import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/camera/scanner_camera_adapter.dart';
import 'package:exalted/features/devices/core/device_models.dart';
import 'package:exalted/features/devices/core/device_state_machine.dart';
import 'package:exalted/features/devices/device_hub_provider.dart';
import 'package:exalted/features/devices/keyence/keyence_barcode_reader_adapter.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';
import 'package:exalted/features/scanner/captured_frame.dart';
import 'package:exalted/features/scanner/frame_pipeline.dart';

class _Port implements ScannerCameraPort {
  @override
  bool get isCameraReady => true;
  @override
  Future<CapturedFrame?> grabFrame({
    Duration timeout = const Duration(seconds: 2),
  }) async => null;
  @override
  bool addAnalyzer(FrameAnalyzer analyzer) => true;
  @override
  bool removeAnalyzer(FrameAnalyzer analyzer) => true;
}

DeviceIdentity _camera() => DeviceIdentity.create(
  manufacturer: 'Test',
  model: 'Cam',
  interfaceType: DeviceInterfaceType.builtIn,
  transport: DeviceTransport.platformCamera,
  systemId: 'cam0',
);

void main() {
  test('reader is served; a camera is unsupported until a port is wired', () {
    final container = ProviderContainer(
      overrides: [
        keyenceSr751ClientProvider.overrideWithValue(KeyenceSr751Client()),
      ],
    );
    addTearDown(container.dispose);
    final hub = container.read(deviceHubProvider);

    final reader = hub.register(
      keyenceSr751Identity(host: '192.0.2.10', port: 1234),
    );
    expect(reader.backendId, 'keyence-sr751');
    expect(reader.state, DeviceState.ready);
    expect(reader.has(DeviceCapability.decodedReads), isTrue);
    expect(reader.has(DeviceCapability.continuousFrames), isFalse);
    expect(reader.has(DeviceCapability.singleFrame), isFalse);

    expect(hub.register(_camera()).state, DeviceState.unsupported);
  });

  test('reader and camera stay separate when a camera port is provided', () {
    final container = ProviderContainer(
      overrides: [
        keyenceSr751ClientProvider.overrideWithValue(KeyenceSr751Client()),
        scannerCameraPortProvider.overrideWithValue(_Port()),
      ],
    );
    addTearDown(container.dispose);
    final hub = container.read(deviceHubProvider);

    final camera = hub.register(_camera());
    expect(camera.backendId, 'scanner-camera');
    expect(camera.has(DeviceCapability.continuousFrames), isTrue);
    expect(camera.has(DeviceCapability.decodedReads), isFalse);

    final reader = hub.register(
      keyenceSr751Identity(host: '192.0.2.10', port: 1234),
    );
    expect(reader.backendId, 'keyence-sr751');
  });
}
