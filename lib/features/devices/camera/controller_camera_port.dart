import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../scanner/captured_frame.dart';
import '../../scanner/frame_pipeline.dart';
import '../../scanner/scanner_controller.dart';
import '../device_hub_provider.dart';
import 'scanner_camera_adapter.dart';

/// Connects the device hub's camera backend to the scanner's existing camera.
/// It only delegates: the scanner keeps ownership and this never opens,
/// starts or stops the camera.
///
/// Limits: [grabFrame] ends at its timeout (null) on platforms where the
/// camera plugin gives no frame stream, and frames only reach the analyzer
/// tap while the scanner is streaming (auto-scan on, not paused).
class ControllerScannerCameraPort implements ScannerCameraPort {
  ControllerScannerCameraPort(this._ref);

  final Ref _ref;

  @override
  bool get isCameraReady =>
      _ref.read(scannerControllerProvider).status == CameraStatus.ready;

  @override
  Future<CapturedFrame?> grabFrame({
    Duration timeout = const Duration(seconds: 2),
  }) =>
      _ref.read(scannerControllerProvider.notifier).grabFrame(timeout: timeout);

  @override
  bool addAnalyzer(FrameAnalyzer analyzer) =>
      _ref.read(framePipelineProvider).addAnalyzer(analyzer);

  @override
  bool removeAnalyzer(FrameAnalyzer analyzer) =>
      _ref.read(framePipelineProvider).removeAnalyzer(analyzer);
}

/// Pass to the app's ProviderScope to enable the hub's camera backend:
/// `ProviderScope(overrides: [scannerCameraPortOverride], ...)`.
final scannerCameraPortOverride = scannerCameraPortProvider.overrideWith(
  (ref) => ControllerScannerCameraPort(ref),
);
