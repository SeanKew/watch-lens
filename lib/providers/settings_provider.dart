import 'package:flutter/foundation.dart';

import '../services/gemini_service.dart';
import '../services/settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._service);

  final SettingsService _service;

  String apiKey = '';
  String model = GeminiModels.defaultModel;
  String customModel = '';
  bool loaded = false;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// 实际使用的模型：填了自定义 ID 就用自定义，否则用下拉选择的。
  String get effectiveModel =>
      customModel.trim().isNotEmpty ? customModel.trim() : model;

  Future<void> load() async {
    final s = await _service.load();
    apiKey = s.apiKey;
    model = s.model;
    customModel = s.customModel;
    loaded = true;
    notifyListeners();
  }

  Future<void> save({
    required String apiKey,
    required String model,
    required String customModel,
  }) async {
    this.apiKey = apiKey;
    this.model = model;
    this.customModel = customModel;
    notifyListeners();
    await _service.save(AppSettings(
      apiKey: apiKey,
      model: model,
      customModel: customModel,
    ));
  }
}
