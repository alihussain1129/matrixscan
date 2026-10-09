import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/decode_result.dart';
import '../../verify/verification_settings.dart';
import 'scan_result_card.dart';

/// [ScanResultCard] wired to the verification engine and the user's choice
/// of allowed online sources.
class ConnectedScanResultCard extends ConsumerWidget {
  const ConnectedScanResultCard({
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
  final VoidCallback? onOpenLink;
  final VoidCallback? onConnectWifi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScanResultCard(
      barcode: barcode,
      onCopy: onCopy,
      onScanAgain: onScanAgain,
      onOpenLink: onOpenLink,
      onConnectWifi: onConnectWifi,
      verifier: ref.read(verificationEngineProvider),
      allowedSources: ref.watch(allowedSourcesProvider),
    );
  }
}