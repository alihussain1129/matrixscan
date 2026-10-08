import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import 'history_entry.dart';

/// "Today, 14:05", "Yesterday, 09:30" or "8 Oct 2026, 14:05".
String formatHistoryTime(DateTime time, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}';
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today, $clock';
  if (diff == 1) return 'Yesterday, $clock';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${time.day} ${months[time.month - 1]} ${time.year}, $clock';
}

String historyTypeLabel(HistoryEntry entry) {
  final format = entry.format;
  if (format != null && format.isNotEmpty) return format;
  return entry.kind == HistoryKind.ocr ? 'Text (OCR)' : 'Barcode';
}

String historySourceLabel(HistorySource source) {
  switch (source) {
    case HistorySource.live:
      return 'Camera';
    case HistorySource.gallery:
      return 'Gallery';
    case HistorySource.ocr:
      return 'OCR';
  }
}

IconData _iconFor(HistoryEntry entry) {
  if (entry.kind == HistoryKind.ocr) return Icons.text_snippet_outlined;
  final format = entry.format ?? '';
  if (format.contains('QR')) return Icons.qr_code_2;
  if (format.contains('Data Matrix') || format.contains('Aztec')) {
    return Icons.grid_view;
  }
  return Icons.view_week_outlined;
}

/// One row in the History list.
class HistoryItemTile extends StatelessWidget {
  const HistoryItemTile({super.key, required this.entry, this.onTap});

  final HistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(_iconFor(entry), color: scheme.primary),
      ),
      title: Text(
        entry.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: text.bodyLarge,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${historyTypeLabel(entry)} · ${historySourceLabel(entry.source)}'
          '\n${formatHistoryTime(entry.createdAt, DateTime.now())}',
          style: text.bodySmall,
        ),
      ),
      isThreeLine: true,
      trailing: entry.pinned
          ? Icon(Icons.push_pin, size: 18, color: scheme.primary)
          : null,
    );
  }
}
