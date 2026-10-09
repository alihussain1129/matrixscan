import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../ffi/decode_result.dart';
import '../../gs1/gs1_parser.dart';
import '../../interpret/default_registry.dart';
import '../../interpret/interpreter.dart';
import 'gs1_info_panel.dart';
import 'interpretation_view.dart';
import 'wifi_info_panel.dart';
import 'wifi_utils.dart';

final _registry = defaultInterpreterRegistry();

/// Bottom card shown on the scanner screen when a barcode has been decoded.
class ScanResultCard extends StatelessWidget {
  const ScanResultCard({
    super.key,
    required this.barcode,
    required this.onCopy,
    required this.onScanAgain,
    this.onOpenLink,
    this.onConnectWifi,
  });

  final DecodedBarcode barcode;
  final VoidCallback onCopy;
  final VoidCallback onScanAgain;

  /// Non-null when the decoded text is a web link.
  final VoidCallback? onOpenLink;

  /// Non-null to offer joining a Wi-Fi code. Shown only when it can be joined.
  final VoidCallback? onConnectWifi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final wifi = parseWifiQr(barcode.text);
    final gs1 = wifi == null ? parseGs1(barcode.text) : null;
    final interp = wifi == null
        ? _registry.interpret(ScanPayload(raw: barcode.text, symbology: barcode.kind.label, source: 'live'))
        : null;
    final emv = (interp != null && (interp.interpreterId == 'emv' || interp.interpreterId == 'gs1')) ? interp : null;
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
                      : emv != null ? Icons.payments_outlined : Icons.qr_code_2,
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
                  child: InterpretationView(interpretation: emv),
                ),
              )
            else if (gs1 != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(child: Gs1InfoPanel(result: gs1)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: SelectableText(barcode.text, style: text.bodyLarge),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
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