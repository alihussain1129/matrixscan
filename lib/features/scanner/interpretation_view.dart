import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../interpret/interpreter.dart';
import '../../interpret/scan_field.dart';

/// Shows an interpretation with searchable sections, field cards, copy actions,
/// and masked sensitive values. Place it inside a scrollable parent.
class InterpretationView extends StatefulWidget {
  const InterpretationView({super.key, required this.interpretation});

  final Interpretation interpretation;

  @override
  State<InterpretationView> createState() => _InterpretationViewState();
}

class _InterpretationViewState extends State<InterpretationView> {
  String _query = '';
  final Set<String> _revealed = {};

  String _key(ScanField f) => '${f.id}|${f.label}';

  bool _matches(ScanField f) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final parts = <String?>[
      f.label,
      f.id,
      f.note,
      f.warning,
      if (!f.sensitive) f.value,
      if (!f.sensitive) f.original,
    ];
    return parts.any((p) => p != null && p.toLowerCase().contains(q));
  }

  bool _sectionHas(ScanSection s) =>
      s.fields.any(_matches) || s.sections.any(_sectionHas);

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    _toast(message);
  }

  String? _rawValue() {
    for (final f in widget.interpretation.allFields) {
      if (f.id == 'raw') return f.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final i = widget.interpretation;
    final raw = _rawValue();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(i.formatName, style: text.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final w in i.warnings)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: scheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        w,
                        style: text.bodySmall?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search fields',
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (raw != null)
              TextButton.icon(
                onPressed: () => _copy(raw, 'Raw data copied'),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy raw data'),
              ),
            TextButton.icon(
              onPressed: () => _copy(
                const JsonEncoder.withIndent('  ').convert(i.toJson()),
                'Copied as JSON (sensitive values hidden)',
              ),
              icon: const Icon(Icons.data_object, size: 18),
              label: const Text('Copy as JSON'),
            ),
          ],
        ),
        for (final s in i.sections) _section(s),
      ],
    );
  }

  Widget _section(ScanSection s) {
    if (!_sectionHas(s)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final searching = _query.isNotEmpty;
    final collapsedByDefault = s.id == 'raw' || s.id == 'technical';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceRaised.withValues(alpha: 0.45),
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ExpansionTile(
        key: ValueKey('${s.id}-$searching'),
        initiallyExpanded: searching || !collapsedByDefault,
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        title: Text(s.title, style: theme.textTheme.titleSmall),
        children: [
          for (final f in s.fields)
            if (_matches(f)) _fieldTile(f),
          for (final n in s.sections) _section(n),
        ],
      ),
    );
  }

  String _presenceText(ScanField f) {
    switch (f.presence) {
      case FieldPresence.notPresent:
        return 'Not present in barcode';
      case FieldPresence.empty:
        return 'Empty';
      case FieldPresence.unsupported:
        return 'Not supported by EXALTED';
      case FieldPresence.unavailable:
        return 'Not retrieved';
      case FieldPresence.present:
        return f.value ?? '';
    }
  }

  String _originText(FieldOrigin o) => switch (o) {
    FieldOrigin.decoded => 'Decoded',
    FieldOrigin.parsed => 'Parsed',
    FieldOrigin.calculated => 'Calculated on this device',
    FieldOrigin.local => 'Local record',
    FieldOrigin.external => 'External source',
  };

  Widget _statusIcon(ScanField f, ColorScheme scheme) {
    if (f.validation == FieldValidation.invalid ||
        f.verification == FieldVerification.mismatch) {
      return Icon(Icons.error_outline, size: 18, color: scheme.error);
    }
    if (f.verification == FieldVerification.verified ||
        f.validation == FieldValidation.valid) {
      final colors = Theme.of(context).extension<ExaltedColors>()!;
      return Icon(Icons.check_circle_outline, size: 18, color: colors.valid);
    }
    if (f.presence != FieldPresence.present) {
      return Icon(
        Icons.info_outline,
        size: 18,
        color: scheme.onSurfaceVariant,
      );
    }
    return const SizedBox(width: 18, height: 18);
  }

  Widget _fieldTile(ScanField f) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final colors = theme.extension<ExaltedColors>()!;
    final revealed = _revealed.contains(_key(f));
    final hasValue = f.presence == FieldPresence.present && f.value != null;

    final shown = hasValue && f.sensitive && !revealed
        ? '\u2022' * 8
        : _presenceText(f);

    final status = <String>[
      if (hasValue) _originText(f.origin),
      if (f.standard != null) f.standard!,
      if (f.dataType != null) f.dataType!,
      if (f.unit != null) f.unit!,
      if (f.validation == FieldValidation.valid) 'Valid',
      if (f.validation == FieldValidation.invalid) 'Invalid',
      if (f.verification == FieldVerification.verified) 'Verified',
      if (f.verification == FieldVerification.mismatch) 'Mismatch',
    ];

    final invalid = f.validation == FieldValidation.invalid ||
        f.verification == FieldVerification.mismatch;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: invalid ? scheme.error.withValues(alpha: 0.65) : colors.outline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _statusIcon(f, scheme),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.label,
                  style: text.labelLarge?.copyWith(color: colors.muted),
                ),
                if (f.id != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('ID ${f.id}', style: text.labelSmall),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  shown,
                  style: text.bodyLarge?.copyWith(
                    fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                    fontFamily: hasValue ? 'monospace' : null,
                  ),
                ),
                if (hasValue &&
                    !f.sensitive &&
                    f.original != null &&
                    f.original != f.value)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: SelectableText(
                      'Encoded: ${f.original}',
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                  ),
                if (status.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final item in status)
                        _metadataChip(
                          item,
                          invalid: item == 'Invalid' || item == 'Mismatch',
                          valid: item == 'Valid' || item == 'Verified',
                        ),
                    ],
                  ),
                ],
                if (f.note != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(f.note!, style: text.bodySmall),
                ],
                if (f.warning != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    f.warning!,
                    style: text.bodySmall?.copyWith(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
          if (hasValue && f.sensitive)
            IconButton(
              tooltip: revealed ? 'Hide ${f.label}' : 'Reveal ${f.label}',
              visualDensity: VisualDensity.compact,
              icon: Icon(revealed ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() {
                revealed ? _revealed.remove(_key(f)) : _revealed.add(_key(f));
              }),
            ),
          if (hasValue)
            IconButton(
              tooltip: 'Copy ${f.label}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => _copy(f.value!, '${f.label} copied'),
            ),
        ],
      ),
    );
  }

  Widget _metadataChip(
    String label, {
    required bool invalid,
    required bool valid,
  }) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final scheme = theme.colorScheme;
    final foreground = invalid
        ? scheme.error
        : valid
        ? colors.valid
        : colors.muted;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}


