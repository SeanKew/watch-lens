import 'package:flutter/foundation.dart';

import '../models/watch_record.dart';
import '../services/gemini_service.dart';
import '../services/segmentation_service.dart';

enum RecognitionStage { idle, segmenting, preview, identifying, result, error }

/// 单次「选图 → 抠图 → 识别」流程的状态。随 CaptureScreen 创建与销毁，
/// 页面关闭后图片字节即被释放。
class RecognitionProvider extends ChangeNotifier {
  RecognitionProvider({
    required SegmentationService segmentation,
    required GeminiService gemini,
  })  : _seg = segmentation,
        _gemini = gemini;

  final SegmentationService _seg;
  final GeminiService _gemini;

  RecognitionStage stage = RecognitionStage.idle;
  SegmentationResult? segmentation;
  WatchRecord? record;
  String? errorMessage;
  bool _disposed = false;

  bool get segmenterSupported => _seg.isSupported;
  bool get canRetryIdentify => segmentation != null;

  Future<void> processImage(String path) async {
    stage = RecognitionStage.segmenting;
    segmentation = null;
    record = null;
    errorMessage = null;
    _notify();

    try {
      segmentation = await _seg.process(path);
      stage = RecognitionStage.preview;
    } on SegmentationException catch (e) {
      fail(e.message);
      return;
    } catch (e) {
      fail('处理图片失败：$e');
      return;
    }
    _notify();
  }

  Future<void> identify({required String apiKey, required String model}) async {
    final seg = segmentation;
    if (seg == null) return;

    stage = RecognitionStage.identifying;
    errorMessage = null;
    _notify();

    try {
      record = await _gemini.identifyWatch(
        imageBase64: seg.jpegBase64,
        apiKey: apiKey,
        model: model,
      );
      stage = RecognitionStage.result;
    } on GeminiException catch (e) {
      errorMessage = e.message;
      stage = RecognitionStage.error;
    } catch (e) {
      errorMessage = '识别失败：$e';
      stage = RecognitionStage.error;
    }
    _notify();
  }

  void fail(String message) {
    errorMessage = message;
    stage = RecognitionStage.error;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 「合并更新」：新结果里非空的字段覆盖旧值，新结果缺失的字段保留旧值。
WatchRecord mergeRecords(WatchRecord old, WatchRecord fresh) {
  String pick(String n, String o) => n.trim().isNotEmpty ? n : o;
  return old.copyWith(
    brand: pick(fresh.brand, old.brand),
    series: pick(fresh.series, old.series),
    referenceNumber: pick(fresh.referenceNumber, old.referenceNumber),
    movement: pick(fresh.movement, old.movement),
    caseDiameter: pick(fresh.caseDiameter, old.caseDiameter),
    waterResistance: pick(fresh.waterResistance, old.waterResistance),
    releaseYear: pick(fresh.releaseYear, old.releaseYear),
    estimatedPrice: pick(fresh.estimatedPrice, old.estimatedPrice),
    summary: pick(fresh.summary, old.summary),
    imageSearchQuery: pick(fresh.imageSearchQuery, old.imageSearchQuery),
  );
}
