import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../ffi/decode_result.dart';
import '../../gs1/gs1_parser.dart';
import '../../interpret/default_registry.dart';
import '../../interpret/interpreter.dart';
import '../../interpret/scan_field.dart';
import 'gs1_info_panel.dart';
import '../../verify/verification_engine.dart';
import '../result/result_screen.dart';
import 'wifi_info_panel.dart';
import 'wifi_utils.dart';

final _registry = defaultInterpreterRegistry();

/// Interpretations shown in full on the card. Everything else shows raw text.
const Set<String> _richInterpreters = {'emv', 'contact'};

/// Bottom card shown on the scanner screen when a barcode has been decoded.
class ScanResultCard extends StatelessWidget {
  const ScanResultCard({
    super.key,
    required this.barcode,
    required this.onCopy,
    required this.onScanAgain,
    this.onOpenLink,
    this.onConnectWifi,
    this.verifier,
    this.allowedSources = const {},
  });

  final DecodedBarcode barcode;
  final VoidCallback onCopy;
  final VoidCallback onScanAgain;

  /// Non-null when the decoded text is a web link.
  final VoidCallback? onOpenLink;

  /// Non-null to offer joining a Wi-Fi code. Shown only when it can be joined.
  final VoidCallback? onConnectWifi;

  /// Runs verification checks when non-null.
  final VerificationEngine? verifier;

  /// IDs of online sources the user has allowed.
  final Set<String> allowedSources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final wifi = parseWifiQr(barcode.text);
    final gs1 = wifi == null ? parseGs1(barcode.text) : null;
    final interp = wifi == null
        ? _registry.interpret(
            ScanPayload(
              raw: barcode.text,
              symbology: barcode.kind.label,
              source: 'live',
            ),
          )
        : null;
    final emv =
        (interp != null && _richInterpreters.contains(interp.interpreterId))
        ? interp
        : null;
    final linkWarnings = (interp != null && interp.interpreterId == 'url')
        ? interp.warnings
        : const <String>[];
    final showConnect =
        wifi != null && wifi.canConnect && onConnectWifi != null;

    return Material(
      color: scheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  wifi != null
                      ? Icons.wifi
                      : gs1 != null
                      ? Icons.inventory_2_outlined
                      : emv != null
                      ? (emv.interpreterId == 'emv'
                            ? Icons.payments_outlined
                            : emv.interpreterId == 'gs1'
                            ? Icons.inventory_2_outlined
                            : Icons.contact_page_outlined)
                      : Icons.qr_code_2,
                  color: scheme.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(barcode.kind.label, style: text.titleMedium),
                ),
                Text(
                  '${(barcode.decodeMicros / 1000).toStringAsFixed(1)} ms',
                  style: text.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (wifi != null)
              WifiInfoPanel(wifi: wifi)
            else if (emv != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: _CompactSummary(interpretation: emv),
                ),
              )
            else if (gs1 != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Gs1InfoPanel(result: gs1, showRaw: false),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(barcode.text, style: text.bodyLarge),
                      for (final w in linkWarnings) _LinkWarning(w),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ResultScreen(
                      raw: barcode.text,
                      symbology: barcode.kind.label,
                      decodeMicros: barcode.decodeMicros,
                      verifier: verifier,
                      allowedSources: allowedSources,
                    ),
                  ),
                ),
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('Full details'),
              ),
            ),
            if (showConnect) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onConnectWifi,
                  icon: const Icon(Icons.wifi),
                  label: const Text('Connect to Wi-Fi'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (onOpenLink != null) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onOpenLink,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open link'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: (onOpenLink == null && !showConnect)
                      ? FilledButton.icon(
                          onPressed: onScanAgain,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Scan again'),
                        )
                      : OutlinedButton.icon(
                          onPressed: onScanAgain,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Scan again'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One warning line about a link, in the error colour.
class _LinkWarning extends StatelessWidget {
  const _LinkWarning(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// A short summary for the scanner card. All fields, checks and sources are
/// on the Decoded details screen.
class _CompactSummary extends StatelessWidget {
  const _CompactSummary({required this.interpretation});

  final Interpretation interpretation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final error = theme.colorScheme.error;

    final shown = <ScanField>[];
    for (final s in interpretation.sections) {
      if (s.id == 'raw' || s.id == 'technical') continue;
      for (final f in s.allFields) {
        if (shown.length >= 4) break;
        final v = f.value;
        if (f.presence == FieldPresence.present &&
            v != null &&
            v.isNotEmpty &&
            !f.sensitive) {
          shown.add(f);
        }
      }
    }
    final warnings = interpretation.warnings.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(interpretation.formatName, style: text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        for (final f in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    f.label,
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    f.value!,
                    style: text.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(w, style: text.bodySmall?.copyWith(color: error)),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Tap Full details for all fields and checks.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}
