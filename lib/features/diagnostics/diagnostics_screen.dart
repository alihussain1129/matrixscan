import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../../core/config/config_controller.dart';
import '../../core/crash/crash_log.dart';
import '../../core/navigation/desktop_chrome.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/devices/keyence/keyence_scanner_coordinator.dart';
import '../../features/devices/keyence/keyence_ftp_receiver.dart';
import '../../features/link/link_providers.dart';
import '../../features/scanner/scanner_controller.dart';
import '../../features/settings/ftp_settings_card.dart';
import '../../ffi/decoder_service.dart';
import '../../verify/verification_settings.dart';

class _NativeDiagnostic {
  const _NativeDiagnostic({required this.available, this.location, this.error});

  final bool available;
  final String? location;
  final String? error;
}

/// Runtime checks for platform services. The native decoder is loaded only
/// when the diagnostics page is opened, never during app startup.
final _nativeDiagnosticProvider = FutureProvider<_NativeDiagnostic>((
  ref,
) async {
  final decoder = DecoderService();
  try {
    final available = decoder.isAvailable;
    return _NativeDiagnostic(
      available: available,
      location: decoder.loadedFrom,
      error: decoder.loadError,
    );
  } finally {
    decoder.dispose();
  }
});

final _crashLogProvider = FutureProvider<String>((ref) async {
  final directory = await getApplicationSupportDirectory();
  return CrashLog(() async => directory).read();
});

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scanner = ref.watch(scannerControllerProvider);
    final keyence = ref.watch(keyenceScannerCoordinatorProvider);
    final link = ref.watch(linkControllerProvider);
    final native = ref.watch(_nativeDiagnosticProvider);
    final ocr = ref.watch(ocrAvailabilityProvider);
    final network = ref.watch(localIpv4AddressesProvider);
    final ftp = ref.watch(keyenceFtpReceiverProvider);
    final ftpConfig = ref.watch(configControllerProvider).scanner;
    final logs = ref.watch(_crashLogProvider);
    final platform = Platform.operatingSystem;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Diagnostics',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh diagnostics',
                  onPressed: () {
                    ref.invalidate(_nativeDiagnosticProvider);
                    ref.invalidate(ocrAvailabilityProvider);
                    ref.invalidate(localIpv4AddressesProvider);
                    ref.invalidate(_crashLogProvider);
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Live status for this device and its connected services.'),
            const SizedBox(height: AppSpacing.lg),
            _DiagnosticRow(label: 'Platform', value: platform),
            const Divider(),
            _DiagnosticRow(
              label: 'Native decoder',
              value: native.when(
                data: (d) => d.available
                    ? 'Ready${d.location == null ? '' : ' · ${d.location}'}'
                    : 'Unavailable${d.error == null ? '' : ' · ${d.error}'}',
                loading: () => 'Checking…',
                error: (_, _) => 'Status check failed',
              ),
            ),
            const Divider(),
            _DiagnosticRow(
              label: 'Camera',
              value: cameraStateLabel(scanner),
              detail: scanner.errorMessage,
            ),
            const Divider(),
            _DiagnosticRow(
              label: 'OCR',
              value: ocr.when(
                data: (state) => Platform.isAndroid
                    ? 'Google ML Kit · checked on first recognition'
                    : state.label,
                loading: () => 'Checking…',
                error: (_, _) => 'Status check failed',
              ),
            ),
            const Divider(),
            _DiagnosticRow(
              label: 'KEYENCE SR-751',
              value: keyence.isConnected
                  ? 'Connected · ${keyence.host}:${keyence.port}'
                  : keyence.isDiscovering
                  ? 'Discovering'
                  : 'Disconnected',
            ),
            const Divider(),
            _DiagnosticRow(
              label: 'Network',
              value: network.when(
                data: (addresses) => '${addresses.length} IPv4 interface(s)',
                loading: () => 'Checking…',
                error: (_, _) => 'Interface check failed',
              ),
              detail: network.asData?.value.join(' · '),
            ),
            const Divider(),
            _DiagnosticRow(
              label: 'KEYENCE FTP receiver',
              value: ftp.isRunning
                  ? 'Listening · port ${ftp.boundPort}'
                  : ftpConfig.ftpReceiverEnabled
                  ? 'Stopped · configured port ${ftp.port}'
                  : 'Disabled · configured port ${ftp.port}',
            ),
            const Divider(),
            _DiagnosticRow(
              label: 'Synchronization',
              value: !link.ready
                  ? (link.error == null
                        ? 'Starting'
                        : 'Unavailable · ${link.error}')
                  : '${link.devices.length + link.peers.length} linked device(s) · ${link.syncing ? 'Syncing' : 'Idle'}',
            ),
            const Divider(),
            _DiagnosticRow(
              label: 'External verification',
              value:
                  '${ref.watch(allowedSourcesProvider).length} online source(s) enabled',
              detail: 'Online checks run only after a scan and never block decoding.',
            ),
            const Divider(),
            _DiagnosticRow(
              label: 'Crash log',
              value: logs.when(
                data: (value) => value.isEmpty
                    ? 'No entries'
                    : '${value.length} characters · ${'\n'.allMatches(value).length} lines',
                loading: () => 'Checking…',
                error: (_, _) => 'Unreadable',
              ),
            ),
            if (logs.asData?.value.isNotEmpty ?? false)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: logs.asData!.value),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Crash log copied.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy crash log'),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(navIndexProvider.notifier).set(kSettingsTab),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: detail == null ? null : Text(detail!),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Text(value, textAlign: TextAlign.end),
      ),
    );
  }
}
