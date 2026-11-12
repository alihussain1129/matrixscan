import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/camera/controller_camera_port.dart';
import 'package:exalted/features/devices/core/device_models.dart';
import 'package:exalted/features/devices/device_hub_provider.dart';
import 'package:exalted/features/scanner/frame_pipeline.dart';

class _Probe extends FrameAnalyzer {
  @override
  String get name => 'controller_port_test_probe';

  @override
  Future<void> analyze(AnalysisFrame frame) async {}
}

void main() {
  test(
    'the port reports the camera as not ready when the scanner is idle',
    () async {
      final container = ProviderContainer(
        overrides: [scannerCameraPortOverride],
      );
      addTearDown(container.dispose);
      final port = container.read(scannerCameraPortProvider)!;
      expect(port.isCameraReady, isFalse);
      expect(
        await port.grabFrame(timeout: const Duration(milliseconds: 50)),
        isNull,
      );
    },
  );

  test('analyzer add and remove reach the shared frame pipeline', () {
    final container = ProviderContainer(overrides: [scannerCameraPortOverride]);
    addTearDown(container.dispose);
    final port = container.read(scannerCameraPortProvider)!;
    final probe = _Probe();
    expect(port.addAnalyzer(probe), isTrue);
    expect(port.addAnalyzer(probe), isFalse);
    expect(port.removeAnalyzer(probe), isTrue);
  });

  test('the hub serves a camera device once the port is overridden', () {
    final container = ProviderContainer(overrides: [scannerCameraPortOverride]);
    addTearDown(container.dispose);
    final hub = container.read(deviceHubProvider);
    final camera = hub.register(
      DeviceIdentity.create(
        manufacturer: 'Exalted',
        model: 'Scanner camera',
        interfaceType: DeviceInterfaceType.builtIn,
        transport: DeviceTransport.platformCamera,
        systemId: 'scanner',
      ),
    );
    expect(camera.backendId, 'scanner-camera');
    expect(camera.has(DeviceCapability.continuousFrames), isTrue);
    expect(camera.has(DeviceCapability.decodedReads), isFalse);
  });
}
