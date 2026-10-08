import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../ffi/decode_result.dart';

/// Bottom card shown on the scanner screen when a barcode has been decoded.
class ScanResultCard extends StatelessWidget {
  const ScanResultCard({
    super.key,
    required this.barcode,
    required this.onCopy,
    required this.onScanAgain,
    this.onOpenLink,
  });

  final DecodedBarcode barcode;
  final VoidCallback onCopy;
  final VoidCallback onScanAgain;

  /// Non-null when the decoded text is a web link.
  final VoidCallback? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

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
                Icon(Icons.qr_code_2, color: scheme.primary),
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: SelectableText(barcode.text, style: text.bodyLarge),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
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
                  child: onOpenLink == null
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
