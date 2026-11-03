import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../ffi/decode_result.dart';
import 'camera_settings_dialog.dart';
import 'connected_scan_result_card.dart';
import 'frame_pipeline.dart';
import 'link_utils.dart';
import 'scan_frame_painter.dart';
import 'scanner_analyzer.dart';
import 'scanner_controller.dart';

/// The Decoder workspace for Windows and Linux.
///
/// It uses the same [ScannerController], decode isolate and result handling as
/// the phone scanner. Only the layout is different: a large preview, a compact
/// toolbar and a results panel.
class DesktopDecoderScreen extends ConsumerStatefulWidget {
  const DesktopDecoderScreen({super.key});

  @override
  ConsumerState<DesktopDecoderScreen> createState() =>
      _DesktopDecoderScreenState();
}

class _DesktopDecoderScreenState extends ConsumerState<DesktopDecoderScreen>
    with WidgetsBindingObserver {
  static const double _wideMin = 900;

  double _roiWidth = 0.7;
  double _roiHeight = 0.7;
  bool _panelOpen = true;
  double _panelWidth = 380;

  DateTime? _detectedAt;
  int _count = 0;
  bool _polygonVisible = false;
  Timer? _polygonTimer;
  Timer? _tick;
  int _lastFrames = -1;
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final frames = ref.read(scannerControllerProvider.notifier).cameraFrames;
      setState(() {
        _fps = _lastFrames < 0 ? 0 : (frames - _lastFrames).toDouble();
        _lastFrames = frames;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyRoi();
      if (ref.read(navIndexProvider) == kScanTab) {
        unawaited(ref.read(scannerControllerProvider.notifier).start());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _polygonTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final ctrl = ref.read(scannerControllerProvider.notifier);
    if (lifecycle == AppLifecycleState.resumed) {
      if (ref.read(navIndexProvider) == kScanTab) unawaited(ctrl.start());
    } else if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.detached) {
      unawaited(ctrl.stop());
    }
  }

  void _applyRoi() {
    final w = _roiWidth;
    final h = _roiHeight;
    ref.read(scannerAnalyzerProvider).scanWindow = Rect.fromLTRB(
      0.5 - w / 2,
      0.5 - h / 2,
      0.5 + w / 2,
      0.5 + h / 2,
    );
  }

  void _run(Future<void> Function() action) => unawaited(action());

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _openLink(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('Could not open the link');
    } catch (_) {
      _snack('Could not open the link');
    }
  }

  CameraController? _liveCamera(ScannerUiState ui) {
    final cam = ui.camera;
    if (cam != null &&
        ui.status == CameraStatus.ready &&
        cam.value.isInitialized) {
      return cam;
    }
    return null;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _hms(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  String _decoderStateLabel(ScannerUiState ui) {
    if (_liveCamera(ui) == null) return 'Camera not running';
    if (ui.result != null && !ui.continuous && ui.paused) {
      return 'Code detected. Scanning stopped (single scan).';
    }
    if (ui.paused) return 'Paused';
    return ui.continuous
        ? 'Scanning continuously for codes'
        : 'Waiting for one code';
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(scannerControllerProvider);
    final ctrl = ref.read(scannerControllerProvider.notifier);

    ref.listen<int>(navIndexProvider, (previous, next) {
      if (next == kScanTab) {
        unawaited(ctrl.start());
      } else {
        unawaited(ctrl.stop());
      }
    });

    ref.listen<DecodedBarcode?>(
      scannerControllerProvider.select((s) => s.result),
      (previous, next) {
        if (next == null) {
          _polygonVisible = false;
          return;
        }
        if (identical(previous, next)) return;
        _count++;
        _detectedAt = DateTime.now();
        _polygonVisible = true;
        _polygonTimer?.cancel();
        _polygonTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          setState(() {
            _polygonVisible = false;
          });
        });
      },
    );

    ref.listen<String?>(scannerControllerProvider.select((s) => s.notice), (
      previous,
      next,
    ) {
      if (next == null) return;
      ctrl.clearNotice();
      // That fallback text says "ready" even when no camera opened. The
      // preview area states the real situation instead.
      if (!next.startsWith('Desktop Mode')) _snack(next);
    });

    ref.listen<CameraStatus>(
      scannerControllerProvider.select((s) => s.status),
      (previous, next) {
        if (next == CameraStatus.ready) _applyRoi();
      },
    );

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= _wideMin;
          final workspace = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInfoLine(ui),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.exalted.canvas,
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      child: _buildPreview(ui, ctrl),
                    ),
                  ),
                ),
              ),
              _buildToolbar(ui, ctrl),
            ],
          );

          if (wide) {
            final panelW = _panelWidth
                .clamp(300.0, c.maxWidth * 0.5)
                .toDouble();
            return Row(
              children: [
                Expanded(child: workspace),
                if (_panelOpen) ...[
                  _buildHandle(),
                  SizedBox(width: panelW, child: _buildPanel(ui, ctrl)),
                ],
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: workspace),
              if (_panelOpen)
                SizedBox(height: 300, child: _buildPanel(ui, ctrl)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoLine(ScannerUiState ui) {
    final colors = context.exalted;
    final live = _liveCamera(ui);
    final size = live?.value.previewSize;
    final parts = <String>[
      live != null ? live.description.name : 'No camera running',
      if (size != null) '${size.width.toInt()}x${size.height.toInt()}',
      if (live != null && _fps > 0) '${_fps.toStringAsFixed(0)} fps',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        parts.join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium!
            .copyWith(color: colors.muted),
      ),
    );
  }

  Widget _buildPreview(ScannerUiState ui, ScannerController ctrl) {
    final live = _liveCamera(ui);
    if (live == null) return _buildStateView(ui, ctrl);
    final scheme = Theme.of(context).colorScheme;
    final size = live.value.previewSize;
    final aspect = (size == null || size.height == 0)
        ? 16 / 9
        : size.width / size.height;
    final result = ui.result;

    return LayoutBuilder(
      builder: (context, c) {
        var w = c.maxWidth;
        var h = w / aspect;
        if (h > c.maxHeight) {
          h = c.maxHeight;
          w = h * aspect;
        }
        final roi = Rect.fromCenter(
          center: Offset(w / 2, h / 2),
          width: w * _roiWidth,
          height: h * _roiHeight,
        );
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: CameraPreview(live)),
                IgnorePointer(
                  child: CustomPaint(
                    painter: ScrimPainter(hole: roi, opacity: 0.2),
                  ),
                ),
                if (result != null &&
                    _polygonVisible &&
                    result.corners.length >= 3 &&
                    result.frameWidth > 0 &&
                    result.frameHeight > 0)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _PolygonPainter(
                        corners: result.corners,
                        frameWidth: result.frameWidth.toDouble(),
                        frameHeight: result.frameHeight.toDouble(),
                        color: context.exalted.valid,
                        // Per the camera_desktop docs the Windows preview is
                        // mirrored in Flutter while stream frames are not.
                        flipX: Platform.isWindows,
                      ),
                    ),
                  ),
                Positioned.fromRect(
                  rect: roi,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: ScanFramePainter(
                        progress: 0,
                        color: scheme.primary,
                        showLine: false,
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStateView(ScannerUiState ui, ScannerController ctrl) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    final starting = ui.status == CameraStatus.starting;
    final needsPermission =
        ui.status == CameraStatus.needsPermission ||
        ui.status == CameraStatus.permissionDenied;
    final failed = ui.status == CameraStatus.error;
    final noCamera = ui.status == CameraStatus.ready && ui.camera == null;

    var icon = Icons.videocam_off_outlined;
    var title = 'Camera stopped';
    var detail =
        'The camera is released when you leave this screen or press Stop. '
        'Start it to scan.';
    String? action = 'Start camera';
    Future<void> Function() onAction = ctrl.start;

    if (starting) {
      icon = Icons.hourglass_top;
      title = 'Starting camera';
      detail = 'Opening the camera and starting the preview.';
      action = null;
    } else if (needsPermission) {
      icon = Icons.lock_outline;
      title = 'Camera permission required';
      detail = 'Allow camera access for Exalted in the system settings, then try again.';
      action = 'Allow camera';
      onAction = ctrl.requestPermission;
    } else if (failed) {
      icon = Icons.error_outline;
      title = 'Camera error';
      detail = ui.errorMessage ?? 'The camera could not be started.';
      action = 'Retry';
      onAction = ctrl.retry;
    } else if (noCamera) {
      icon = Icons.no_photography_outlined;
      title = 'No camera available';
      detail =
          'No camera could be opened. Check that a camera is connected and '
          'not used by another application, then retry.';
      action = 'Retry';
      onAction = ctrl.retry;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: colors.muted),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.muted,
                ),
              ),
              if (starting) ...[
                const SizedBox(height: AppSpacing.lg),
                const SizedBox(width: 180, child: LinearProgressIndicator()),
              ],
              if (action != null) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () => _run(onAction),
                  child: Text(action),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(ScannerUiState ui, ScannerController ctrl) {
    final live = _liveCamera(ui) != null;
    final running =
        ui.status == CameraStatus.starting || ui.status == CameraStatus.ready;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () => _run(running ? ctrl.stop : ctrl.start),
            icon: Icon(
              running ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            ),
            label: Text(running ? 'Stop camera' : 'Start camera'),
          ),
          FilledButton.tonalIcon(
            onPressed: live ? () => _run(ctrl.togglePause) : null,
            icon: Icon(ui.paused ? Icons.play_arrow : Icons.pause),
            label: Text(ui.paused ? 'Resume' : 'Pause'),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.looks_one_outlined),
                label: Text('Single'),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.repeat),
                label: Text('Continuous'),
              ),
            ],
            selected: {ui.continuous},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              if (s.first != ui.continuous) ctrl.toggleContinuous();
            },
          ),
          if (ui.result != null)
            FilledButton.icon(
              onPressed: () => _run(ctrl.resumeScanning),
              icon: const Icon(Icons.refresh),
              label: const Text('Scan again'),
            ),
          const Tooltip(
            message: 'Flash is not available on this camera',
            child: IconButton(onPressed: null, icon: Icon(Icons.flash_off)),
          ),
          OutlinedButton.icon(
            onPressed: () => showCameraSettingsDialog(context),
            icon: const Icon(Icons.tune),
            label: const Text('Camera settings'),
          ),
          IconButton(
            tooltip: _panelOpen ? 'Hide results panel' : 'Show results panel',
            onPressed: () {
              setState(() {
                _panelOpen = !_panelOpen;
              });
            },
            icon: const Icon(Icons.vertical_split_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    final colors = context.exalted;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) {
          setState(() {
            _panelWidth = (_panelWidth - d.delta.dx)
                .clamp(300.0, 560.0)
                .toDouble();
          });
        },
        child: SizedBox(
          width: 8,
          child: Center(child: Container(width: 1, color: colors.outline)),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ panel

  Widget _sectionTitle(String text) {
    final colors = context.exalted;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: colors.muted,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 12,
                color: colors.muted,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _roiSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.2,
            max: 1.0,
            divisions: 16,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(ScannerUiState ui, ScannerController ctrl) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    final r = ui.result;
    final live = _liveCamera(ui);
    final pipeline = ref.read(framePipelineProvider);
    final link = r == null ? null : linkUri(r.text);
    final stateColor = live == null
        ? colors.muted
        : (r != null ? colors.valid : colors.info);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Decoder', style: theme.textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'Hide results panel',
                onPressed: () {
                  setState(() {
                    _panelOpen = false;
                  });
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: stateColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _decoderStateLabel(ui),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          _sectionTitle('Last detection'),
          if (r == null)
            Text(
              live == null
                  ? 'Start the camera to scan.'
                  : (ui.paused
                        ? 'Paused. Resume to look for codes.'
                        : 'No code detected yet. Hold a code inside the scan area.'),
              style: theme.textTheme.bodyMedium!.copyWith(color: colors.muted),
            )
          else ...[
            _kv('Symbology', r.kind.label),
            _kv(
              'Decode time',
              '${(r.decodeMicros / 1000).toStringAsFixed(1)} ms',
            ),
            _kv(
              'Detected at',
              _detectedAt == null ? 'Not recorded' : _hms(_detectedAt!),
            ),
            _kv('Frame', '${r.frameWidth}x${r.frameHeight}'),
            _kv('Results this session', '$_count'),
            const SizedBox(height: AppSpacing.md),
            ConnectedScanResultCard(
              barcode: r,
              onCopy: () {
                Clipboard.setData(ClipboardData(text: r.text));
                _snack('Copied');
              },
              onScanAgain: ctrl.resumeScanning,
              onConnectWifi: () => _snack(
                'Connecting to Wi-Fi from a scanned code is only available on Android',
              ),
              onOpenLink: link == null ? null : () => _openLink(link),
            ),
          ],
          const Divider(height: AppSpacing.xl),
          _sectionTitle('Scan area'),
          _roiSlider('Width', _roiWidth, (v) {
            setState(() {
              _roiWidth = v;
            });
            _applyRoi();
          }),
          _roiSlider('Height', _roiHeight, (v) {
            setState(() {
              _roiHeight = v;
            });
            _applyRoi();
          }),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() {
                  _roiWidth = 0.7;
                  _roiHeight = 0.7;
                });
                _applyRoi();
              },
              child: const Text('Reset to 70%'),
            ),
          ),
          Text(
            'Decoding focuses on this area.',
            style: theme.textTheme.bodyMedium!.copyWith(
              fontSize: 12,
              color: colors.muted,
            ),
          ),
          const Divider(height: AppSpacing.xl),
          _sectionTitle('Measured'),
          _kv(
            'Camera stream',
            live != null && _fps > 0
                ? '${_fps.toStringAsFixed(0)} fps'
                : 'Not running',
          ),
          _kv('Frames analyzed', '${pipeline.analyzedTotal}'),
          _kv('Skipped (decoder busy)', '${pipeline.busySkippedTotal}'),
        ],
      ),
    );
  }
}

/// Draws the detected code outline over the preview. The corners are in
/// camera-image pixels, so they are scaled to the preview size.
class _PolygonPainter extends CustomPainter {
  _PolygonPainter({
    required this.corners,
    required this.frameWidth,
    required this.frameHeight,
    required this.color,
    required this.flipX,
  });

  final List<Offset> corners;
  final double frameWidth;
  final double frameHeight;
  final Color color;
  final bool flipX;

  Offset _map(Offset p, Size size) {
    final x = p.dx / frameWidth * size.width;
    return Offset(flipX ? size.width - x : x, p.dy / frameHeight * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final first = _map(corners.first, size);
    final path = Path()..moveTo(first.dx, first.dy);
    for (var i = 1; i < corners.length; i++) {
      final p = _map(corners[i], size);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PolygonPainter old) =>
      old.corners != corners ||
      old.frameWidth != frameWidth ||
      old.frameHeight != frameHeight ||
      old.color != color ||
      old.flipX != flipX;
}
