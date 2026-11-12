import 'ftp_settings_card.dart';
import 'auto_restart_card.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_recovery_service.dart';
import '../../core/config/app_config.dart';
import '../../core/config/config_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/exalted_card.dart';
import '../../design/exalted_page.dart';
import '../../design/exalted_segmented.dart';
import '../../design/exalted_settings_kit.dart';
import '../../design/exalted_tab_pills.dart';
import '../devices/keyence/keyence_sr751_client.dart';
import '../scanner/live_ocr_analyzer.dart';
import '../scanner/scan_feedback.dart';
import '../scanner/scanner_controller.dart';
import '../link/companion_notifications.dart';
import '../../ffi/decode_result.dart';
import '../../core/router/app_router.dart';
import 'about_screen.dart';
import 'settings_controller.dart';

/// Comprehensive system settings and industrial hardware configuration screen.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Map<String, dynamic>? _storageHealth;
  bool _isCheckingHealth = false;
  int _cat = 0;

  Future<void> _checkStorageHealth() async {
    setState(() => _isCheckingHealth = true);
    final backupService = ref.read(backupRecoveryServiceProvider);
    final health = await backupService.checkStorageIntegrity();
    if (mounted) {
      setState(() {
        _storageHealth = health;
        _isCheckingHealth = false;
      });
    }
  }

  Future<void> _createBackup() async {
    try {
      final backupService = ref.read(backupRecoveryServiceProvider);
      final file = await backupService.createBackupFile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup archive created: ${file.path}'),
          action: SnackBarAction(
            label: 'Copy Path',
            onPressed: () => Clipboard.setData(ClipboardData(text: file.path)),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _setSymbology(String name, bool enabled) async {
    const all = DecoderConfig.knownSymbologies;
    final current = ref.read(configControllerProvider).decoder.symbologies;
    final selected = current.isEmpty ? all.toSet() : current.toSet();
    if (enabled) {
      selected.add(name);
    } else {
      selected.remove(name);
    }
    final next = selected.length == all.length ? <String>[] : selected.toList();
    final result = await ref.read(configControllerProvider.notifier).patch({
      'decoder': {'symbologies': next},
    });
    if (result.saveError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Decoder settings were not saved: ${result.saveError}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    final mode = ref.watch(themeModeProvider);
    final decoder = ref.watch(configControllerProvider).decoder;
    final ui = ref.watch(scannerControllerProvider);
    final scanner = ref.read(scannerControllerProvider.notifier);
    final keyence = ref.watch(keyenceSr751ClientProvider);

    final platformDesc = Platform.isLinux
        ? 'Linux Desktop (Pop!_OS / Ubuntu x86_64)'
        : (Platform.isWindows
              ? 'Windows Desktop (x64)'
              : (Platform.isAndroid
                    ? 'Android Mobile'
                    : Platform.operatingSystem));

    return SafeArea(
      child: ExaltedPageFrame(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          children: [
            Row(
              children: [
                Expanded(child: Text('Settings', style: text.displaySmall)),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            ExaltedTabPills(
              items: const [
                ExaltedTabItem('General', Icons.tune),
                ExaltedTabItem('Appearance', Icons.palette_outlined),
                ExaltedTabItem('Scanning', Icons.qr_code_scanner),
                ExaltedTabItem('Decoder', Icons.qr_code_2),
                ExaltedTabItem('OCR', Icons.text_fields),
                ExaltedTabItem('Verification', Icons.fact_check_outlined),
                ExaltedTabItem('Devices & Sync', Icons.sync_alt),
                ExaltedTabItem('Network & FTP', Icons.lan_outlined),
                ExaltedTabItem(
                  'Notifications & Feedback',
                  Icons.notifications_outlined,
                ),
                ExaltedTabItem('Advanced', Icons.build_outlined),
                ExaltedTabItem('About', Icons.info_outline),
              ],
              selected: _cat,
              onChanged: (i) => setState(() => _cat = i),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_cat == 2) ...[
              // ---- SCANNING ---------------------------------------------------
              ExaltedSectionHeader(title: 'Scanning & decoder engine'),
              const SizedBox(height: AppSpacing.md),
              ExaltedCard(
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: Icons.bolt,
                      title: 'Auto scan',
                      subtitle:
                          'Detect and decode as soon as a code is in view',
                      value: ui.autoScan,
                      onChanged: (_) => scanner.toggleAuto(),
                    ),
                    Divider(color: colors.outline, height: AppSpacing.xl),
                    _SwitchRow(
                      icon: Icons.repeat,
                      title: 'Continuous scanning',
                      subtitle: 'Keep scanning several codes without stopping',
                      value: ui.continuous,
                      onChanged: (_) => scanner.toggleContinuous(),
                    ),
                    Divider(color: colors.outline, height: AppSpacing.xl),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Camera quality', style: text.bodyLarge),
                          const SizedBox(height: 2),
                          Text(
                            'Balanced is smoother on older devices. '
                            'High reads small Data Matrix and dot-peen codes better.',
                            style: text.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: ExaltedSegmented<CameraQuality>(
                              options: [
                                for (final q in CameraQuality.values)
                                  ExaltedSegment<CameraQuality>(
                                    value: q,
                                    label: q.label,
                                  ),
                              ],
                              value: ui.quality,
                              onChanged: (q) => scanner.setQuality(q),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_cat == 6) ...[
              // ---- INDUSTRIAL HARDWARE & VISION -------------------------------
              ExaltedSectionHeader(title: 'Industrial hardware & networking'),
              const SizedBox(height: AppSpacing.md),
              ExaltedCard(
                child: Column(
                  children: [
                    _InfoRow(
                      label: 'Keyence SR-751 Target',
                      value: '${keyence.host}:${keyence.port}',
                    ),
                    Divider(color: colors.outline, height: AppSpacing.xl),
                    _InfoRow(
                      label: 'Keyence Connection',
                      value: keyence.status == KeyenceConnectionStatus.connected
                          ? 'ONLINE / READY'
                          : 'STANDBY',
                    ),
                    Divider(color: colors.outline, height: AppSpacing.xl),
                    _SwitchRow(
                      icon: Icons.autorenew,
                      title: 'Auto Reconnect',
                      subtitle:
                          'Automatically recover connection on socket drops',
                      value: keyence.autoReconnect,
                      onChanged: (v) {
                        setState(() {
                          keyence.autoReconnect = v;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(navIndexProvider.notifier).set(kDevicesTab),
                icon: const Icon(Icons.router_outlined),
                label: const Text('Open device management'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(navIndexProvider.notifier).set(kLinkTab),
                icon: const Icon(Icons.sync_alt),
                label: const Text('Open linked devices and sync'),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (_cat == 9) ...[
              // ---- ADVANCED DATA & RECOVERY ----------------------------------
              ExaltedSectionHeader(
                title: 'Data storage, backup & traceability',
              ),
              const SizedBox(height: AppSpacing.md),
              ExaltedCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Offline Image & Traceability Repository',
                      style: text.bodyLarge!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Original scanned frames and OCR document images are preserved '
                      'permanently on local disk under exalted_media/.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.verified_outlined, size: 16),
                            label: const Text('Check Integrity'),
                            onPressed: _isCheckingHealth
                                ? null
                                : _checkStorageHealth,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.archive_outlined, size: 16),
                            label: const Text('Export Backup'),
                            onPressed: _createBackup,
                          ),
                        ),
                      ],
                    ),
                    if (_storageHealth != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: (_storageHealth!['isHealthy'] as bool)
                              ? const Color(0xFF22C55E).withAlpha(20)
                              : Colors.orange.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (_storageHealth!['isHealthy'] as bool)
                                ? const Color(0xFF22C55E)
                                : Colors.orange,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Storage Health: ${(_storageHealth!['isHealthy'] as bool) ? '100% HEALTHY' : 'WARNINGS FOUND'}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: (_storageHealth!['isHealthy'] as bool)
                                    ? const Color(0xFF22C55E)
                                    : Colors.orange,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tracked Media: ${_storageHealth!['validImages']} / ${_storageHealth!['totalImagesTracked']} valid '
                              '(${((_storageHealth!['totalStorageBytes'] as int) / (1024 * 1024)).toStringAsFixed(2)} MB on disk)',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),
            ],
            if (_cat == 1) ...[
              // ---- APPEARANCE -------------------------------------------------
              ExaltedSectionHeader(title: 'Appearance'),
              const SizedBox(height: AppSpacing.md),
              ExaltedCard(
                child: SizedBox(
                  width: double.infinity,
                  child: ExaltedSegmented<ThemeMode>(
                    options: const [
                      ExaltedSegment<ThemeMode>(
                        value: ThemeMode.system,
                        label: 'System',
                        icon: Icons.brightness_auto_outlined,
                      ),
                      ExaltedSegment<ThemeMode>(
                        value: ThemeMode.light,
                        label: 'Light',
                        icon: Icons.light_mode_outlined,
                      ),
                      ExaltedSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        label: 'Dark',
                        icon: Icons.dark_mode_outlined,
                      ),
                    ],
                    value: mode,
                    onChanged: (m) =>
                        ref.read(themeModeProvider.notifier).set(m),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),
            ],
            if (_cat == 3) ...[
              ExaltedSectionHeader(title: 'Enabled symbologies'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Limit live decoding to selected formats. Selecting every format restores the default all-formats mode.',
                style: text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              ExaltedCard(
                child: Column(
                  children: [
                    for (final kind in BarcodeKind.values)
                      if (kind != BarcodeKind.unknown)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(kind.label),
                          value:
                              decoder.symbologies.isEmpty ||
                              decoder.symbologies.contains(kind.name),
                          onChanged: (enabled) {
                            if (enabled != null) {
                              unawaited(_setSymbology(kind.name, enabled));
                            }
                          },
                        ),
                  ],
                ),
              ),
            ],
            if (_cat == 7) ...[
              // ---- KEYENCE FTP RECEIVER ---------------------------------------
              ExaltedSectionHeader(title: 'Keyence FTP receiver'),
              const SizedBox(height: AppSpacing.md),
              const ExaltedCard(child: FtpSettingsCard()),

              const SizedBox(height: AppSpacing.xl),
            ],
            if (_cat == 9) ...[
              // ---- AUTO-RESTART AFTER CRASH -----------------------------------
              ExaltedSectionHeader(title: 'Auto-restart after crash'),
              const SizedBox(height: AppSpacing.md),
              const ExaltedCard(child: AutoRestartCard()),

              const SizedBox(height: AppSpacing.xl),
            ],
            if (_cat == 0) ...[
              // ---- SYSTEM ARCHITECTURE & DIAGNOSTICS --------------------------
              ExaltedSectionHeader(title: 'System architecture & diagnostics'),
              const SizedBox(height: AppSpacing.md),
              ExaltedCard(
                child: Column(
                  children: [
                    const _InfoRow(
                      label: 'Platform Architecture',
                      value: 'Unified Core (Dart + C++20)',
                    ),
                    Divider(color: colors.outline, height: AppSpacing.xl),
                    _InfoRow(label: 'Operating System', value: platformDesc),
                    Divider(color: colors.outline, height: AppSpacing.xl),
                    const _InfoRow(
                      label: 'Native Decoder',
                      value: 'C++20 (ZXing + DotPeen ECC200)',
                    ),
                    Divider(color: colors.outline, height: AppSpacing.xl),
                    const _InfoRow(
                      label: 'Offline Privacy',
                      value: 'Online sources are opt-in under Verification',
                    ),
                  ],
                ),
              ),
            ],
            if (_cat == 4) ...[
              ExaltedSectionHeader(title: 'OCR engine'),
              const SizedBox(height: AppSpacing.md),
              ExaltedCard(
                child: Column(
                  children: [
                    _InfoRow(
                      label: 'Engine',
                      value: Platform.isAndroid
                          ? 'Google ML Kit · on-device'
                          : 'Tesseract · local',
                    ),
                    const Divider(height: AppSpacing.xl),
                    ValueListenableBuilder<bool>(
                      valueListenable: ref
                          .read(liveOcrAnalyzerProvider)
                          .enabledListenable,
                      builder: (context, on, _) => _SwitchRow(
                        icon: Icons.text_fields,
                        title: 'Live text reading',
                        subtitle: 'Read printed text in the camera view. Turning it off reduces processing load.',
                        value: on,
                        onChanged: (value) =>
                            ref.read(liveOcrAnalyzerProvider).setEnabled(value),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_cat == 5) ...[
              ExaltedSectionHeader(title: 'Verification'),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Configure on-device checks and optional external sources on the Verification screen.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(navIndexProvider.notifier).set(kVerificationTab),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Open verification settings'),
              ),
            ],
            if (_cat == 8) ...[
              ExaltedSectionHeader(title: 'Companion notifications'),
              const SizedBox(height: AppSpacing.md),
              if (Platform.isAndroid)
                ExaltedCard(child: const CompanionNotificationSettings())
              else
                Text(
                  'Companion notifications are delivered on paired Android devices.',
                  style: text.bodyMedium,
                ),
              const SizedBox(height: AppSpacing.xl),
              ExaltedSectionHeader(title: 'Scan feedback'),
              const SizedBox(height: AppSpacing.md),
              ExaltedCard(
                child: ValueListenableBuilder<bool>(
                  valueListenable: ScanFeedback.enabledListenable,
                  builder: (context, on, _) => _SwitchRow(
                    icon: Icons.volume_up_outlined,
                    title: 'Scan sounds',
                    subtitle: 'Plays a native beep on Android. Desktop support is not available yet.',
                    value: on,
                    onChanged: ScanFeedback.setEnabled,
                  ),
                ),
              ),
            ],
            if (_cat == 10) ...[
              ExaltedSectionHeader(title: 'About exalted'),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                ),
                icon: const Icon(Icons.info_outline),
                label: const Text('View product information'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon = Icons.tune,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData icon;

  void _set(bool v) {
    HapticFeedback.selectionClick();
    onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _set(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              ExaltedIconChip(icon: icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Switch(
                value: value,
                onChanged: _set,
                thumbIcon: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? const Icon(Icons.check)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = AppTypography.mono(
      size: 13,
      color: theme.colorScheme.onSurface,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: theme.textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(value, style: valueStyle),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(label, style: theme.textTheme.bodyLarge),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: Text(
                value,
                textAlign: TextAlign.end,
                softWrap: true,
                style: valueStyle,
              ),
            ),
          ],
        );
      },
    );
  }
}
