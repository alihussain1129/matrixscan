import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import 'keyence_commissioning_service.dart';
import 'keyence_ftp_receiver.dart';
import 'keyence_scanner_coordinator.dart';
import 'keyence_scanner_discovery_service.dart';
import 'keyence_sr751_client.dart';
import 'sr751_inspection_pipeline.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/config_controller.dart';
import '../../../core/config/platform_secret_store.dart';

/// Premium Industrial Control & Device Management Workspace for KEYENCE SR-750/751/752
/// 2D optical code readers, step-by-step Connection Wizard, and live machine vision inspection.
class KeyenceDeviceScreen extends ConsumerStatefulWidget {
  const KeyenceDeviceScreen({super.key});

  @override
  ConsumerState<KeyenceDeviceScreen> createState() =>
      _KeyenceDeviceScreenState();
}

class _KeyenceDeviceScreenState extends ConsumerState<KeyenceDeviceScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _ftpPortController = TextEditingController();
  final TextEditingController _ocvPatternController = TextEditingController(
    text: r'LOT-[A-Z0-9]+',
  );

  bool _isTesting = false;
  bool _advancedExpanded = false;
  int _wizardTabIndex = 0; // 0 = Auto-Discovery, 1 = Manual IP

  @override
  void initState() {
    super.initState();
    final sc = ref.read(configControllerProvider).scanner;
    _hostController.text = sc.host;
    _portController.text = sc.port.toString();
    _ftpPortController.text = sc.ftpReceiverPort.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startFtpServer();
      final coord = ref.read(keyenceScannerCoordinatorProvider);
      _hostController.text = coord.host;
      _portController.text = coord.port.toString();
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _ftpPortController.dispose();
    _ocvPatternController.dispose();
    super.dispose();
  }

  Future<void> _startFtpServer() async {
    final scannerConfig = ref.read(configControllerProvider).scanner;
    if (!scannerConfig.ftpReceiverEnabled) {
      debugPrint(
        '[KEYENCE][FTP] Startup skipped: receiver is disabled in settings.',
      );
      return;
    }
    final ftp = ref.read(keyenceFtpReceiverProvider);
    if (!ftp.isRunning) {
      String? password;
      try {
        password = await ref
            .read(secretStoreProvider)
            .read(ScannerConfig.ftpPasswordSecretKey);
      } catch (e) {
        debugPrint(
          '[KEYENCE][FTP] Could not read the FTP password from secure storage: ${e.runtimeType}',
        );
      }
      if (!mounted) return;
      ftp.configureCredentials(
        username: scannerConfig.ftpUsername,
        password: password,
      );
      final port =
          int.tryParse(_ftpPortController.text) ??
          scannerConfig.ftpReceiverPort;
      final started = await ftp.start(listenPort: port);
      if (!started) {
        debugPrint(
          '[KEYENCE][FTP] Receiver not started. Set a username and password in Settings.',
        );
      }
    }
  }

  Future<void> _toggleConnection() async {
    final coordinator = ref.read(keyenceScannerCoordinatorProvider.notifier);
    final state = ref.read(keyenceScannerCoordinatorProvider);

    if (state.isConnected) {
      await coordinator.disconnect();
    } else {
      final host = _hostController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 9004;

      final success = await coordinator.connect(
        targetHost: host,
        targetPort: port,
      );
      if (mounted && !success) {
        final err = ref.read(keyenceScannerCoordinatorProvider).lastError;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not connect to Keyence reader at $host:$port. '
              '${err ?? "Check network cables and IP configuration."}',
            ),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _runCommissioningDialog() async {
    setState(() => _isTesting = true);
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9004;
    final report = await ref
        .read(keyenceScannerCoordinatorProvider.notifier)
        .runCommissioning(targetHost: host, targetPort: port);

    if (!mounted) return;
    setState(() => _isTesting = false);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final passedSteps = report.steps.where((s) => s.passed).toList();
        final failedSteps = report.steps.where((s) => !s.passed).toList();

        return AlertDialog(
          title: Row(
            children: [
              Icon(
                report.overallReady ? Icons.check_circle : Icons.warning_amber,
                color: report.overallReady
                    ? AppColors.successGreen
                    : AppColors.warningAmber,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                report.overallReady
                    ? 'Commissioning Verified'
                    : 'Commissioning Attention Required',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evaluated Keyence SR reader at $host:$port across physical network, '
                    'command socket, trigger channels, and FTP image transfer.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (failedSteps.isNotEmpty) ...[
                    Text(
                      'ATTENTION NEEDED (${failedSteps.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(ctx).colorScheme.error,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    for (final step in failedSteps) ...[
                      _DiagnosticRow(step: step, passed: false),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Text(
                    'PASSED CHECKS (${passedSteps.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.successGreen,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final step in passedSteps) ...[
                    _DiagnosticRow(step: step, passed: true),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            if (!report.overallReady)
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Re-test'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _runCommissioningDialog();
                },
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    final text = theme.textTheme;

    final coordinator = ref.watch(keyenceScannerCoordinatorProvider);
    final coordNotifier = ref.read(keyenceScannerCoordinatorProvider.notifier);
    final pipeline = ref.watch(sr751InspectionPipelineProvider);
    final ftp = ref.watch(keyenceFtpReceiverProvider);

    final width = MediaQuery.sizeOf(context).width;
    final isDesktopWide = width >= 1100;

    return Scaffold(
      body: SafeArea(
        child: isDesktopWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Pane: Device Overview, Wizard & Controls (Flex 6)
                  Expanded(
                    flex: 6,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildDeviceOverviewCard(coordinator, colors, text),
                          const SizedBox(height: AppSpacing.xl),
                          _buildConnectionWizard(
                            coordinator,
                            coordNotifier,
                            colors,
                            text,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _buildHardwareControls(
                            coordinator,
                            coordNotifier,
                            colors,
                            text,
                          ),
                        ],
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, color: colors.outline),
                  // Right Pane: Inspection, CMOS Camera Feed & Diagnostics (Flex 5)
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildLiveReadCard(coordinator, colors, text),
                          const SizedBox(height: AppSpacing.xl),
                          _buildCmosInspectionView(pipeline, ftp, colors, text),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDeviceOverviewCard(coordinator, colors, text),
                    const SizedBox(height: AppSpacing.lg),
                    _buildConnectionWizard(
                      coordinator,
                      coordNotifier,
                      colors,
                      text,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _buildHardwareControls(
                      coordinator,
                      coordNotifier,
                      colors,
                      text,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _buildLiveReadCard(coordinator, colors, text),
                    const SizedBox(height: AppSpacing.lg),
                    _buildCmosInspectionView(pipeline, ftp, colors, text),
                  ],
                ),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. DEVICE OVERVIEW CARD
  // ---------------------------------------------------------------------------
  Widget _buildDeviceOverviewCard(
    KeyenceCoordinatorState state,
    ExaltedColors colors,
    TextTheme text,
  ) {
    final isConnected = state.isConnected;

    StatusBadgeVariant badgeVariant;
    String statusText;
    IconData statusIcon;

    switch (state.status) {
      case KeyenceConnectionStatus.connected:
        badgeVariant = StatusBadgeVariant.success;
        statusText = 'CONNECTED';
        statusIcon = Icons.check_circle_outline;
        break;
      case KeyenceConnectionStatus.connecting:
        badgeVariant = StatusBadgeVariant.processing;
        statusText = 'CONNECTING';
        statusIcon = Icons.sync;
        break;
      case KeyenceConnectionStatus.error:
        badgeVariant = StatusBadgeVariant.error;
        statusText = 'COMM ERROR';
        statusIcon = Icons.error_outline;
        break;
      case KeyenceConnectionStatus.disconnected:
        badgeVariant = StatusBadgeVariant.neutral;
        statusText = 'DISCONNECTED';
        statusIcon = Icons.power_off_outlined;
        break;
    }

    return Card(
      color: colors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: isConnected ? colors.valid.withAlpha(120) : colors.outline,
          width: isConnected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? colors.valid.withAlpha(25)
                        : colors.muted.withAlpha(25),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Icon(
                    Icons.router_outlined,
                    size: 26,
                    color: isConnected ? colors.valid : colors.muted,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'KEYENCE ${state.model}',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          StatusBadge(
                            label: statusText,
                            variant: badgeVariant,
                            icon: statusIcon,
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isConnected
                            ? 'Endpoint: ${state.host}:${state.port} · TCP Unicast'
                            : 'Factory Default: 192.168.100.100:9004',
                        style: text.bodySmall?.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  icon: Icon(
                    isConnected ? Icons.power_settings_new : Icons.bolt,
                    size: 16,
                  ),
                  label: Text(isConnected ? 'Disconnect' : 'Connect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: state.status == KeyenceConnectionStatus.connecting
                      ? null
                      : _toggleConnection,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            // Diagnostic Telemetry Row
            Row(
              children: [
                _buildTelemetryTile(
                  label: 'FIRMWARE',
                  value: state.firmware ?? 'N/A',
                  colors: colors,
                  text: text,
                ),
                _buildTelemetryTile(
                  label: 'SERIAL NUMBER',
                  value: state.serialNumber ?? 'N/A',
                  colors: colors,
                  text: text,
                ),
                _buildTelemetryTile(
                  label: 'CONNECTION SPEED',
                  value: state.totalConnectionTimeMs > 0
                      ? '${state.totalConnectionTimeMs} ms'
                      : '—',
                  subvalue: state.totalConnectionTimeMs > 0
                      ? 'Target: < 3-4s'
                      : null,
                  colors: colors,
                  text: text,
                  highlight:
                      state.totalConnectionTimeMs > 0 &&
                      state.totalConnectionTimeMs < 4000,
                ),
                _buildTelemetryTile(
                  label: 'TOTAL READS',
                  value: '${state.scanCount}',
                  colors: colors,
                  text: text,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryTile({
    required String label,
    required String value,
    String? subvalue,
    required ExaltedColors colors,
    required TextTheme text,
    bool highlight = false,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: colors.muted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: highlight ? colors.valid : null,
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subvalue != null) ...[
            const SizedBox(height: 1),
            Text(subvalue, style: TextStyle(fontSize: 10, color: colors.muted)),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. CONNECTION WIZARD (Auto-Discovery vs Manual Fallback)
  // ---------------------------------------------------------------------------
  Widget _buildConnectionWizard(
    KeyenceCoordinatorState state,
    KeyenceScannerCoordinator coordNotifier,
    ExaltedColors colors,
    TextTheme text,
  ) {
    return Card(
      color: colors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONNECTION WIZARD',
                        style: text.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.muted,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Locate and verify your Keyence SR-751 on Ethernet or Wi-Fi',
                        style: text.bodySmall?.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('Auto-Discovery'),
                      icon: Icon(Icons.wifi_tethering, size: 16),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('Manual IP'),
                      icon: Icon(Icons.edit_outlined, size: 16),
                    ),
                  ],
                  selected: {_wizardTabIndex},
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (set) =>
                      setState(() => _wizardTabIndex = set.first),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.md),

            // Tab 0: Auto-Discovery
            if (_wizardTabIndex == 0) ...[
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: state.isDiscovering
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search, size: 16),
                    label: Text(
                      state.isDiscovering
                          ? 'Scanning Interfaces...'
                          : 'Scan for Scanners',
                    ),
                    onPressed: state.isDiscovering
                        ? null
                        : () => coordNotifier.discoverScanners(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.health_and_safety_outlined,
                      size: 16,
                    ),
                    label: const Text('Readiness Check'),
                    onPressed: _isTesting ? null : _runCommissioningDialog,
                  ),
                  const Spacer(),
                  if (state.discoveredScanners.isNotEmpty)
                    Text(
                      'Found ${state.discoveredScanners.length} scanner(s)',
                      style: text.bodySmall?.copyWith(
                        color: colors.valid,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.discoveredScanners.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: colors.canvas.withAlpha(10),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(color: colors.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: colors.muted),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          state.isDiscovering
                              ? 'Probing ARP neighbors, local subnets, and standard ports...'
                              : 'No scanners discovered yet. Connect Ethernet cable and tap "Scan for Scanners".',
                          style: text.bodySmall?.copyWith(color: colors.muted),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    for (final disc in state.discoveredScanners)
                      _buildDiscoveredDeviceCard(
                        disc,
                        coordNotifier,
                        colors,
                        text,
                      ),
                  ],
                ),
            ]
            // Tab 1: Manual IP Fallback
            else ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Scanner IP Address',
                        hintText: '192.168.100.100',
                        prefixIcon: Icon(Icons.lan_outlined, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'TCP Port',
                        hintText: '9004',
                        prefixIcon: Icon(Icons.tag, size: 18),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Apply & Connect'),
                    onPressed: _toggleConnection,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  ActionChip(
                    label: const Text('Default (192.168.100.100)'),
                    onPressed: () {
                      const d = ScannerConfig();
                      _hostController.text = d.host;
                      _portController.text = d.port.toString();
                    },
                  ),
                  ActionChip(
                    label: const Text('Alternate (.101)'),
                    onPressed: () {
                      _hostController.text = '192.168.100.101';
                      _portController.text = '9004';
                    },
                  ),
                  ActionChip(
                    label: const Text('Localhost (127.0.0.1)'),
                    onPressed: () {
                      _hostController.text = '127.0.0.1';
                    },
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            // Advanced Expandable Panel
            InkWell(
              onTap: () =>
                  setState(() => _advancedExpanded = !_advancedExpanded),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _advancedExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: colors.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Advanced Protocol & Automation Settings',
                      style: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_advancedExpanded) ...[
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Auto-Reconnect on Drops',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Exponential backoff recovery if network cable momentarily drops',
                  style: TextStyle(fontSize: 11),
                ),
                value: state.autoReconnect,
                onChanged: (v) => coordNotifier.setAutoReconnect(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Auto-Connect on Startup',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Instantly connect to last successful scanner upon launching Exalted',
                  style: TextStyle(fontSize: 11),
                ),
                value: state.autoConnectOnStartup,
                onChanged: (v) => coordNotifier.setAutoConnectOnStartup(v),
              ),
              TextField(
                controller: _ftpPortController,
                decoration: const InputDecoration(
                  labelText: 'CMOS Image FTP Port',
                  hintText: '2121',
                  prefixIcon: Icon(Icons.camera_alt_outlined, size: 18),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveredDeviceCard(
    DiscoveredKeyenceScanner disc,
    KeyenceScannerCoordinator coordNotifier,
    ExaltedColors colors,
    TextTheme text,
  ) {
    final host = disc.identity.ipAddress ?? '192.168.100.100';
    final port = disc.identity.port ?? 9004;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.valid.withAlpha(25),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(Icons.qr_code_scanner, color: colors.valid, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  disc.identity.displayName ?? 'KEYENCE ${disc.identity.model}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$host:$port · FW: ${disc.identity.firmwareVersion ?? "V2.30"} · SN: ${disc.identity.serialNumber ?? "Unknown"} (${disc.responseTimeMs}ms)',
                  style: text.bodySmall?.copyWith(
                    fontSize: 11,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _hostController.text = host;
              _portController.text = port.toString();
              coordNotifier.connect(targetHost: host, targetPort: port);
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 8,
              ),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. HARDWARE CONTROL CONSOLE
  // ---------------------------------------------------------------------------
  Widget _buildHardwareControls(
    KeyenceCoordinatorState state,
    KeyenceScannerCoordinator coordNotifier,
    ExaltedColors colors,
    TextTheme text,
  ) {
    final isConnected = state.isConnected;

    return Card(
      color: colors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HARDWARE TRIGGER CONSOLE',
              style: text.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.muted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: const Text('Trigger Read (LON)'),
                  onPressed: isConnected
                      ? () => coordNotifier.triggerRead()
                      : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.flash_off, size: 16),
                  label: const Text('Stop Read (LOFF)'),
                  onPressed: isConnected
                      ? () => coordNotifier.stopRead()
                      : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Test Trigger (T1)'),
                  onPressed: isConnected
                      ? () => coordNotifier.triggerT1()
                      : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.volume_up, size: 16),
                  label: const Text('Buzzer (BEEP)'),
                  onPressed: isConnected ? () => coordNotifier.beep() : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.health_and_safety, size: 16),
                  label: const Text('Health (STAT)'),
                  onPressed: isConnected
                      ? () => coordNotifier.queryStatus()
                      : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: const Text('Request Frame (FTPOUT)'),
                  onPressed: isConnected
                      ? () => coordNotifier.requestFtpImage()
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. LIVE READ CARD
  // ---------------------------------------------------------------------------
  Widget _buildLiveReadCard(
    KeyenceCoordinatorState state,
    ExaltedColors colors,
    TextTheme text,
  ) {
    return Card(
      color: colors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'LATEST HARDWARE DECODE',
                  style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.muted,
                    letterSpacing: 0.8,
                  ),
                ),
                if (state.lastScan != null)
                  IconButton(
                    tooltip: 'Copy barcode',
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: state.lastScan!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied barcode to clipboard'),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.canvas,
                borderRadius: BorderRadius.circular(AppRadius.button),
                border: Border.all(color: colors.outline),
              ),
              child: state.lastScan == null
                  ? const Text(
                      'No barcode scanned yet.\nTrigger scanner to test decoding.',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    )
                  : SelectableText(
                      state.lastScan!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.aqua,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. CMOS INSPECTION & FTP IMAGE FEED
  // ---------------------------------------------------------------------------
  Widget _buildCmosInspectionView(
    Sr751InspectionPipeline pipeline,
    KeyenceFtpReceiver ftp,
    ExaltedColors colors,
    TextTheme text,
  ) {
    return Card(
      color: colors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CMOS MACHINE VISION INSPECTION',
                        style: text.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.muted,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Embedded FTP Server on Port ${ftp.boundPort} · Auto-OCV',
                        style: text.bodySmall?.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  label: ftp.isRunning ? 'FTP LISTENING' : 'FTP IDLE',
                  variant: ftp.isRunning
                      ? StatusBadgeVariant.success
                      : StatusBadgeVariant.neutral,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (pipeline.inspections.firstOrNull?.imagePath != null &&
                File(pipeline.inspections.firstOrNull!.imagePath!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.button),
                child: Image.file(
                  File(pipeline.inspections.firstOrNull!.imagePath!),
                  fit: BoxFit.contain,
                  height: 240,
                  width: double.infinity,
                ),
              )
            else
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.canvas,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  border: Border.all(color: colors.outline),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_outlined, size: 36, color: colors.muted),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Awaiting CMOS image from Keyence SR-751',
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _ocvPatternController,
              decoration: const InputDecoration(
                labelText: 'Expected OCV Pattern (Regex)',
                hintText: r'LOT-[A-Z0-9]+',
                prefixIcon: Icon(Icons.spellcheck, size: 18),
              ),
              onChanged: (v) => pipeline.expectedOcvPattern = v,
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.step, required this.passed});

  final CommissioningStep step;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: passed
            ? AppColors.successGreen.withAlpha(15)
            : Theme.of(context).colorScheme.error.withAlpha(15),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(
          color: passed
              ? AppColors.successGreen.withAlpha(60)
              : Theme.of(context).colorScheme.error.withAlpha(60),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                passed ? Icons.check_circle : Icons.cancel,
                size: 16,
                color: passed
                    ? AppColors.successGreen
                    : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                step.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(step.details, style: const TextStyle(fontSize: 11)),
          if (step.remediation != null) ...[
            const SizedBox(height: 2),
            Text(
              'Remediation: ${step.remediation!}',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
