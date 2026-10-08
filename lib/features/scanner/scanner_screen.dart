import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/exalted_button.dart';
import '../../core/widgets/exalted_logo.dart';
import '../gallery/gallery_import_service.dart';
import '../gallery/image_barcode_decoder.dart';
import '../ocr/controllers/ocr_controller.dart';
import '../ocr/views/ocr_result_screen.dart';
import '../ocr/widgets/image_action_sheet.dart';
import 'frame_pipeline.dart';
import 'link_utils.dart';
import 'scan_frame_painter.dart';
import 'scan_result_card.dart';
import 'scanner_controller.dart';
import 'scanner_widgets.dart';
import 'wifi_connector.dart';
import 'wifi_utils.dart';

/// Main scanner screen: live camera, scan frame, controls.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _line;

  // The camera screen always uses dark chrome.
  late final ThemeData _darkTheme = AppTheme.dark();

  Offset? _focusTap;
  int _focusId = 0;

  @override
  void initState() {
    super.initState();
    _line = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(navIndexProvider) == 0) {
        ref.read(scannerControllerProvider.notifier).start();
        _startLineAnimation();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _line.dispose();
    super.dispose();
  }

  void _startLineAnimation() {
    if (!mounted) return;
    if (!_line.isAnimating) {
      _line.repeat(reverse: true);
    }
  }

  void _stopLineAnimation() {
    if (_line.isAnimating) {
      _line.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final ctrl = ref.read(scannerControllerProvider.notifier);
    if (lifecycle == AppLifecycleState.resumed) {
      if (ref.read(navIndexProvider) == 0) {
        ctrl.start();
        _startLineAnimation();
      }
    } else if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.detached) {
      ctrl.stop();
      _stopLineAnimation();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  void _onFocusTap(Offset local, Size size) {
    final ui = ref.read(scannerControllerProvider);
    if (ui.status != CameraStatus.ready) return;

    HapticFeedback.selectionClick();

    setState(() {
      _focusTap = local;
      _focusId++;
    });

    ref
        .read(scannerControllerProvider.notifier)
        .focusAt(
          Offset(
            (local.dx / size.width).clamp(0.0, 1.0).toDouble(),
            (local.dy / size.height).clamp(0.0, 1.0).toDouble(),
          ),
        );
  }

  /// Gallery -> system photo picker -> choose what to do with the image.
  Future<void> _openGallery() async {
    HapticFeedback.selectionClick();

    final picked = await GalleryImportService().pickImage();

    if (!mounted) return;

    if (picked.error != null) {
      _snack(picked.error!);
      return;
    }

    final path = picked.path;
    if (path == null) return;

    final action = await showImageActionSheet(context, path);

    if (!mounted || action == null) return;

    if (action == GalleryAction.scanCode) {
      await _scanGalleryImage(path);
      return;
    }

    if (action == GalleryAction.extractText) {
      await _extractGalleryText(path);
    }
  }

  Future<void> _scanGalleryImage(String path) async {
    final ctrl = ref.read(scannerControllerProvider.notifier);

    _stopLineAnimation();
    await ctrl.stop();

    if (!mounted) return;

    _snack('Scanning image...');

    try {
      final barcode = await ImageBarcodeDecoder().decodeFile(path);

      if (!mounted) return;

      if (barcode == null) {
        _snack('No readable code found in this image');
      } else {
        ctrl.presentImported(barcode);
      }
    } catch (error) {
      if (mounted) {
        _snack("Couldn't scan this image");
      }

      debugPrint('[EXALTED][GALLERY] scan failed: $error');
    }

    if (!mounted) return;

    if (ref.read(navIndexProvider) == 0) {
      _startLineAnimation();
    }
  }

  Future<void> _extractGalleryText(String path) async {
    // Release the camera while the OCR screen is open.
    final ctrl = ref.read(scannerControllerProvider.notifier);

    _stopLineAnimation();
    await ctrl.stop();

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OcrResultScreen(imagePath: path)),
    );

    ref.read(ocrControllerProvider.notifier).reset();

    if (mounted && ref.read(navIndexProvider) == 0) {
      ctrl.start();
      _startLineAnimation();
    }
  }

  Future<void> _openLink(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!ok) {
        _snack("Couldn't open the link");
      }
    } catch (_) {
      _snack("Couldn't open the link");
    }
  }

  Future<void> _connectWifi(WifiNetworkInfo wifi) async {
    HapticFeedback.selectionClick();
    final result = await ref.read(wifiConnectorProvider).connect(wifi);
    if (!mounted) return;
    _snack(result.message);
  }

  String _hint(ScannerUiState ui) {
    switch (ui.status) {
      case CameraStatus.ready:
        return 'Align a code inside the frame';
      case CameraStatus.starting:
        return 'Starting camera...';
      default:
        return '';
    }
  }

  /// Full-bleed preview. The camera reports its size in landscape; the app is
  /// locked to portrait, so the portrait box is (short side x long side).
  Widget _preview(CameraController cam) {
    final size = cam.value.previewSize;

    if (!cam.value.isInitialized || size == null) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.shortestSide,
          height: size.longestSide,
          child: CameraPreview(cam),
        ),
      ),
    );
  }

  String _previewLabel(CameraController? cam) {
    final size = cam?.value.previewSize;

    if (size == null) return '-';

    return '${size.longestSide.toInt()}x${size.shortestSide.toInt()}';
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(scannerControllerProvider);
    final ctrl = ref.read(scannerControllerProvider.notifier);
    final pipeline = ref.read(framePipelineProvider);

    ref.listen<int>(navIndexProvider, (previous, next) {
      if (next == 0) {
        ctrl.start();
        _startLineAnimation();
      } else {
        ctrl.stop();
        _stopLineAnimation();
      }
    });

    ref.listen<String?>(scannerControllerProvider.select((s) => s.notice), (
      previous,
      next,
    ) {
      if (next != null) {
        _snack(next);
        ctrl.clearNotice();
      }
    });

    return Theme(
      data: _darkTheme,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final text = theme.textTheme;

          final ready = ui.status == CameraStatus.ready && ui.camera != null;

          final showPanel =
              ui.status == CameraStatus.needsPermission ||
              ui.status == CameraStatus.permissionDenied ||
              ui.status == CameraStatus.error;

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Container(
              color: const Color(0xFF0A0A0B),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;

                  var side = w * 0.74;

                  if (side > 300) {
                    side = 300;
                  }

                  final scanRect = Rect.fromCenter(
                    center: Offset(w / 2, h * 0.40),
                    width: side,
                    height: side,
                  );

                  final screenSize = Size(w, h);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background, only needed until the camera is ready.
                      if (!ready)
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(0, -0.2),
                                radius: 1.1,
                                colors: [Color(0xFF1B1C20), Color(0xFF0A0A0B)],
                              ),
                            ),
                          ),
                        ),

                      // Live camera preview, its own layer.
                      if (ready)
                        Positioned.fill(
                          child: RepaintBoundary(child: _preview(ui.camera!)),
                        ),

                      // Tap anywhere to focus.
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (d) =>
                              _onFocusTap(d.localPosition, screenSize),
                        ),
                      ),

                      // Static overlays (dim area + fades): painted once.
                      if (ready)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: _StaticOverlay(hole: scanRect),
                            ),
                          ),
                        ),

                      // Scan frame: only this small layer repaints each frame.
                      if (!showPanel)
                        Positioned.fromRect(
                          rect: scanRect,
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: Semantics(
                                label:
                                    'Scan area. Align a code inside the frame.',
                                child: AnimatedBuilder(
                                  animation: _line,
                                  builder: (context, child) {
                                    return CustomPaint(
                                      painter: ScanFramePainter(
                                        progress: Curves.easeInOut.transform(
                                          _line.value,
                                        ),
                                        color: scheme.primary,
                                        showLine: ready && !ui.paused,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Tap-to-focus ring.
                      if (_focusTap != null)
                        Positioned(
                          left: _focusTap!.dx - 32,
                          top: _focusTap!.dy - 32,
                          child: IgnorePointer(
                            child: FocusRing(
                              key: ValueKey(_focusId),
                              color: scheme.primary,
                            ),
                          ),
                        ),

                      // Permission / error panel.
                      if (showPanel)
                        Positioned.fill(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: _panelFor(ui, ctrl),
                            ),
                          ),
                        ),

                      // Controls overlay.
                      Positioned.fill(
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                            ),
                            child: Column(
                              children: [
                                const SizedBox(height: AppSpacing.md),

                                Row(
                                  children: [
                                    const ExaltedLogo(width: 120),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Settings',
                                      onPressed: () => ref
                                          .read(navIndexProvider.notifier)
                                          .set(2),
                                      icon: const Icon(Icons.settings_outlined),
                                      color: Colors.white,
                                      iconSize: 26,
                                      constraints: const BoxConstraints(
                                        minWidth: 48,
                                        minHeight: 48,
                                      ),
                                    ),
                                  ],
                                ),

                                ModeChip(
                                  continuous: ui.continuous,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    ctrl.toggleContinuous();
                                  },
                                ),

                                if (!kReleaseMode && ready)
                                  DebugStatsLine(
                                    pipeline: pipeline,
                                    streaming: ui.streaming,
                                    previewSize: _previewLabel(ui.camera),
                                    qualityLabel: ui.quality.label,
                                  ),

                                const Spacer(),

                                Text(
                                  _hint(ui),
                                  style: text.bodyMedium!.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),

                                const SizedBox(height: AppSpacing.xl),

                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    RoundControl(
                                      icon: ui.flashOn
                                          ? Icons.flash_on
                                          : Icons.flash_off,
                                      label: 'Flash',
                                      active: ui.flashOn,
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        ctrl.toggleFlash();
                                      },
                                    ),
                                    RoundControl(
                                      icon: Icons.bolt,
                                      label: 'Auto',
                                      active: ui.autoScan,
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        ctrl.toggleAuto();
                                      },
                                    ),
                                  ],
                                ),

                                const SizedBox(height: AppSpacing.xl),

                                ExaltedButton(
                                  label: 'Gallery',
                                  icon: Icons.photo_library_outlined,
                                  outlined: true,
                                  expand: true,
                                  onPressed: _openGallery,
                                ),

                                const SizedBox(height: AppSpacing.lg),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Decoded result card (top layer).
                      if (ui.result != null)
                        Positioned(
                          left: AppSpacing.xl,
                          right: AppSpacing.xl,
                          bottom:
                              AppSpacing.lg +
                              MediaQuery.of(context).padding.bottom,
                          child: ScanResultCard(
                            barcode: ui.result!,
                            onCopy: () {
                              Clipboard.setData(
                                ClipboardData(text: ui.result!.text),
                              );
                              HapticFeedback.selectionClick();
                              _snack('Copied');
                            },
                            onScanAgain: ctrl.resumeScanning,
                            onConnectWifi: () {
                              final wifi = parseWifiQr(ui.result!.text);
                              if (wifi != null) _connectWifi(wifi);
                            },
                            onOpenLink: linkUri(ui.result!.text) == null
                                ? null
                                : () => _openLink(linkUri(ui.result!.text)!),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _panelFor(ScannerUiState ui, ScannerController ctrl) {
    switch (ui.status) {
      case CameraStatus.needsPermission:
        return ScannerStatePanel(
          icon: Icons.camera_alt_outlined,
          title: 'Camera access needed',
          message:
              'Exalted uses the camera only to scan codes. '
              'Nothing leaves your device.',
          actionLabel: 'Allow camera',
          onAction: ctrl.requestPermission,
        );

      case CameraStatus.permissionDenied:
        return ScannerStatePanel(
          icon: Icons.no_photography_outlined,
          title: 'Camera permission is off',
          message:
              'Turn on the Camera permission for Exalted in Settings, '
              'then come back.',
          actionLabel: 'Open settings',
          onAction: ctrl.openSettings,
        );

      default:
        return ScannerStatePanel(
          icon: Icons.error_outline,
          title: "Couldn't start the camera",
          message: ui.errorMessage ?? 'Something went wrong.',
          actionLabel: 'Try again',
          onAction: ctrl.retry,
        );
    }
  }
}

/// Dim area outside the scan window plus top/bottom fades.
class _StaticOverlay extends StatelessWidget {
  const _StaticOverlay({required this.hole});

  final Rect hole;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: CustomPaint(painter: ScrimPainter(hole: hole)),
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 150,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xB3000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 300,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
