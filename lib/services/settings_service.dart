import 'package:shared_preferences/shared_preferences.dart';

import 'gemini_service.dart';

class AppSettings {
  final String apiKey;
  final String model;
  final String customModel;
  const AppSettings({
    required this.apiKey,
    required this.model,
    required this.customModel,
  });
}

/// 设置持久化（SharedPreferences）。
/// 如需更高安全级别，可把 API Key 换成 flutter_secure_storage。
class SettingsService {
  static const _kApiKey = 'gemini_api_key';
  static const _kModel = 'gemini_model';
  static const _kCustomModel = 'gemini_custom_model';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString(_kModel);
    return AppSettings(
      apiKey: prefs.getString(_kApiKey) ?? '',
      model: GeminiModels.all.contains(model) ? model! : GeminiModels.defaultModel,
      customModel: prefs.getString(_kCustomModel) ?? '',
    );
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, s.apiKey);
    await prefs.setString(_kModel, s.model);
    await prefs.setString(_kCustomModel, s.customModel);
  }
}
