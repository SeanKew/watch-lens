import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/watch_record.dart';

/// 可选模型。模型 ID 请以 Google AI Studio 当前列表为准，若返回 404 在此修改即可。
class GeminiModels {
  GeminiModels._();
  static const flashLite = 'gemini-3.5-flash-lite';
  static const flash = 'gemini-3.8-flash';
  static const defaultModel = flashLite;
  static const all = [flashLite, flash];
}

class GeminiException implements Exception {
  final String message;
  final int? statusCode;
  const GeminiException(this.message, {this.statusCode});

  @override
  String toString() => 'GeminiException($statusCode): $message';
}

class GeminiService {
  GeminiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
            ));

  final Dio _dio;

  /// 503/500 等瞬时错误的最大重试次数
  static const _maxRetries = 1;

  static const _systemPrompt = r'''
你是一位资深的腕表鉴定与数据库编辑专家。用户会发送一张已去除背景的手表图片。
请依据表盘、表壳、表冠、表带、字面细节等特征识别这只手表，并且只输出一个 JSON 对象。

严格要求：
1. 只输出 JSON，不要有任何解释、前后缀文字或 Markdown 代码块。
2. 所有字段值均为字符串（is_watch 为布尔值）；无法确定的字段填空字符串 ""，绝不编造。
3. brand：中英文并列，如 "Rolex 劳力士"。
4. series：系列名，如 "Submariner 潜航者"。
5. reference_number：尽可能精确的官方参考型号，如 "126610LN"；若只能判断到系列，填写最可能的型号并在 summary 中说明不确定性。
6. movement：机芯类型及型号，如 "自动机械 Cal.3235"。
7. case_diameter：如 "41mm"；water_resistance：如 "300m"。
8. release_year：大致发售年份或区间，如 "2020"。
9. estimated_price：参考公价区间并注明币种，如 "约 ¥85,000 – ¥95,000（人民币官方公价，仅供参考）"。
10. summary：100–200 字中文，介绍核心特点与历史背景，并说明识别把握程度。
11. image_search_query：英文，用于检索该款高清官图的最佳关键词，格式如 "Rolex Submariner Date 126610LN official product photo"。
12. 若图片中没有手表，is_watch 设为 false，其余字段全部填 ""。
''';

  static const _userPrompt = '请识别这只手表，并严格按要求返回 JSON。';

  static const _fields = [
    'is_watch',
    'brand',
    'series',
    'reference_number',
    'movement',
    'case_diameter',
    'water_resistance',
    'release_year',
    'estimated_price',
    'summary',
    'image_search_query',
  ];

  static final Map<String, dynamic> _responseSchema = {
    'type': 'OBJECT',
    'properties': {
      for (final f in _fields)
        f: {'type': f == 'is_watch' ? 'BOOLEAN' : 'STRING'},
    },
    'required': _fields,
    'propertyOrdering': _fields,
  };

  /// 识别手表。[imageBase64] 为不带 data: 前缀的纯 Base64（JPEG）。
  Future<WatchRecord> identifyWatch({
    required String imageBase64,
    required String apiKey,
    String model = GeminiModels.defaultModel,
    String mimeType = 'image/jpeg',
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const GeminiException('尚未设置 Gemini API Key，请先到设置页填写。');
    }

    final body = {
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt}
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'inlineData': {'mimeType': mimeType, 'data': imageBase64}
            },
            {'text': _userPrompt},
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
        'responseSchema': _responseSchema,
      },
    };

    final response = await _post('/models/$model:generateContent', body, apiKey.trim());
    final json = _parseResponse(response.data);

    if (json['is_watch'] == false) {
      throw const GeminiException('图片中未识别到手表，请换一张更清晰的照片。');
    }
    return WatchRecord.fromGeminiJson(json);
  }

  // ───────────────────────── 内部实现 ─────────────────────────

  Future<Response<dynamic>> _post(
    String path,
    Map<String, dynamic> body,
    String apiKey,
  ) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await _dio.post<dynamic>(
          path,
          data: body,
          options: Options(headers: {
            // Key 放在请求头而不是 URL 查询参数，避免被日志记录
            'x-goog-api-key': apiKey,
            'Content-Type': 'application/json',
          }),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final transient = status == 500 || status == 503;
        if (transient && attempt < _maxRetries) {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          continue;
        }
        throw _mapDioError(e);
      }
    }
  }

  Map<String, dynamic> _parseResponse(dynamic data) {
    if (data is! Map) {
      throw const GeminiException('服务器返回了无法解析的数据。');
    }
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      final block = (data['promptFeedback'] is Map)
          ? data['promptFeedback']['blockReason']
          : null;
      throw GeminiException(
        block != null ? '请求被安全策略拦截（$block）。' : '模型没有返回任何结果，请重试。',
      );
    }

    final first = candidates.first;
    final parts = (first is Map && first['content'] is Map)
        ? first['content']['parts']
        : null;
    if (parts is! List) {
      final reason = first is Map ? first['finishReason'] : null;
      throw GeminiException('模型返回内容为空${reason != null ? '（$reason）' : ''}。');
    }

    // 忽略 thinking 片段，只拼接正文
    final text = parts
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => p['text'])
        .whereType<String>()
        .join();

    return _extractJson(text);
  }

  /// 即使开启了 JSON 模式，也兜底剥离 ```json 围栏与多余文字。
  Map<String, dynamic> _extractJson(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const GeminiException('模型没有返回有效的 JSON，请重试。');
    }
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('not an object');
    } on FormatException {
      throw const GeminiException('模型返回的 JSON 格式有误，请重试。');
    }
  }

  GeminiException _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const GeminiException('请求超时，请检查网络后重试。');
      case DioExceptionType.connectionError:
        return const GeminiException('网络连接失败，请检查网络（部分地区需要可访问 Google 服务的网络环境）。');
      default:
        break;
    }

    final status = e.response?.statusCode;
    final apiMsg = _apiErrorMessage(e.response?.data);
    switch (status) {
      case 400:
        if ((apiMsg ?? '').toLowerCase().contains('api key')) {
          return GeminiException('API Key 无效，请检查设置。', statusCode: status);
        }
        return GeminiException('请求参数有误：${apiMsg ?? '未知原因'}', statusCode: status);
      case 401:
      case 403:
        return GeminiException('API Key 无权限或已失效：${apiMsg ?? ''}', statusCode: status);
      case 404:
        return GeminiException('模型不可用，请在设置中切换模型。${apiMsg ?? ''}', statusCode: status);
      case 429:
        return GeminiException('已达到免费额度或请求过于频繁，请稍后再试或切换模型。', statusCode: status);
      case 500:
      case 503:
        return GeminiException('Gemini 服务暂时繁忙，请稍后重试。', statusCode: status);
      default:
        return GeminiException('请求失败（${status ?? '未知'}）：${apiMsg ?? e.message ?? ''}',
            statusCode: status);
    }
  }

  String? _apiErrorMessage(dynamic data) {
    if (data is Map && data['error'] is Map) {
      return data['error']['message']?.toString();
    }
    return null;
  }
}
