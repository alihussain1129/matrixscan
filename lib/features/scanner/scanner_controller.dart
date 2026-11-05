import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:camera_desktop/camera_desktop.dart';
import 'dart:typed_data';
import 'desktop_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../ffi/decode_result.dart';
import '../history/history_entry.dart';
import '../history/history_repository.dart';
import 'frame_pipeline.dart';
import 'scanner_analyzer.dart';
import 'scan_feedback.dart';
import 'detection_events.dart';
import '../inspection/combined_inspector.dart';
import 'captured_frame.dart';

enum CameraStatus {
  idle,
  starting,
  ready,
  needsPermission,
  permissionDenied,
  error,
}

const String _qualityDefine = String.fromEnvironment('EXALTED_QUALITY');
const CameraQuality _defaultQuality = _qualityDefine == 'high' ? CameraQuality.high : (_qualityDefine == 'ultra' ? CameraQuality.ultra : CameraQuality.balanced);

enum CameraQuality {
  balanced('Balanced', ResolutionPreset.medium),
  high('High', ResolutionPreset.high),
  ultra('Ultra', ResolutionPreset.veryHigh);

  const CameraQuality(this.label, this.preset);

  final String label;
  final ResolutionPreset preset;
}

/// UI state of the scanner.
///
/// Per-frame diagnostics live in [FramePipeline.stats], so this state does
/// not rebuild on every camera frame.
class ScannerUiState {
  const ScannerUiState({
    this.status = CameraStatus.idle,
    this.camera,
    this.flashOn = false,
    this.continuous = false,
    this.autoScan = true,
    this.paused = false,
    this.quality = _defaultQuality,
    this.errorMessage,
    this.notice,
    this.result,
  });

  final CameraStatus status;
  final CameraController? camera;
  final bool flashOn;
  final bool continuous;
  final bool autoScan;
  final bool paused;
  final CameraQuality quality;
  final String? errorMessage;
  final String? notice;
  final DecodedBarcode? result;

  /// True while camera frames are being sent to the frame pipeline.
  bool get streaming => autoScan && !paused;

  ScannerUiState copyWith({
    CameraStatus? status,
    CameraController? camera,
    bool clearCamera = false,
    bool? flashOn,
    bool? continuous,
    bool? autoScan,
    bool? paused,
    CameraQuality? quality,
    String? errorMessage,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
    DecodedBarcode? result,
    bool clearResult = false,
  }) {
    return ScannerUiState(
      status: status ?? this.status,
      camera: clearCamera ? null : (camera ?? this.camera),
      flashOn: flashOn ?? this.flashOn,
      continuous: continuous ?? this.continuous,
      autoScan: autoScan ?? this.autoScan,
      paused: paused ?? this.paused,
      quality: quality ?? this.quality,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      notice: clearNotice ? null : (notice ?? this.notice),
      result: clearResult ? null : (result ?? this.result),
    );
  }
}

/// Owns the camera: permission, start/stop, flash, focus, pause.
///
/// Frames go to [FramePipeline]; this class never analyzes them directly.
class ScannerController extends Notifier<ScannerUiState> {
  CameraController? _camera;
  List<CameraDescription>? _cameras;
  Future<List<CameraDescription>>? _camerasFuture;

  int _rotation = 90;
  int _lastGrayMs = -1000;
  final GrayConverter _gray = GrayConverter();

  /// Camera frames received so far. Read once per second to measure the
  /// real frame rate.
  int cameraFrames = 0;

  bool _starting = false;
  bool _wantRunning = false;

  bool _syncing = false;
  bool _syncAgain = false;

  FramePipeline get _pipeline => ref.read(framePipelineProvider);

  void _startup(String what) => ScannerAnalyzer.startupLog(what);

  ScannerAnalyzer get _analyzer => ref.read(scannerAnalyzerProvider);

  final Stopwatch _resultClock = Stopwatch()..start();

  /// Groups the per-frame decoder hits into detection events.
  final DetectionEventTracker _events = DetectionEventTracker();
  int _suppressedHits = 0;

  /// Pending request for the next camera frame (used by OCR).
  Completer<CapturedFrame>? _grab;
  int _scanStartMs = 0;

  @override
  ScannerUiState build() {
    // The analyzer belongs to the scanner provider graph. Wire its result
    // callback here so every native decode reaches the controller/UI.
    final analyzer = _analyzer;
    final pipeline = _pipeline;
    analyzer.onDecoded = _onDecoded;
    _gray.onGray = _onGray;
    _startup('scanner created');

    // Warm up in parallel with the camera start: native library, decode
    // isolate and the camera list.
    unawaited(analyzer.prewarm());
    if (Platform.isAndroid) {
      final cameras = _camerasFuture ??= availableCameras();
      unawaited(cameras.then<void>((_) {}, onError: (Object _) {}));
    }

    ref.onDispose(() {
      // Providers must not be read inside onDispose, so use the objects
      // captured above.
      analyzer.onDecoded = null;
      _gray.dispose();

      _wantRunning = false;

      final cam = _camera;
      _camera = null;

      if (cam != null) {
        unawaited(cam.dispose());
      }

      pipeline.stop();
    });

    unawaited(_loadQuality()); return const ScannerUiState();
  }

  // ---- simple toggles ----------------------------------------------------

    static const String _qualityKey = 'exalted_camera_quality';

  Future<void> _loadQuality() async {
    if (_qualityDefine.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_qualityKey);
      for (final q in CameraQuality.values) {
        if (q.name == saved && q != state.quality) {
          state = state.copyWith(quality: q);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveQuality(CameraQuality quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_qualityKey, quality.name);
    } catch (_) {}
  }

  void toggleContinuous() {
    final next = !state.continuous;
    // Leaving Single mode while it is stopped on a result: scanning must
    // restart by itself, without Scan Again.
    if (next && state.paused && state.result != null) {
      _events.reset();
      state = state.copyWith(continuous: true, clearResult: true, paused: false);
      unawaited(_syncStream());
      return;
    }
    state = state.copyWith(continuous: next);
  }

  Future<void> toggleAuto() async {
    state = state.copyWith(autoScan: !state.autoScan);
    await _syncStream();
  }

  /// Applied the next time the camera starts.
  void setQuality(CameraQuality quality) {
    state = state.copyWith(quality: quality); unawaited(_saveQuality(quality));
  }

  void clearNotice() {
    state = state.copyWith(clearNotice: true);
  }

  // ---- camera lifecycle --------------------------------------------------

  /// Starts the camera if permission is granted, otherwise exposes the
  /// appropriate permission state.
  ///
  /// Safe to call repeatedly.
  Future<void> start() async {
    _wantRunning = true;

    if (_camera != null && _camera!.value.isInitialized) {
      await _syncStream();
      return;
    }

    if (_starting) return;

    _starting = true;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final permission = await Permission.camera.status;
        _startup('camera permission checked');

        if (permission.isGranted) {
          await _openCamera();
        } else if (permission.isPermanentlyDenied) {
          state = state.copyWith(status: CameraStatus.permissionDenied);
        } else {
          state = state.copyWith(status: CameraStatus.needsPermission);
        }
      } else {
        // Desktop platforms (Linux / Windows)
        try {
          await _openCamera();
        } catch (_) {
          state = state.copyWith(
            status: CameraStatus.ready,
            clearCamera: true,
            notice: 'Desktop Mode: Image & Document Decoder Ready',
          );
        }
      }
    } catch (e) {
      debugPrint('[EXALTED][CAMERA] start failed: $e');

      if (!Platform.isAndroid && !Platform.isIOS) {
        state = state.copyWith(
          status: CameraStatus.ready,
          clearCamera: true,
          notice: 'Desktop Mode: Image & Document Decoder Ready',
        );
      } else {
        state = state.copyWith(
          status: CameraStatus.error,
          errorMessage: 'Could not start the camera.',
        );
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _openCamera() async {
    state = state.copyWith(status: CameraStatus.starting, clearError: true);

    if (_cameras == null) {
      try {
        _cameras = await (_camerasFuture ?? availableCameras());
      } catch (_) {
        _camerasFuture = null;
        rethrow;
      }
    }
    _startup('camera list ready');

    final cameras = _cameras!;
    final camNames = cameras
        .map((c) => '${c.name}:${c.lensDirection.name}:${c.sensorOrientation}')
        .join(' ');
    debugPrint('[EXALTED][CAMERA] cameras: $camNames');

    if (cameras.isEmpty) {
      state = state.copyWith(
        status: CameraStatus.error,
        errorMessage: 'No camera was found on this device.',
      );
      return;
    }

    final description = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      description,
      state.quality.preset,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      _startup('camera initialized');

      if (Platform.isLinux) {
        // The Linux plugin mirrors by default. A mirrored image breaks
        // barcode decoding, so turn it off.
        try {
          await CameraDesktopPlugin().setMirror(controller.cameraId, false);
          debugPrint('[EXALTED][CAMERA] mirror off');
        } catch (e) {
          debugPrint('[EXALTED][CAMERA] mirror setting failed: $e');
        }
      }

      // Explicitly request automatic focus. This is non-fatal because
      // camera implementations differ in their supported controls.
      try {
        unawaited(
          controller
              .setFocusMode(FocusMode.auto)
              .then((_) => debugPrint('[EXALTED][CAMERA] focus mode: auto'))
              .catchError(
                (Object e) =>
                    debugPrint('[EXALTED][CAMERA] focus mode unavailable: $e'),
              ),
        );
      } catch (e) {
        debugPrint('[EXALTED][CAMERA] focus mode unavailable: $e');
      }

      // Keep exposure automatic so changing lighting does not leave the
      // barcode excessively dark or bright.
      try {
        unawaited(
          controller
              .setExposureMode(ExposureMode.auto)
              .then((_) => debugPrint('[EXALTED][CAMERA] exposure mode: auto'))
              .catchError(
                (Object e) => debugPrint(
                  '[EXALTED][CAMERA] exposure mode unavailable: $e',
                ),
              ),
        );
      } catch (e) {
        debugPrint('[EXALTED][CAMERA] exposure mode unavailable: $e');
      }

      if (state.flashOn) {
        try {
          await controller.setFlashMode(FlashMode.torch);
        } catch (_) {
          state = state.copyWith(
            flashOn: false,
            notice: 'Flash is not available on this camera',
          );
        }
      }
    } catch (e) {
      debugPrint('[EXALTED][CAMERA] initialization failed: $e');

      try {
        await controller.dispose();
      } catch (_) {}

      if (e is CameraException && e.code.startsWith('CameraAccess')) {
        state = state.copyWith(status: CameraStatus.permissionDenied);
      } else {
        state = state.copyWith(
          status: CameraStatus.error,
          errorMessage:
              'Could not open the camera. Close other apps that '
              'use it and try again.',
        );
      }

      return;
    }

    if (!_wantRunning) {
      try {
        await controller.dispose();
      } catch (_) {}

      state = state.copyWith(status: CameraStatus.idle);

      return;
    }

    _camera = controller;
    _rotation = description.sensorOrientation;
    _startup('camera ready, preview can show');

    state = state.copyWith(
      status: CameraStatus.ready,
      camera: controller,
      paused: false,
    );

    await _syncStream();
  }

  Future<void> stop() async {
    _wantRunning = false;

    final cam = _camera;

    if (cam == null) {
      _pipeline.stop();

      state = state.copyWith(
        status: CameraStatus.idle,
        clearCamera: true,
        paused: false,
      );

      return;
    }

    _camera = null;

    _pipeline.stop();

    state = state.copyWith(
      status: CameraStatus.idle,
      clearCamera: true,
      paused: false,
    );

    // Give the camera plugin a frame boundary before tearing down the
    // stream. This avoids racing the Android image callback.
    await Future.any<void>([
      WidgetsBinding.instance.endOfFrame,
      Future<void>.delayed(const Duration(milliseconds: 100)),
    ]);

    try {
      if (cam.value.isStreamingImages) {
        await cam.stopImageStream();
      }
    } catch (_) {}

    try {
      await cam.dispose();
    } catch (_) {}
  }

  Future<void> retry() async {
    await stop();
    await start();
  }

  /// A copy of the next camera frame, or null when none arrives in time.
  /// Used to run OCR on the same image the decoder is looking at.
  Future<CapturedFrame?> grabFrame({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_camera == null || !_wantRunning) return null;
    final c = _grab ??= Completer<CapturedFrame>();
    try {
      return await c.future.timeout(timeout);
    } on TimeoutException {
      if (identical(_grab, c)) _grab = null;
      return null;
    }
  }

  // ---- frame stream ------------------------------------------------------

  void _onGray(Uint8List gray, int width, int height) {
    if (!_wantRunning || state.paused || !state.autoScan) return;
    _pipeline.submit(
      width: width,
      height: height,
      rotationDegrees: _rotation,
      yPlane: gray,
      yRowStride: width,
    );
  }

  void _onFrame(CameraImage image) {
    cameraFrames++;
    final grab = _grab;
    if (grab != null && !grab.isCompleted) {
      _grab = null;
      grab.complete(CapturedFrame.fromCameraImage(image, _rotation));
    }
    if (!_wantRunning || state.paused || !state.autoScan) {
      return;
    }

    final y = image.planes.first;

    if (image.format.group == ImageFormatGroup.bgra8888) {
      // Desktop cameras send BGRA. The decoder wants one gray byte per
      // pixel, so convert here, at most about 15 times per second.
      final now = _resultClock.elapsedMilliseconds;
      if (now - _lastGrayMs < 66) return;
      // The conversion runs on a background isolate. The frame is skipped
      // when that isolate is still busy with the previous one.
      if (_gray.submit(y.bytes, image.width, image.height, y.bytesPerRow)) {
        _lastGrayMs = now;
      }
      return;
    }

    _pipeline.submit(
      width: image.width,
      height: image.height,
      rotationDegrees: _rotation,
      yPlane: y.bytes,
      yRowStride: y.bytesPerRow,
    );
  }

  Future<void> _syncStream() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }

    _syncing = true;

    try {
      do {
        _syncAgain = false;
        await _applyStream();
      } while (_syncAgain);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _applyStream() async {
    final cam = _camera;

    if (cam == null || !cam.value.isInitialized) {
      return;
    }

    // Keep the camera stream running while a result is on screen. Restarting
    // it costs about 400 ms before the first frame arrives, so Scan Again
    // would feel slow. _onFrame drops frames while paused.
    final want = _wantRunning && state.autoScan;

    try {
      if (want && !cam.value.isStreamingImages) {
        await cam.startImageStream(_onFrame);
        _startup('image stream started');
        _pipeline.start();

        debugPrint(
          '[EXALTED][CAMERA] image stream started, '
          'preview=${cam.value.previewSize}',
        );
      } else if (!want && cam.value.isStreamingImages) {
        await cam.stopImageStream();
        _pipeline.stop();

        debugPrint('[EXALTED][CAMERA] image stream stopped');
      } else if (want) {
        _pipeline.start();
      } else {
        _pipeline.stop();
      }
    } catch (e) {
      debugPrint('[EXALTED][CAMERA] image stream change failed: $e');
    }
  }

  // ---- permission --------------------------------------------------------

  Future<void> requestPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      await start();
      return;
    }
    final result = await Permission.camera.request();

    if (result.isGranted) {
      await start();
    } else if (result.isPermanentlyDenied) {
      state = state.copyWith(status: CameraStatus.permissionDenied);
    } else {
      state = state.copyWith(status: CameraStatus.needsPermission);
    }
  }

  Future<void> openSettings() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await openAppSettings();
    }
  }

  // ---- scanner controls --------------------------------------------------

  Future<void> toggleFlash() async {
    final next = !state.flashOn;

    state = state.copyWith(flashOn: next);

    final cam = _camera;

    if (cam == null || !cam.value.isInitialized) {
      return;
    }

    try {
      await cam.setFlashMode(next ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      state = state.copyWith(
        flashOn: !next,
        notice: 'Flash is not available on this camera',
      );
    }
  }

  /// [point] is normalized: (0,0) top-left to (1,1) bottom-right.
  Future<void> focusAt(Offset point) async {
    final cam = _camera;

    if (cam == null || !cam.value.isInitialized) {
      return;
    }

    try {
      await cam.setFocusPoint(point);
    } catch (_) {}

    try {
      await cam.setExposurePoint(point);
    } catch (_) {}
  }

  Future<void> togglePause() async {
    if (_camera == null) {
      return;
    }

    final resuming = state.paused;
    if (resuming) _events.reset();

    state = state.copyWith(paused: !state.paused, clearResult: resuming);

    await _syncStream();
  }

  Future<void> resumeScanning() async {
    debugPrint('[EXALTED][SCAN] scan again');
    _events.reset();
    _scanStartMs = _resultClock.elapsedMilliseconds;
    state = state.copyWith(clearResult: true, paused: false);

    await _syncStream();
  }

  // ---- decoded results --------------------------------------------------

  void _onDecoded(DecodedBarcode barcode) {
    if (state.result != null && !state.continuous) {
      return;
    }

    final now = _resultClock.elapsedMilliseconds;

    // The analyzer reports a hit on nearly every frame while a code stays in
    // view. All of those frames are one detection event. A new event starts
    // when the payload changes or the code was out of view for the re-arm gap,
    // so the same payload on a new product is recorded again.
    if (!_events.observe(barcode.text, now, ref.read(rearmGapProvider))) {
      _suppressedHits++;
      return;
    }
    debugPrint(
      '[EXALTED][EVENT] t=${now}ms continuous=${state.continuous} '
      'gap=${ref.read(rearmGapProvider)}ms sameFramesBefore=$_suppressedHits '
      'textLength=${barcode.text.length}',
    );
    _suppressedHits = 0;

    HapticFeedback.mediumImpact();
    unawaited(ScanFeedback.beep());

    debugPrint('[EXALTED][RESULT] shown: $barcode');
    debugPrint(
      '[EXALTED][BENCH] ${barcode.kind.label} ttd=${now - _scanStartMs}ms '
      'decode=${(barcode.decodeMicros / 1000).toStringAsFixed(1)}ms '
      'frame=${barcode.frameWidth}x${barcode.frameHeight}',
    );

    _saveToHistory(barcode, HistorySource.live);

    final pause = !state.continuous;

    state = state.copyWith(
      result: barcode,
      paused: pause ? true : state.paused,
    );

    if (pause) {
      unawaited(_syncStream());
    }
  }

  /// Saves a successful scan. Fire and forget: the repository never throws,
  /// and a failure here must never affect scanning.
  void _saveToHistory(DecodedBarcode barcode, HistorySource source) {
    try {
      unawaited(
        ref
            .read(historyRepositoryProvider)
            .add(
              kind: HistoryKind.barcode,
              source: source,
              text: barcode.text,
              format: barcode.kind.label,
              processingDurationMs: barcode.decodeMicros / 1000,
              // Event tracking already removed per-frame repeats.
              allowRepeat: source == HistorySource.live,
            ),
      );
      // One related data row per inspection event (fields, checks, status).
      unawaited(
        ref
            .read(combinedInspectorProvider.notifier)
            .record(
              raw: barcode.text,
              symbology: barcode.kind.label,
              source: source.name,
              decodeMs: barcode.decodeMicros / 1000,
            ),
      );
    } catch (e) {
      debugPrint('[EXALTED][HISTORY] save skipped: $e');
    }
  }

  /// Shows a barcode decoded from an imported gallery image.
  void presentImported(DecodedBarcode barcode) {
    _events.reset();

    HapticFeedback.mediumImpact();
    unawaited(ScanFeedback.beep());

    debugPrint('[EXALTED][RESULT] shown (gallery): $barcode');

    _saveToHistory(barcode, HistorySource.gallery);

    state = state.copyWith(result: barcode, paused: true);

    unawaited(_syncStream());
  }
}

final scannerControllerProvider =
    NotifierProvider<ScannerController, ScannerUiState>(ScannerController.new);

