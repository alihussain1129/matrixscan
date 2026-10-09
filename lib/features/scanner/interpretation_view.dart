import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_spacing.dart';
import '../../interpret/interpreter.dart';
import '../../interpret/scan_field.dart';

/// Shows everything an [Interpretation] contains: warnings, search, collapsible
/// sections, per-field copy, and masked sensitive values. Place it inside a
/// scrollable parent.
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
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
        const SizedBox(height: AppSpacing.sm),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search fields',
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        Row(
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
    final searching = _query.isNotEmpty;
    final collapsedByDefault = s.id == 'raw' || s.id == 'technical';
    return ExpansionTile(
      key: ValueKey('${s.id}-$searching'),
      initiallyExpanded: searching || !collapsedByDefault,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: AppSpacing.sm),
      title: Text(s.title, style: Theme.of(context).textTheme.titleSmall),
      children: [
        for (final f in s.fields)
          if (_matches(f)) _fieldTile(f),
        for (final n in s.sections) _section(n),
      ],
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

  Widget _fieldTile(ScanField f) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
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

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.label, style: text.bodySmall),
                if (f.id != null) Text('ID ${f.id}', style: text.labelSmall),
                Text(shown, style: text.bodyMedium),
                if (hasValue &&
                    !f.sensitive &&
                    f.original != null &&
                    f.original != f.value)
                  Text('Encoded: ${f.original}', style: text.bodySmall),
                if (status.isNotEmpty)
                  Text(status.join(' \u00b7 '), style: text.bodySmall),
                if (f.note != null) Text(f.note!, style: text.bodySmall),
                if (f.warning != null)
                  Text(
                    f.warning!,
                    style: text.bodySmall?.copyWith(color: scheme.error),
                  ),
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
}