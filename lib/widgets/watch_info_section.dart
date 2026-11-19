import 'package:flutter/material.dart';

import '../models/watch_record.dart';

String formatDateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 手表信息展示：标题 + 规格表 + 简评。识别结果页与详情页共用。
class WatchInfoSection extends StatelessWidget {
  const WatchInfoSection({
    super.key,
    required this.record,
    this.showTimestamps = false,
  });

  final WatchRecord record;
  final bool showTimestamps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final rows = <_SpecRow>[
      _SpecRow(Icons.settings_outlined, '机芯', record.movement),
      _SpecRow(Icons.straighten, '表径', record.caseDiameter),
      _SpecRow(Icons.water_drop_outlined, '防水', record.waterResistance),
      _SpecRow(Icons.calendar_month_outlined, '发售年份', record.releaseYear),
      _SpecRow(Icons.sell_outlined, '参考公价', record.estimatedPrice),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          record.brand.isEmpty ? '未知品牌' : record.brand,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (record.series.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(record.series, style: theme.textTheme.titleMedium),
        ],
        if (record.referenceNumber.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Ref. ${record.referenceNumber}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 52),
                rows[i],
              ],
            ],
          ),
        ),
        if (record.summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('简评', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(record.summary, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                ],
              ),
            ),
          ),
        ],
        if (showTimestamps) ...[
          const SizedBox(height: 12),
          Text(
            '首次识别 ${formatDateTime(record.createdAt)}  ·  最近更新 ${formatDateTime(record.updatedAt)}',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
