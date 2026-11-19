import 'dart:convert';

import 'package:dio/dio.dart';

/// 一张网络参考图（仅内存 / 缓存使用，不入库）。
class WatchImage {
  /// 主展示图
  final String url;

  /// 缩略图（主图加载失败时作为备选）
  final String thumbUrl;
  final String title;

  /// 来源名称，如 "Wikimedia Commons"
  final String source;

  const WatchImage({
    required this.url,
    required this.thumbUrl,
    required this.title,
    required this.source,
  });
}

class ImageSearchException implements Exception {
  final String message;
  const ImageSearchException(this.message);
  @override
  String toString() => 'ImageSearchException: $message';
}

/// 免 API Key 的联网搜图：
///   1. Wikimedia Commons 官方 API（合规稳定，但冷门型号可能没有图）
///   2. DuckDuckGo 图片检索（非官方接口，作为补充；可能随时失效）
/// 结果仅做内存缓存；图片本体由 cached_network_image 临时缓存。
class ImageSearchService {
  ImageSearchService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              // Wikimedia 要求 User-Agent 带上应用名与联系方式，请替换为你自己的邮箱
              headers: {'User-Agent': _wikimediaUserAgent},
            ));

  final Dio _dio;

  static const _wikimediaUserAgent =
      'WatchLens/0.1 (Flutter personal watch catalog; contact: YOUR_EMAIL@example.com)';
  static const _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Mobile Safari/537.36';

  static const _wanted = 8;
  static const _enough = 3;
  static const _okMimes = {'image/jpeg', 'image/png', 'image/webp'};
  static final _noise = RegExp(
    r'\b(official|product|photo|photos|image|images|picture|pictures|hd)\b',
    caseSensitive: false,
  );

  final Map<String, List<WatchImage>> _cache = {};

  /// [query] 通常是记录里的 image_search_query；[fallbackQuery] 是更短的兜底词（品牌+型号）。
  /// 没有任何结果时返回空列表；仅当所有来源都因网络等原因失败时才抛异常。
  Future<List<WatchImage>> search(
    String query, {
    String? fallbackQuery,
    bool forceRefresh = false,
  }) async {
    final queries = <String>[];
    for (final q in [query, fallbackQuery ?? '']) {
      final t = q.trim();
      if (t.isNotEmpty && !queries.contains(t)) queries.add(t);
    }
    if (queries.isEmpty) return const [];

    final key = queries.join('|').toLowerCase();
    if (!forceRefresh) {
      final hit = _cache[key];
      if (hit != null) return hit;
    }

    final found = <WatchImage>[];
    final seen = <String>{};
    Object? lastError;
    var anySourceOk = false;

    Future<void> attempt(
      Future<List<WatchImage>> Function(String) source,
      String q,
    ) async {
      try {
        final list = await source(q);
        anySourceOk = true;
        for (final img in list) {
          if (seen.add(img.url)) found.add(img);
        }
      } catch (e) {
        lastError = e;
      }
    }

    for (final q in queries) {
      await attempt(_searchWikimedia, q);
      if (found.length >= _enough) break;
    }
    if (found.length < _enough) {
      for (final q in queries) {
        await attempt(_searchDuckDuckGo, q);
        if (found.length >= _wanted) break;
      }
    }

    if (found.isEmpty && !anySourceOk && lastError != null) {
      throw ImageSearchException(_describe(lastError!));
    }

    final result = List<WatchImage>.unmodifiable(found.take(_wanted));
    if (result.isNotEmpty) _cache[key] = result;
    return result;
  }

  // ───────────────────────── Wikimedia Commons ─────────────────────────

  Future<List<WatchImage>> _searchWikimedia(String rawQuery) async {
    final q = rawQuery.replaceAll(_noise, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.isEmpty) return const [];

    final resp = await _dio.get<dynamic>(
      'https://commons.wikimedia.org/w/api.php',
      queryParameters: {
        'action': 'query',
        'format': 'json',
        'generator': 'search',
        'gsrnamespace': 6, // File:
        'gsrlimit': 12,
        'gsrsearch': '$q filetype:bitmap',
        'prop': 'imageinfo',
        'iiprop': 'url|mime|size',
        'iiurlwidth': 800,
      },
    );

    final data = resp.data;
    final pages = (data is Map && data['query'] is Map) ? data['query']['pages'] : null;
    if (pages is! Map) return const [];

    num indexOf(Map m) => (m['index'] is num) ? m['index'] as num : 999;
    final entries = pages.values.whereType<Map>().toList()
      ..sort((a, b) => indexOf(a).compareTo(indexOf(b)));

    final out = <WatchImage>[];
    for (final p in entries) {
      final infos = p['imageinfo'];
      if (infos is! List || infos.isEmpty || infos.first is! Map) continue;
      final info = infos.first as Map;

      if (!_okMimes.contains(info['mime']?.toString())) continue;
      final width = (info['width'] is num) ? (info['width'] as num).toInt() : 0;
      if (width < 300) continue;

      final url = (info['thumburl'] ?? info['url'])?.toString() ?? '';
      if (!url.startsWith('https://')) continue;

      final title = (p['title']?.toString() ?? '')
          .replaceFirst(RegExp(r'^File:'), '')
          .replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
      out.add(WatchImage(
        url: url,
        thumbUrl: url,
        title: title,
        source: 'Wikimedia Commons',
      ));
    }
    return out;
  }

  // ───────────────────────── DuckDuckGo ─────────────────────────

  Future<List<WatchImage>> _searchDuckDuckGo(String q) async {
    final headers = {
      'User-Agent': _browserUserAgent,
      'Referer': 'https://duckduckgo.com/',
    };

    // 第一步：取得 vqd 令牌
    final home = await _dio.get<String>(
      'https://duckduckgo.com/',
      queryParameters: {'q': q, 'iax': 'images', 'ia': 'images'},
      options: Options(headers: headers, responseType: ResponseType.plain),
    );
    final vqd = RegExp('vqd=["\']?([\\d-]+)["\']?').firstMatch(home.data ?? '')?.group(1);
    if (vqd == null) throw StateError('DuckDuckGo vqd not found');

    // 第二步：取图片 JSON
    final resp = await _dio.get<dynamic>(
      'https://duckduckgo.com/i.js',
      queryParameters: {
        'l': 'us-en',
        'o': 'json',
        'q': q,
        'vqd': vqd,
        'f': ',,,,,',
        'p': '1',
      },
      options: Options(headers: headers),
    );

    final data = resp.data;
    final decoded = data is String ? _tryJson(data) : data;
    final results = (decoded is Map) ? decoded['results'] : null;
    if (results is! List) return const [];

    final out = <WatchImage>[];
    for (final r in results.whereType<Map>()) {
      final image = r['image']?.toString() ?? '';
      final thumb = r['thumbnail']?.toString() ?? '';
      // Android 默认禁止明文 HTTP，只保留 https
      if (!thumb.startsWith('https://')) continue;
      out.add(WatchImage(
        url: image.startsWith('https://') ? image : thumb,
        thumbUrl: thumb,
        title: r['title']?.toString() ?? '',
        source: 'DuckDuckGo',
      ));
      if (out.length >= _wanted) break;
    }
    return out;
  }

  dynamic _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  String _describe(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '联网检索超时，请检查网络后重试。';
        case DioExceptionType.connectionError:
          return '网络连接失败，请检查网络后重试。';
        default:
          break;
      }
    }
    return '图片检索失败，请稍后重试。';
  }
}
