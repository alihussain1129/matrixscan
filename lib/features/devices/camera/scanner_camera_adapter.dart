import 'dart:async';
import 'dart:typed_data';

import '../../scanner/captured_frame.dart';
import '../../scanner/frame_pipeline.dart';
import '../core/device_adapter.dart';
import '../core/device_backend_factory.dart';
import '../core/device_exception.dart';
import '../core/device_models.dart';
import 'captured_frame_mapper.dart';

/// What the adapter needs from the scanner. The scanner keeps ownership of
/// the camera; this port never starts, stops or opens it.
///
/// Wire it later with: `isCameraReady` from the scanner state,
/// `grabFrame` from `ScannerController.grabFrame`, and the analyzer methods
/// from `FramePipeline.addAnalyzer` / `removeAnalyzer`.
abstract interface class ScannerCameraPort {
  bool get isCameraReady;
  Future<CapturedFrame?> grabFrame({Duration timeout});
  bool addAnalyzer(FrameAnalyzer analyzer);
  bool removeAnalyzer(FrameAnalyzer analyzer);
}

const Set<DeviceCapability> kScannerCameraCapabilities = {
  DeviceCapability.continuousFrames,
  DeviceCapability.singleFrame,
  DeviceCapability.diagnostics,
};

/// Exposes the scanner's existing camera through the DeviceHub contracts.
///
/// Limits, stated plainly:
/// * Continuous frames are luma only (what the pipeline provides), at the
///   pipeline's throttled rate.
/// * It cannot detect that the scanner lost its camera, so [linkEvents]
///   never fires.
/// * Cancelling a single capture cannot abort the scanner's pending grab; it
///   ends at the grab timeout.
class ScannerCameraAdapter
    implements DeviceAdapter, FrameSource, SingleFrameCapture {
  ScannerCameraAdapter(
    this._port, {
    this.grabTimeout = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const String analyzerName = 'device_hub_tap';

  final ScannerCameraPort _port;
  final Duration grabTimeout;
  final DateTime Function() _clock;

  final StreamController<DeviceFrame> _frames =
      StreamController<DeviceFrame>.broadcast();
  final StreamController<DeviceLinkEvent> _links =
      StreamController<DeviceLinkEvent>.broadcast();
  late final _TapAnalyzer _tap = _TapAnalyzer(this);
  bool _tapped = false;
  bool _disposed = false;
  int _sequence = 0;
  int framesDelivered = 0;

  @override
  String get backendId => 'scanner-camera';

  @override
  Set<DeviceCapability> get capabilities => kScannerCameraCapabilities;

  @override
  bool get supportsCancellation => true;

  @override
  bool get reconnectsAutomatically => false;

  @override
  Stream<DeviceLinkEvent> get linkEvents => _links.stream;

  @override
  Stream<DeviceFrame> get frames => _frames.stream;

  @override
  Future<void> connect(CancelToken cancel) async {
    _ensureOpen();
    if (cancel.isCancelled) {
      throw const DeviceException(
        DeviceFailureKind.cancelled,
        'Operation cancelled',
      );
    }
    if (!_port.isCameraReady) {
      throw const DeviceException(
        DeviceFailureKind.connectionFailed,
        'The scanner has not started its camera',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _untap();
  }

  @override
  Future<void> startAcquisition(CancelToken cancel) async {
    _ensureOpen();
    if (cancel.isCancelled) {
      throw const DeviceException(
        DeviceFailureKind.cancelled,
        'Operation cancelled',
      );
    }
    if (!_port.isCameraReady) {
      throw const DeviceException(
        DeviceFailureKind.connectionFailed,
        'The scanner has not started its camera',
      );
    }
    if (!_tapped) {
      _port.addAnalyzer(_tap);
      _tapped = true;
    }
  }

  @override
  Future<void> stopAcquisition() async {
    _untap();
  }

  @override
  Future<DeviceFrame> captureFrame(CancelToken cancel) async {
    _ensureOpen();
    if (cancel.isCancelled || !_port.isCameraReady) {
      throw DeviceException(
        cancel.isCancelled
            ? DeviceFailureKind.cancelled
            : DeviceFailureKind.connectionFailed,
        cancel.isCancelled
            ? 'Operation cancelled'
            : 'The scanner has not started its camera',
      );
    }
    final captured = await _port.grabFrame(timeout: grabTimeout);
    if (captured == null) {
      throw const DeviceException(
        DeviceFailureKind.timeout,
        'No camera frame arrived in time',
      );
    }
    if (cancel.isCancelled) {
      throw const DeviceException(
        DeviceFailureKind.cancelled,
        'Operation cancelled',
      );
    }
    return deviceFrameFromCaptured(
      captured,
      timestamp: _clock(),
      sequence: ++_sequence,
    );
  }

  @override
  Future<Map<String, Object?>> diagnostics() async => {
    'backend': backendId,
    'cameraReady': _port.isCameraReady,
    'tapped': _tapped,
    'framesDelivered': framesDelivered,
    'frameContent': 'luma only',
  };

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _untap();
    _disposed = true;
    await _frames.close();
    await _links.close();
  }

  void _untap() {
    if (!_tapped) return;
    _tapped = false;
    _port.removeAnalyzer(_tap);
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const DeviceException(
        DeviceFailureKind.disposed,
        'Scanner camera adapter is disposed',
      );
    }
  }

  void _onAnalysisFrame(AnalysisFrame frame) {
    if (_disposed || !_tapped || !_frames.hasListener) return;
    // The plane is shared with the camera plugin, so copy it.
    final device = deviceFrameFromAnalysis(
      frame,
      timestamp: _clock(),
      sequence: ++_sequence,
    );
    framesDelivered++;
    _frames.add(device);
  }
}

class _TapAnalyzer extends FrameAnalyzer {
  _TapAnalyzer(this._owner);

  final ScannerCameraAdapter _owner;

  @override
  String get name => ScannerCameraAdapter.analyzerName;

  @override
  Future<void> analyze(AnalysisFrame frame) async {
    _owner._onAnalysisFrame(frame);
  }
}

/// Luma plane of an [AnalysisFrame] as an independent [DeviceFrame].
DeviceFrame deviceFrameFromAnalysis(
  AnalysisFrame frame, {
  required DateTime timestamp,
  int sequence = 0,
}) {
  return DeviceFrame.single(
    width: frame.width,
    height: frame.height,
    format: DevicePixelFormat.luma8,
    bytes: Uint8List.fromList(frame.yPlane),
    rowStride: frame.yRowStride,
    pixelStride: 1,
    rotationDegrees: frame.rotationDegrees,
    timestamp: timestamp,
    sequence: sequence,
  );
}

/// Backend registration for the scanner's camera. Only devices with the
/// platform-camera transport are served.
BackendRegistration scannerCameraRegistration(ScannerCameraPort port) {
  return BackendRegistration(
    backendId: 'scanner-camera',
    capabilities: kScannerCameraCapabilities,
    supports: (identity) =>
        identity.transport == DeviceTransport.platformCamera,
    create: (identity, configuration) => ScannerCameraAdapter(port),
  );
}
