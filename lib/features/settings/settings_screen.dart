import 'ftp_settings_card.dart';
import 'auto_restart_card.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_recovery_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/exalted_card.dart';
import '../devices/keyence/keyence_sr751_client.dart';
import '../scanner/scanner_controller.dart';
import '../../verify/verification_settings.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    final mode = ref.watch(themeModeProvider);
    final allowed = ref.watch(allowedSourcesProvider);
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
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Row(
            children: [
              Expanded(child: Text('Settings', style: text.displaySmall)),
              IconButton(
                tooltip: 'About EXALTED',
                icon: const Icon(Icons.info_outline_rounded),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- SCANNING & DECODER ENGINE ----------------------------------
          Text('SCANNING & DECODER ENGINE', style: text.labelSmall),
          const SizedBox(height: AppSpacing.md),
          ExaltedCard(
            child: Column(
              children: [
                _SwitchRow(
                  title: 'Auto scan',
                  subtitle: 'Detect and decode as soon as a code is in view',
                  value: ui.autoScan,
                  onChanged: (_) => scanner.toggleAuto(),
                ),
                Divider(color: colors.outline, height: AppSpacing.xl),
                _SwitchRow(
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
                        child: SegmentedButton<CameraQuality>(
                          showSelectedIcon: false,
                          segments: [
                            for (final q in CameraQuality.values)
                              ButtonSegment(value: q, label: Text(q.label)),
                          ],
                          selected: {ui.quality},
                          onSelectionChanged: (s) =>
                              scanner.setQuality(s.first),
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: scheme.primary,
                            selectedForegroundColor: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---- INDUSTRIAL HARDWARE & VISION -------------------------------
          Text('INDUSTRIAL HARDWARE & NETWORKING', style: text.labelSmall),
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
                  title: 'Auto Reconnect',
                  subtitle: 'Automatically recover connection on socket drops',
                  value: keyence.autoReconnect,
                  onChanged: (v) {
                    setState(() {
                      keyence.autoReconnect = v;
                    });
                  },
                ),
                Divider(color: colors.outline, height: AppSpacing.xl),
                _InfoRow(
                  label: 'OCR Engine Core',
                  value: Platform.isAndroid
                      ? 'Google ML Kit'
                      : 'Tesseract 5.3 TSV',
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---- DATA STORAGE, BACKUP & INTEGRITY ---------------------------
          Text('DATA STORAGE, BACKUP & TRACEABILITY', style: text.labelSmall),
          const SizedBox(height: AppSpacing.md),
          ExaltedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Offline Image & Traceability Repository',
                  style: text.bodyLarge!.copyWith(fontWeight: FontWeight.bold),
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

          // ---- APPEARANCE -------------------------------------------------
          Text('APPEARANCE', style: text.labelSmall),
          const SizedBox(height: AppSpacing.md),
          ExaltedCard(
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).set(s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: scheme.primary,
                  selectedForegroundColor: scheme.onPrimary,
                ),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ---- KEYENCE FTP RECEIVER ---------------------------------------
          Text('KEYENCE FTP RECEIVER', style: text.labelSmall),
          const SizedBox(height: AppSpacing.md),
          const ExaltedCard(child: FtpSettingsCard()),

          const SizedBox(height: AppSpacing.xl),

          // ---- AUTO-RESTART AFTER CRASH -----------------------------------
          Text('AUTO-RESTART AFTER CRASH', style: text.labelSmall),
          const SizedBox(height: AppSpacing.md),
          const ExaltedCard(child: AutoRestartCard()),

          const SizedBox(height: AppSpacing.xl),

          // ---- ONLINE LOOKUPS ---------------------------------------------
          Text('OPTIONAL ONLINE LOOKUPS', style: text.labelSmall),
          const SizedBox(height: AppSpacing.md),
          for (final s in onlineSourceChoices) ...[
            ExaltedCard(
              child: _SwitchRow(
                title: 'Allow ${s.name} lookup',
                subtitle: s.subtitle,
                value: allowed.contains(s.id),
                onChanged: (v) => ref
                    .read(allowedSourcesProvider.notifier)
                    .setAllowed(s.id, v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          const SizedBox(height: AppSpacing.xl),

          // ---- SYSTEM ARCHITECTURE & DIAGNOSTICS --------------------------
          Text('SYSTEM ARCHITECTURE & DIAGNOSTICS', style: text.labelSmall),
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
                _InfoRow(
                  label: 'Offline Privacy',
                  value: allowed.isEmpty
                      ? 'Strict Offline (Zero Leaks)'
                      : 'Lookups Enabled',
                ),
              ],
            ),
          ),
        ],
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
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.bodyLarge),
              const SizedBox(height: 2),
              Text(subtitle, style: text.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Switch(value: value, onChanged: onChanged),
      ],
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

    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        Text(
          value,
          style: AppTypography.mono(
            size: 13,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
