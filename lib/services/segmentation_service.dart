import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class SegmentationException implements Exception {
  final String message;
  const SegmentationException(this.message);
  @override
  String toString() => 'SegmentationException: $message';
}

/// 抠图结果（全部在内存中，不落盘）。
class SegmentationResult {
  /// 带透明通道的 PNG，用于界面预览
  final Uint8List previewPng;

  /// 白底 JPEG（最长边 ≤ 1024px），用于发送给 Gemini
  final Uint8List jpegBytes;

  /// 是否真的执行了主体分割；false 表示回退为原图（平台不支持或未检出主体）
  final bool segmented;

  const SegmentationResult({
    required this.previewPng,
    required this.jpegBytes,
    required this.segmented,
  });

  String get jpegBase64 => base64Encode(jpegBytes);
}

class SegmentationService {
  static const int maxSide = 1024;
  static const int jpegQuality = 85;

  /// 低于此前景占比视为"未检出主体"
  static const double minForegroundRatio = 0.01;

  /// ML Kit 主体分割目前仅 Android 可用；iOS 暂时回退为原图直传。
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  SubjectSegmenter? _segmenter;

  SubjectSegmenter _getSegmenter() {
    return _segmenter ??= SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundConfidenceMask: true,
        enableForegroundBitmap: false,
        enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: false,
          enableSubjectBitmap: false,
        ),
      ),
    );
  }

  /// [imagePath]：相机或相册返回的图片路径。
  Future<SegmentationResult> process(String imagePath) async {
    final srcBytes = await File(imagePath).readAsBytes();

    // 1) 解码 + 修正 EXIF 方向 + 缩放到最长边 ≤ 1024（放到后台 isolate）
    final prepared = await compute(_prepareImage, srcBytes);
    if (prepared == null) {
      throw const SegmentationException('无法解码这张图片，请换一张。');
    }

    // 2) 端侧主体分割，拿到前景置信度蒙版
    List<double>? mask;
    if (isSupported) {
      mask = await _runSegmentation(prepared);
    }

    // 3) 应用蒙版、裁剪到主体包围盒、输出 PNG 预览 + 白底 JPEG
    final out = await compute(
      _compose,
      _ComposeInput(prepared.jpeg, prepared.width, prepared.height, mask),
    );
    return SegmentationResult(
      previewPng: out.png,
      jpegBytes: out.jpeg,
      segmented: out.segmented,
    );
  }

  Future<List<double>?> _runSegmentation(_Prepared prepared) async {
    final tmpDir = await getTemporaryDirectory();
    final tmpFile = File(
      '${tmpDir.path}/wl_seg_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    try {
      await tmpFile.writeAsBytes(prepared.jpeg, flush: true);
      final result =
          await _getSegmenter().processImage(InputImage.fromFilePath(tmpFile.path));
      final mask = result.foregroundConfidenceMask;
      if (mask == null || mask.isEmpty) return null;
      if (mask.length != prepared.width * prepared.height) {
        throw const SegmentationException('分割蒙版尺寸与图片不一致。');
      }
      return mask;
    } on SegmentationException {
      rethrow;
    } catch (e) {
      throw SegmentationException('端侧抠图失败：$e');
    } finally {
      // 临时文件用完即删，保证不在手机上留存图片
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
    }
  }

  Future<void> dispose() async {
    await _segmenter?.close();
    _segmenter = null;
  }
}

// ═══════════════ 以下为 isolate 内执行的纯函数 ═══════════════

class _Prepared {
  final Uint8List jpeg;
  final int width;
  final int height;
  const _Prepared(this.jpeg, this.width, this.height);
}

class _ComposeInput {
  final Uint8List jpeg;
  final int width;
  final int height;
  final List<double>? mask;
  const _ComposeInput(this.jpeg, this.width, this.height, this.mask);
}

class _ComposeOutput {
  final Uint8List png;
  final Uint8List jpeg;
  final bool segmented;
  const _ComposeOutput(this.png, this.jpeg, this.segmented);
}

_Prepared? _prepareImage(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;

  image = img.bakeOrientation(image);

  if (math.max(image.width, image.height) > SegmentationService.maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: SegmentationService.maxSide)
        : img.copyResize(image, height: SegmentationService.maxSide);
  }

  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 92));
  return _Prepared(jpeg, image.width, image.height);
}

_ComposeOutput _compose(_ComposeInput input) {
  final src = img.decodeJpg(input.jpeg)!;
  final mask = input.mask;

  // 无蒙版 → 回退原图
  if (mask == null) return _fallback(src, input.jpeg);

  final w = src.width;
  final h = src.height;

  // 统计前景包围盒
  var minX = w, minY = h, maxX = -1, maxY = -1, fg = 0;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      if (mask[row + x] >= 0.5) {
        fg++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0 || fg < w * h * SegmentationService.minForegroundRatio) {
    return _fallback(src, input.jpeg);
  }

  // 四周留 4% 边距
  final padX = ((maxX - minX + 1) * 0.04).round();
  final padY = ((maxY - minY + 1) * 0.04).round();
  final cx = math.max(0, minX - padX);
  final cy = math.max(0, minY - padY);
  final cw = math.min(w, maxX + padX + 1) - cx;
  final ch = math.min(h, maxY + padY + 1) - cy;

  final rgba = img.Image(width: cw, height: ch, numChannels: 4);
  final flat = img.Image(width: cw, height: ch); // RGB，白底

  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final sx = cx + x;
      final sy = cy + y;
      final px = src.getPixel(sx, sy);
      final r = px.r.toInt();
      final g = px.g.toInt();
      final b = px.b.toInt();

      final c = mask[sy * w + sx];
      final a = c <= 0.05 ? 0 : (c >= 0.95 ? 255 : (c * 255).round());

      rgba.setPixelRgba(x, y, r, g, b, a);

      final inv = 255 - a;
      flat.setPixelRgb(
        x,
        y,
        (r * a + 255 * inv) ~/ 255,
        (g * a + 255 * inv) ~/ 255,
        (b * a + 255 * inv) ~/ 255,
      );
    }
  }

  return _ComposeOutput(
    Uint8List.fromList(img.encodePng(rgba)),
    Uint8List.fromList(
      img.encodeJpg(flat, quality: SegmentationService.jpegQuality),
    ),
    true,
  );
}

_ComposeOutput _fallback(img.Image src, Uint8List jpeg) {
  return _ComposeOutput(
    Uint8List.fromList(img.encodePng(src)),
    jpeg,
    false,
  );
}
