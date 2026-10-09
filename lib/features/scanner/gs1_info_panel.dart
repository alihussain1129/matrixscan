import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../gs1/gs1_parser.dart';

const List<(String, String)> _keyAis = [
  ('01', 'GTIN'),
  ('10', 'Batch/Lot number'),
  ('17', 'Expiration date'),
  ('21', 'Serial number'),
];

/// Expiry status calculated on this device from the date on the barcode.
/// Null when the date cannot be interpreted.
String? expiryStatus(Gs1Field field, DateTime now) {
  final parsed = parseGs1Date(field.value, now: now);
  if (parsed == null) return null;
  final today = DateTime(now.year, now.month, now.day);
  final end = parsed.date;
  if (end.isBefore(today)) return 'Expired';
  if (end.difference(today).inDays <= 30) return 'Near expiry (within 30 days)';
  return 'Not expired';
}

/// GS1 fields read from decoded text. Shows what the barcode contains and
/// what it does not; it makes no database or authenticity claim.
class Gs1InfoPanel extends StatelessWidget {
  const Gs1InfoPanel({
    super.key,
    required this.result,
    this.showRaw = true,
    this.now,
  });

  final Gs1ParseResult result;

  /// Show the raw decoded text under the fields.
  final bool showRaw;

  /// Clock for expiry status; defaults to the current time.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final clock = now ?? DateTime.now();

    final shown = <Gs1Field>{};
    final tiles = <Widget>[];
    for (final (ai, label) in _keyAis) {
      Gs1Field? found;
      for (final f in result.fields) {
        if (f.ai == ai) {
          found = f;
          break;
        }
      }
      if (found != null) shown.add(found);
      tiles.add(_FieldTile(label: label, ai: ai, field: found, now: clock));
    }
    for (final f in result.fields) {
      if (!shown.contains(f)) {
        tiles.add(_FieldTile(label: f.name, ai: f.ai, field: f, now: clock));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('GS1-formatted text', style: text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Read from the decoded text only. The symbol is not confirmed as '
          'GS1, and nothing was checked against a database.',
          style: text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        ...tiles,
        if (result.unparsed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Could not interpret: ${result.unparsed}',
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        if (showRaw) ...[
          Text('Raw decoded data', style: text.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(result.original, style: text.bodyMedium),
        ],
      ],
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.ai,
    required this.field,
    required this.now,
  });

  final String label;
  final String ai;
  final Gs1Field? field;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final f = field;

    IconData icon;
    Color color;
    if (f == null) {
      icon = Icons.remove_circle_outline;
      color = scheme.onSurfaceVariant;
    } else {
      switch (f.status) {
        case Gs1FieldStatus.valid:
          icon = Icons.check_circle_outline;
          color = scheme.primary;
        case Gs1FieldStatus.invalid:
          icon = Icons.error_outline;
          color = scheme.error;
        case Gs1FieldStatus.unknownAi:
          icon = Icons.help_outline;
          color = scheme.onSurfaceVariant;
      }
    }

    final lines = <Widget>[
      Text('$label (AI $ai)', style: text.bodySmall),
    ];
    if (f == null) {
      lines.add(Text('Not present in barcode', style: text.bodyMedium));
    } else {
      lines.add(Text(f.display, style: text.bodyMedium));
      if (f.display != f.value) {
        lines.add(Text('Encoded: ${f.value}', style: text.bodySmall));
      }
      if (f.error != null) {
        lines.add(
          Text(f.error!, style: text.bodySmall?.copyWith(color: scheme.error)),
        );
      }
      if (f.isValid && gs1AiTable[f.ai]?.type == Gs1ValueType.gtin) {
        lines.add(Text('Check digit OK', style: text.bodySmall));
      }
      if (f.isValid && f.ai == '17') {
        final status = expiryStatus(f, now);
        if (status != null) {
          lines.add(
            Text(
              status,
              style: text.bodySmall?.copyWith(
                color: status == 'Expired' ? scheme.error : null,
              ),
            ),
          );
        }
      }
      if (f.status == Gs1FieldStatus.unknownAi) {
        lines.add(Text('Not interpreted by EXALTED', style: text.bodySmall));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
          ),
        ],
      ),
    );
  }
}