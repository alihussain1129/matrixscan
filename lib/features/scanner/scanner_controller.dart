import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'frame_pipeline.dart';

enum CameraStatus {
  idle,
  starting,
  ready,
  needsPermission,
  permissionDenied,
  error,
}

/// Camera quality. Balanced is faster on older phones, High reads small
/// codes better.
enum CameraQuality {
  balanced('Balanced', ResolutionPreset.medium),
  high('High', ResolutionPreset.high);

  const CameraQuality(this.label, this.preset);

  final String label;
  final ResolutionPreset preset;
}

/// UI state of the scanner. Changes rarely, so rebuilds stay cheap.
/// Per-frame numbers live in [FramePipeline.stats], not here.
class ScannerUiState {
  const ScannerUiState({
    this.status = CameraStatus.idle,
    this.camera,
    this.flashOn = false,
    this.continuous = false,
    this.autoScan = true,
    this.paused = false,
    this.quality = CameraQuality.high,
    this.errorMessage,
    this.notice,
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
    );
  }
}

/// Owns the camera: permission, start/stop, flash, focus, pause.
/// Frames go to [FramePipeline]; this class never analyzes them.
class ScannerController extends Notifier<ScannerUiState> {
  CameraController? _camera;
  List<CameraDescription>? _cameras;
  int _rotation = 90;
  bool _starting = false;
  bool _wantRunning = false;
  bool _syncing = false;
  bool _syncAgain = false;

  FramePipeline get _pipeline => ref.read(framePipelineProvider);

  @override
  ScannerUiState build() {
    ref.onDispose(() {
      _camera?.dispose();
    });
    return const ScannerUiState();
  }

  // ---- simple toggles ----------------------------------------------------

  void toggleContinuous() =>
      state = state.copyWith(continuous: !state.continuous);

  Future<void> toggleAuto() async {
    state = state.copyWith(autoScan: !state.autoScan);
    await _syncStream();
  }

  /// Applied the next time the camera starts (it is off while Settings is open).
  void setQuality(CameraQuality quality) =>
      state = state.copyWith(quality: quality);

  void clearNotice() => state = state.copyWith(clearNotice: true);

  // ---- camera lifecycle --------------------------------------------------

  /// Starts the camera if permission is granted, otherwise shows the
  /// permission screen. Safe to call many times.
  Future<void> start() async {
    _wantRunning = true;
    if (_starting || _camera != null) return;
    _starting = true;
    try {
      final permission = await Permission.camera.status;
      if (permission.isGranted) {
        await _openCamera();
      } else if (permission.isPermanentlyDenied) {
        state = state.copyWith(status: CameraStatus.permissionDenied);
      } else {
        state = state.copyWith(status: CameraStatus.needsPermission);
      }
    } catch (e) {
      debugPrint('Camera start failed: $e');
      state = state.copyWith(
        status: CameraStatus.error,
        errorMessage: 'The camera is not available on this device.',
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> _openCamera() async {
    state = state.copyWith(status: CameraStatus.starting, clearError: true);

    _cameras ??= await availableCameras();
    final cameras = _cameras!;
    if (cameras.isEmpty) {
      state = state.copyWith(
        status: CameraStatus.error,
        errorMessage: 'No camera was found on this device.',
      );
      return;
    }
    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
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
      debugPrint('Camera init failed: $e');
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
      await controller.dispose();
      state = state.copyWith(status: CameraStatus.idle);
      return;
    }

    _camera = controller;
    _rotation = description.sensorOrientation;
    state = state.copyWith(
      status: CameraStatus.ready,
      camera: controller,
      paused: false,
    );
    await _syncStream();
  }

  /// Stops the camera and releases it. Safe to call many times.
  Future<void> stop() async {
    _wantRunning = false;
    final cam = _camera;
    if (cam == null) return;
    _camera = null;
    _pipeline.stop();
    state = state.copyWith(
      status: CameraStatus.idle,
      clearCamera: true,
      paused: false,
    );
    // Let the UI drop the preview before the controller is disposed.
    await Future.any<void>([
      WidgetsBinding.instance.endOfFrame,
      Future<void>.delayed(const Duration(milliseconds: 100)),
    ]);
    try {
      if (cam.value.isStreamingImages) await cam.stopImageStream();
    } catch (_) {}
    try {
      await cam.dispose();
    } catch (_) {}
  }

  Future<void> retry() async {
    await stop();
    await start();
  }

  // ---- frame stream ------------------------------------------------------

  /// Runs for every camera frame. Only hands the grayscale plane to the
  /// pipeline; no copies and no state changes here.
  void _onFrame(CameraImage image) {
    final y = image.planes.first;
    _pipeline.submit(
      width: image.width,
      height: image.height,
      rotationDegrees: _rotation,
      yPlane: y.bytes,
      yRowStride: y.bytesPerRow,
    );
  }

  /// Starts or stops the image stream to match the current state.
  /// Concurrent calls are merged so start/stop never overlap.
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
    if (cam == null || !cam.value.isInitialized) return;
    final want = state.streaming;
    try {
      if (want && !cam.value.isStreamingImages) {
        await cam.startImageStream(_onFrame);
        _pipeline.start();
      } else if (!want && cam.value.isStreamingImages) {
        await cam.stopImageStream();
        _pipeline.stop();
      }
    } catch (e) {
      debugPrint('Image stream change failed: $e');
    }
  }

  // ---- permission --------------------------------------------------------

  Future<void> requestPermission() async {
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
    await openAppSettings();
  }

  // ---- controls ----------------------------------------------------------

  Future<void> toggleFlash() async {
    final next = !state.flashOn;
    state = state.copyWith(flashOn: next);
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.setFlashMode(next ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      state = state.copyWith(
        flashOn: !next,
        notice: 'Flash is not available on this camera',
      );
    }
  }

  Future<void> togglePause() async {
    if (_camera == null) return;
    state = state.copyWith(paused: !state.paused);
    await _syncStream();
  }

  /// [point] is normalized: (0,0) top-left to (1,1) bottom-right.
  Future<void> focusAt(Offset point) async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.setFocusPoint(point);
    } catch (_) {}
    try {
      await cam.setExposurePoint(point);
    } catch (_) {}
  }
}

final scannerControllerProvider =
    NotifierProvider<ScannerController, ScannerUiState>(ScannerController.new);
