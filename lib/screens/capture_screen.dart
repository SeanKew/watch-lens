import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/watch_record.dart';
import '../providers/library_provider.dart';
import '../providers/recognition_provider.dart';
import '../providers/settings_provider.dart';
import '../services/gemini_service.dart';
import '../services/segmentation_service.dart';
import '../widgets/checker_board.dart';
import '../widgets/watch_info_section.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';

/// 拍照 / 选图 → 端侧抠图预览 → Gemini 识别 → 保存。
class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key, required this.source});

  final ImageSource source;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => RecognitionProvider(
        segmentation: ctx.read<SegmentationService>(),
        gemini: ctx.read<GeminiService>(),
      ),
      child: _CaptureView(source: source),
    );
  }
}

enum _DuplicateChoice { cancel, merge, overwrite }

class _CaptureView extends StatefulWidget {
  const _CaptureView({required this.source});

  final ImageSource source;

  @override
  State<_CaptureView> createState() => _CaptureViewState();
}

class _CaptureViewState extends State<_CaptureView> {
  final _picker = ImagePicker();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    final rec = context.read<RecognitionProvider>();
    try {
      final file = await _picker.pickImage(
        source: widget.source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (!mounted) return;
      if (file == null) {
        // 首次进入就取消 → 直接返回首页
        if (rec.stage == RecognitionStage.idle) Navigator.of(context).pop();
        return;
      }
      await rec.processImage(file.path);
    } catch (e) {
      if (mounted) rec.fail('无法获取图片：$e');
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _identify() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中填写 Gemini API Key'),
          action: SnackBarAction(label: '去设置', onPressed: _openSettings),
        ),
      );
      return;
    }
    await context.read<RecognitionProvider>().identify(
          apiKey: settings.apiKey,
          model: settings.effectiveModel,
        );
  }

  Future<void> _save() async {
    if (_saving) return;
    final lib = context.read<LibraryProvider>();
    final record = context.read<RecognitionProvider>().record;
    if (record == null) return;

    setState(() => _saving = true);
    try {
      final dup = await lib.findDuplicate(record);
      WatchRecord saved;

      if (dup == null) {
        saved = await lib.insert(record);
      } else {
        if (!mounted) return;
        final choice = await _askDuplicate(dup);
        if (choice == null || choice == _DuplicateChoice.cancel) return;
        saved = choice == _DuplicateChoice.merge
            ? await lib.overwrite(dup.id!, mergeRecords(dup, record))
            : await lib.overwrite(dup.id!, record);
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DetailScreen(record: saved)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_DuplicateChoice?> _askDuplicate(WatchRecord dup) {
    return showDialog<_DuplicateChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('数据库已有记录'),
        content: Text(
          '“${dup.displayTitle}”已在图库中（最近更新 ${formatDateTime(dup.updatedAt)}）。\n\n'
          '合并更新：用新结果补充/修正，缺失的字段保留旧值。\n'
          '完全覆盖：整条记录替换为本次识别结果。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DuplicateChoice.cancel),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, _DuplicateChoice.merge),
            child: const Text('合并更新'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _DuplicateChoice.overwrite),
            child: const Text('完全覆盖'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rec = context.watch<RecognitionProvider>();

    final title = switch (rec.stage) {
      RecognitionStage.result => '识别结果',
      RecognitionStage.error => '出错了',
      _ => '抠图预览',
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: _buildBody(rec)),
    );
  }

  Widget _buildBody(RecognitionProvider rec) {
    switch (rec.stage) {
      case RecognitionStage.idle:
      case RecognitionStage.segmenting:
        return _Centered(
          icon: const CircularProgressIndicator(),
          text: rec.stage == RecognitionStage.segmenting ? '正在端侧抠图…' : '正在打开…',
        );

      case RecognitionStage.preview:
        return _buildPreview(rec, busy: false);

      case RecognitionStage.identifying:
        return _buildPreview(rec, busy: true);

      case RecognitionStage.result:
        return _buildResult(rec);

      case RecognitionStage.error:
        return _buildError(rec);
    }
  }

  Widget _buildPreview(RecognitionProvider rec, {required bool busy}) {
    final seg = rec.segmentation!;
    final theme = Theme.of(context);

    return Column(
      children: [
        if (!seg.segmented)
          Container(
            width: double.infinity,
            color: theme.colorScheme.tertiaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              rec.segmenterSupported
                  ? '未检测到明确的手表主体，将使用原图识别。建议把表放在纯色背景上重拍。'
                  : '当前平台暂不支持端侧抠图（仅 Android），将使用原图识别。',
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CheckerBoard(
                    child: Center(
                      child: Image.memory(
                        seg.previewPng,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  if (busy)
                    Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Gemini 正在识别…', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _pick,
                  icon: const Icon(Icons.refresh),
                  label: Text(widget.source == ImageSource.camera ? '重拍' : '重选'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: busy ? null : _identify,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('确认并识别'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult(RecognitionProvider rec) {
    final seg = rec.segmentation!;
    final record = rec.record!;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox.expand(
                    child: CheckerBoard(
                      child: Center(
                        child: Image.memory(seg.previewPng, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              WatchInfoSection(record: record),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _identify,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新识别'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bookmark_add_outlined),
                  label: const Text('保存到图库'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError(RecognitionProvider rec) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              rec.errorMessage ?? '发生未知错误',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            if (rec.canRetryIdentify)
              FilledButton.icon(
                onPressed: _identify,
                icon: const Icon(Icons.refresh),
                label: const Text('重试识别'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.image_outlined),
              label: const Text('重新选择图片'),
            ),
            if (rec.canRetryIdentify)
              TextButton(onPressed: _openSettings, child: const Text('检查设置')),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text});

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [icon, const SizedBox(height: 16), Text(text)],
      ),
    );
  }
}
