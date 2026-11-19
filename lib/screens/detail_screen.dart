import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/watch_record.dart';
import '../providers/library_provider.dart';
import '../services/image_search_service.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/watch_info_section.dart';

/// 详情页：本地只有文字，参考图按需联网检索。
class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.record});

  final WatchRecord record;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Future<List<WatchImage>> _imagesFuture;

  WatchRecord get _r => widget.record;

  /// 兜底关键词：品牌中的英文部分 + 参考型号
  String get _fallbackQuery {
    final asciiBrand =
        RegExp(r'[A-Za-z][A-Za-z0-9&.\- ]*').firstMatch(_r.brand)?.group(0)?.trim() ?? '';
    return [asciiBrand, _r.referenceNumber].where((e) => e.isNotEmpty).join(' ');
  }

  @override
  void initState() {
    super.initState();
    _imagesFuture = _load();
  }

  Future<List<WatchImage>> _load({bool force = false}) {
    return context.read<ImageSearchService>().search(
          _r.imageSearchQuery,
          fallbackQuery: _fallbackQuery,
          forceRefresh: force,
        );
  }

  void _retry() => setState(() => _imagesFuture = _load(force: true));

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: '删除记录',
      message: '确定删除“${_r.displayTitle}”吗？',
      confirmText: '删除',
    );
    if (!ok || !mounted) return;
    final lib = context.read<LibraryProvider>();
    Navigator.of(context).pop();
    await lib.delete(_r.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _r.series.isNotEmpty ? _r.series : _r.brand,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<List<WatchImage>>(
            future: _imagesFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const _ImageBox(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('正在联网检索参考图…'),
                    ],
                  ),
                );
              }
              if (snap.hasError) {
                final e = snap.error;
                return _ImageBox(
                  child: _Notice(
                    icon: Icons.wifi_off_outlined,
                    text: e is ImageSearchException ? e.message : '参考图检索失败。',
                    onRetry: _retry,
                  ),
                );
              }
              final images = snap.data ?? const [];
              if (images.isEmpty) {
                return _ImageBox(
                  child: _Notice(
                    icon: Icons.image_not_supported_outlined,
                    text: '没有找到该款手表的参考图。',
                    onRetry: _retry,
                  ),
                );
              }
              return _Gallery(images: images, onRefresh: _retry);
            },
          ),
          const SizedBox(height: 20),
          WatchInfoSection(record: _r, showTimestamps: true),
        ],
      ),
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.images, required this.onRefresh});

  final List<WatchImage> images;
  final VoidCallback onRefresh;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _ctrl = PageController();
  int _index = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final images = widget.images;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: scheme.surfaceContainerHighest),
                PageView.builder(
                  controller: _ctrl,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _GalleryImage(image: images[i]),
                ),
                if (images.length > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < images.length; i++)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _index ? scheme.primary : scheme.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_index + 1}/${images.length} · ${images[_index].source}'
                '${images[_index].title.isEmpty ? '' : ' · ${images[_index].title}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: '重新检索',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: widget.onRefresh,
            ),
          ],
        ),
        Text(
          '参考图来自网络，仅供参考，版权归原作者所有。',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _GalleryImage extends StatelessWidget {
  const _GalleryImage({required this.image});

  final WatchImage image;

  Widget _spinner() => const Center(child: CircularProgressIndicator(strokeWidth: 2));

  Widget _broken(BuildContext context) => Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.outline,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: image.url,
      fit: BoxFit.contain,
      placeholder: (_, __) => _spinner(),
      // 主图失败 → 退回缩略图 → 再失败显示占位
      errorWidget: (ctx, _, __) {
        if (image.thumbUrl == image.url) return _broken(ctx);
        return CachedNetworkImage(
          imageUrl: image.thumbUrl,
          fit: BoxFit.contain,
          placeholder: (_, __) => _spinner(),
          errorWidget: (c, _, __) => _broken(c),
        );
      },
    );
  }
}
