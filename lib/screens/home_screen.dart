import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/watch_record.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/confirm_dialog.dart';
import 'capture_screen.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _startRecognition() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CaptureScreen(source: source)),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WatchLens'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startRecognition,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('识别手表'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onChanged: (v) {
                lib.setQuery(v);
                setState(() {}); // 刷新清除按钮
              },
              decoration: InputDecoration(
                hintText: '搜索品牌、系列、型号、关键词',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          lib.setQuery('');
                          setState(() {});
                        },
                      ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (settings.loaded && !settings.hasApiKey)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                margin: EdgeInsets.zero,
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('尚未设置 Gemini API Key'),
                  subtitle: const Text('填写后才能识别手表'),
                  trailing: TextButton(onPressed: _openSettings, child: const Text('去设置')),
                ),
              ),
            ),
          if (lib.total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  lib.query.trim().isEmpty
                      ? '共 ${lib.total} 条记录'
                      : '找到 ${lib.records.length} 条 / 共 ${lib.total} 条',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          Expanded(child: _buildList(lib)),
        ],
      ),
    );
  }

  Widget _buildList(LibraryProvider lib) {
    if (lib.loading && lib.records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (lib.records.isEmpty) {
      final searching = lib.query.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                searching ? Icons.search_off : Icons.watch_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                searching ? '没有找到匹配的记录' : '还没有识别记录\n点击右下角开始识别第一块表',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: lib.records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = lib.records[i];
        return Dismissible(
          key: ValueKey(r.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => confirmDialog(
            context,
            title: '删除记录',
            message: '确定删除“${r.displayTitle}”吗？',
            confirmText: '删除',
          ),
          onDismissed: (_) => lib.delete(r.id!),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          child: _RecordCard(record: r),
        );
      },
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final WatchRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = [record.brand, record.series].where((e) => e.isNotEmpty).join(' · ');
    final extra = [record.releaseYear, record.estimatedPrice].where((e) => e.isNotEmpty).join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        isThreeLine: record.referenceNumber.isNotEmpty && extra.isNotEmpty,
        title: Text(
          title.isEmpty ? '未知手表' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.referenceNumber.isNotEmpty)
              Text(
                'Ref. ${record.referenceNumber}',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            if (extra.isNotEmpty)
              Text(extra, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DetailScreen(record: record)),
        ),
      ),
    );
  }
}
