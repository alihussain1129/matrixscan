import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/devices/keyence/keyence_scanner_coordinator.dart';
import '../../features/devices/keyence/keyence_sr751_client.dart';
import '../../features/ocr/services/tesseract_locator.dart';
import '../../features/scanner/camera_settings_dialog.dart';
import '../../features/scanner/scanner_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../router/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';
import '../widgets/status_badge.dart';

/// What was actually found about the OCR engine on this machine.
@immutable
class OcrAvailability {
  const OcrAvailability({required this.label, required this.ok});

  final String label;
  final bool ok;
}

/// Runs `tesseract --list-langs` once. Nothing is claimed that this check did
/// not see: the label lists the language data that is really installed.
final ocrAvailabilityProvider = FutureProvider<OcrAvailability>((ref) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return const OcrAvailability(label: 'OCR: Google ML Kit', ok: false);
  }

  final installation = await TesseractLocator.discover();
  if (installation == null) {
    return const OcrAvailability(label: 'OCR: Tesseract not found', ok: false);
  }

  final languages = installation.displayLanguages;
  if (!installation.supportsLanguage('eng')) {
    final available = languages.isEmpty ? 'none' : languages.join(', ');
    return OcrAvailability(
      label: 'OCR: Tesseract found; English data missing ($available)',
      ok: false,
    );
  }

  final languageLabel = languages.isEmpty ? 'eng' : languages.join(', ');
  return OcrAvailability(
    label: 'OCR: Tesseract ($languageLabel), runs locally',
    ok: true,
  );
});

/// Camera state in words, from the real scanner state.
String cameraStateLabel(ScannerUiState ui) {
  if (ui.status == CameraStatus.ready && ui.camera != null) {
    return ui.paused ? 'Camera on, paused' : 'Camera on';
  }
  if (ui.status == CameraStatus.starting) return 'Camera starting';
  if (ui.status == CameraStatus.error) return 'Camera error';
  if (ui.status == CameraStatus.needsPermission ||
      ui.status == CameraStatus.permissionDenied) {
    return 'Camera permission needed';
  }
  if (ui.status == CameraStatus.ready) return 'No camera available';
  return 'Camera stopped';
}

// ---------------------------------------------------------------- top bar

class DesktopTopBar extends ConsumerWidget {
  const DesktopTopBar({
    super.key,
    required this.title,
    this.onOpenCommandPalette,
    this.scannerActive = false,
    this.devicesActive = false,
  });

  final String title;
  final VoidCallback? onOpenCommandPalette;
  final bool scannerActive;
  final bool devicesActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.exalted;
    final theme = Theme.of(context);
    final ui = scannerActive ? ref.watch(scannerControllerProvider) : null;
    final keyence = devicesActive
        ? ref.watch(keyenceScannerCoordinatorProvider)
        : null;
    final mode = ref.watch(themeModeProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 950;
    final live = ui?.status == CameraStatus.ready && ui?.camera != null;
    final processing = !live
        ? 'Idle'
        : (ui?.paused == true ? 'Paused' : 'Scanning');
    final stateColor = live
        ? colors.valid
        : (ui?.status == CameraStatus.error
              ? theme.colorScheme.error
              : colors.muted);

    return Container(
      height: AppSizes.toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: AppMotion.fast,
            child: Text(
              title,
              key: ValueKey<String>(title),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          // KEYENCE SR-751 Quick Status Badge (Interactive)
          InkWell(
            onTap: () => ref.read(navIndexProvider.notifier).set(kDevicesTab),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Tooltip(
              message: keyence == null
                  ? 'Open Devices to check or connect an industrial scanner'
                  : keyence.isConnected
                  ? 'KEYENCE ${keyence.model} Connected (${keyence.host}:${keyence.port}) — Click to Manage'
                  : 'KEYENCE Industrial Scanner: ${keyence.isDiscovering ? 'Discovering...' : 'Offline'} — Click to Connect',
              child: StatusBadge(
                label: keyence == null
                    ? 'Devices'
                    : keyence.isConnected
                    ? 'KEYENCE ${keyence.model}'
                    : (keyence.isDiscovering
                          ? 'Discovering...'
                          : 'Scanner Offline'),
                sublabel: keyence?.isConnected == true
                    ? '${keyence!.totalConnectionTimeMs}ms'
                    : null,
                variant: keyence == null
                    ? StatusBadgeVariant.neutral
                    : keyence.isConnected
                    ? StatusBadgeVariant.success
                    : (keyence.isDiscovering
                          ? StatusBadgeVariant.processing
                          : StatusBadgeVariant.neutral),
                icon: Icons.router_outlined,
                compact: true,
              ),
            ),
          ),
          if (!isCompact && scannerActive) ...[
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Tooltip(
                message: ui?.camera?.description.name ?? 'No camera open',
                child: _StateChip(
                  icon: Icons.videocam_outlined,
                  label: cameraStateLabel(ui!),
                  color: stateColor,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: _StateChip(
                icon: Icons.qr_code_scanner,
                label: processing,
                color: live && ui.paused != true ? colors.info : colors.muted,
              ),
            ),
          ],
          const Spacer(),
          if (onOpenCommandPalette != null && !isCompact)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: OutlinedButton.icon(
                onPressed: onOpenCommandPalette,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Go to  Ctrl+K'),
              ),
            ),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined, size: 16),
                tooltip: 'System theme',
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined, size: 16),
                tooltip: 'Light theme',
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined, size: 16),
                tooltip: 'Dark theme',
              ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Camera settings',
            icon: const Icon(Icons.tune, size: 18),
            onPressed: () => showCameraSettingsDialog(context),
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.exalted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizes.iconSm, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- status bar

/// Shows only what the app measured or checked. No readiness is assumed.
class DesktopStatusBar extends ConsumerStatefulWidget {
  const DesktopStatusBar({
    super.key,
    this.scannerActive = false,
    this.devicesActive = false,
  });

  final bool scannerActive;
  final bool devicesActive;

  @override
  ConsumerState<DesktopStatusBar> createState() => _DesktopStatusBarState();
}

class _DesktopStatusBarState extends ConsumerState<DesktopStatusBar> {
  Timer? _timer;
  int _last = -1;
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!widget.scannerActive) return;
      final frames = ref.read(scannerControllerProvider.notifier).cameraFrames;
      setState(() {
        _fps = _last < 0 ? 0 : (frames - _last).toDouble();
        _last = frames;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.exalted;
    final ui = widget.scannerActive
        ? ref.watch(scannerControllerProvider)
        : null;
    final keyence = widget.devicesActive
        ? ref.watch(keyenceScannerCoordinatorProvider)
        : null;
    final connected = keyence?.isConnected ?? false;
    final cam = ui?.camera;
    final live = ui?.status == CameraStatus.ready && cam != null;

    var cameraText = ui == null
        ? 'Camera: not initialized'
        : cameraStateLabel(ui);
    if (live && cam.value.isInitialized) {
      final size = cam.value.previewSize;
      final res = size == null
          ? ''
          : ' · ${size.width.toInt()}x${size.height.toInt()}';
      final rate = _fps > 0 ? ' · ${_fps.toStringAsFixed(0)} fps' : '';
      cameraText = '${cam.description.name}$res$rate';
    }

    final decoderText = !live
        ? 'Decoder: idle'
        : (ui?.paused == true
              ? 'Decoder: paused'
              : ui == null
              ? 'Decoder: not initialized'
              : 'Decoder: scanning (${ui.continuous ? 'continuous' : 'single'})');

    final platform = Platform.isLinux
        ? 'Linux x64'
        : Platform.isWindows
        ? 'Windows x64'
        : Platform.operatingSystem;

    String keyenceText;
    if (keyence == null) {
      keyenceText = 'KEYENCE: open Devices for status';
    } else if (connected) {
      keyenceText =
          'KEYENCE ${keyence.model} connected · ${keyence.host}:${keyence.port} (${keyence.totalConnectionTimeMs}ms)';
    } else if (keyence.isDiscovering) {
      keyenceText = 'KEYENCE: Discovering scanners...';
    } else if (keyence.status == KeyenceConnectionStatus.connecting) {
      keyenceText = 'KEYENCE: Connecting to ${keyence.host}...';
    } else {
      keyenceText = 'KEYENCE: Offline';
    }

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: Row(
        children: [
          _StatusItem(
            icon: Icons.videocam_outlined,
            text: cameraText,
            color: live ? colors.valid : colors.muted,
          ),
          const SizedBox(width: AppSpacing.lg),
          _StatusItem(
            icon: Icons.qr_code_scanner,
            text: decoderText,
            color: live && ui?.paused != true ? colors.valid : colors.muted,
          ),
          const SizedBox(width: AppSpacing.lg),
          const _StatusItem(
            icon: Icons.text_fields_outlined,
            text: 'OCR: open workspace for status',
            color: Colors.grey,
          ),
          const SizedBox(width: AppSpacing.lg),
          _StatusItem(
            icon: Icons.router_outlined,
            text: keyenceText,
            color: connected
                ? colors.valid
                : (keyence?.isDiscovering == true ? colors.aqua : colors.muted),
          ),
          if (MediaQuery.sizeOf(context).width > 1200) ...[
            const SizedBox(width: AppSpacing.lg),
            Text(platform, style: Theme.of(context).textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall!
        .copyWith(color: color);
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizes.iconXs, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
