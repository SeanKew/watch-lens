import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/gemini_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _customCtrl;
  late String _model;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _keyCtrl = TextEditingController(text: s.apiKey);
    _customCtrl = TextEditingController(text: s.customModel);
    _model = s.model;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  String _labelFor(String id) =>
      id == GeminiModels.flashLite ? 'Flash-Lite（默认）' : 'Flash';

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _keyCtrl.text = text);
    }
  }

  Future<void> _save() async {
    await context.read<SettingsProvider>().save(
          apiKey: _keyCtrl.text.trim(),
          model: _model,
          customModel: _customCtrl.text.trim(),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Gemini API Key', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _keyCtrl,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: '粘贴你的 API Key',
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '粘贴',
                    icon: const Icon(Icons.content_paste),
                    onPressed: _paste,
                  ),
                  IconButton(
                    tooltip: _obscure ? '显示' : '隐藏',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '免费 Key 可在 Google AI Studio（aistudio.google.com/apikey）创建。Key 仅保存在本机。',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Text('识别模型', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final id in GeminiModels.all)
                  ButtonSegment(value: id, label: Text(_labelFor(id))),
              ],
              selected: {_model},
              onSelectionChanged: (s) => setState(() => _model = s.first),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _model,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customCtrl,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '自定义模型 ID（可选）',
              hintText: '留空则使用上方选择',
              helperText: '填写后优先使用，例如官方更新后的模型名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '识别时，抠图后的手表图片会发送至 Google Gemini API；'
                      '本地数据库只保存文字，不会保存任何图片。',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
