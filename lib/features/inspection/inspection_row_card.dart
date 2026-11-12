import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'combined_inspector.dart';
import 'gs1_fields.dart';
import 'inspection_data_screen.dart';
import 'inspection_log.dart';
import 'inspection_row.dart';

Color rowStatusColor(BuildContext context, RowStatus s) {
  switch (s) {
    case RowStatus.pass:
      return context.exalted.valid;
    case RowStatus.fail:
      return Theme.of(context).colorScheme.error;
    case RowStatus.review:
      return const Color(0xFFE5A100);
  }
}

class RowStatusChip extends StatelessWidget {
  const RowStatusChip(this.status, {super.key});

  final RowStatus status;

  @override
  Widget build(BuildContext context) {
    final color = rowStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// The latest inspection as one related data row: decoded fields next to
/// whether the printed text agrees, plus the checks and the OCR text.
class InspectionRowCard extends ConsumerWidget {
  const InspectionRowCard({super.key});

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inspector = ref.watch(combinedInspectorProvider);
    final row = inspector.latest;
    final theme = Theme.of(context);
    final colors = context.exalted;
    final muted = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 12,
      color: colors.muted,
    );

    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              'INSPECTION ROW',
              style: theme.textTheme.labelSmall!.copyWith(
                color: colors.muted,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (inspector.ocrBusy) Text('Reading printed text…', style: muted),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
    ];

    if (row == null) {
      children.add(
        Text(
          'No inspection recorded yet. Every new code adds one row.',
          style: muted,
        ),
      );
    } else {
      final t = row.createdAt;
      children.add(
        Row(
          children: [
            RowStatusChip(row.status),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}  ·  ${row.symbology}',
              style: muted,
            ),
          ],
        ),
      );
      children.add(const SizedBox(height: AppSpacing.sm));

      if (row.fields.isEmpty) {
        children.add(_line(context, 'Value', row.raw, null));
      } else {
        for (final e in row.fields.entries) {
          final field = Gs1Field(e.key, e.value);
          bool? printed;
          if (row.ocrText != null && row.ocrText!.trim().isNotEmpty) {
            printed = InspectionLog.ocrContains(row.ocrText!, e.value);
          }
          children.add(_line(context, field.label, field.display, printed));
        }
      }

      if (row.fields.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Last column: does the printed text (OCR) contain this value?',
              style: muted,
            ),
          ),
        );
      }

      for (final reason in row.reasons) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: rowStatusColor(context, row.status),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(reason, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        );
      }

      children.add(const SizedBox(height: AppSpacing.md));
      children.add(
        Text(
          'PRINTED TEXT (OCR)${row.ocrMs == null ? '' : '  ·  ${row.ocrMs!.toStringAsFixed(0)} ms'}',
          style: theme.textTheme.labelSmall!.copyWith(
            color: colors.muted,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      children.add(const SizedBox(height: 4));
      if (row.ocrText == null) {
        children.add(
          Text(row.ocrNote ?? 'OCR did not run for this event.', style: muted),
        );
      } else if (row.ocrText!.trim().isEmpty) {
        children.add(Text('No text was read from the frame.', style: muted));
      } else {
        children.add(
          SelectableText(
            row.ocrText!.trim(),
            style: theme.textTheme.bodyMedium,
          ),
        );
      }
    }

    children.add(const SizedBox(height: AppSpacing.sm));
    children.add(
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const InspectionDataScreen(),
            ),
          ),
          icon: const Icon(Icons.table_rows_outlined, size: 18),
          label: const Text('All inspection rows'),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    String value,
    bool? printed,
  ) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    Widget mark;
    if (printed == null) {
      mark = Text('–', style: TextStyle(color: colors.muted));
    } else if (printed) {
      mark = Icon(Icons.check_circle, size: 16, color: colors.valid);
    } else {
      mark = Icon(Icons.cancel, size: 16, color: theme.colorScheme.error);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 12,
                color: colors.muted,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
          SizedBox(width: 24, child: Center(child: mark)),
        ],
      ),
    );
  }
}
