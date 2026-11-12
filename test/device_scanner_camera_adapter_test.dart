import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/camera/scanner_camera_adapter.dart';
import 'package:exalted/features/devices/core/device_backend_factory.dart';
import 'package:exalted/features/devices/core/device_exception.dart';
import 'package:exalted/features/devices/core/device_hub.dart';
import 'package:exalted/features/devices/core/device_models.dart';
import 'package:exalted/features/devices/core/device_state_machine.dart';
import 'package:exalted/features/scanner/captured_frame.dart';
import 'package:exalted/features/scanner/frame_pipeline.dart';

import 'support/fake_device_adapter.dart';

class FakePort implements ScannerCameraPort {
  bool ready = true;
  CapturedFrame? next;
  final List<FrameAnalyzer> analyzers = [];

  @override
  bool get isCameraReady => ready;

  @override
  Future<CapturedFrame?> grabFrame({
    Duration timeout = const Duration(seconds: 2),
  }) async => next;

  @override
  bool addAnalyzer(FrameAnalyzer analyzer) {
    if (analyzers.any((a) => a.name == analyzer.name)) return false;
    analyzers.add(analyzer);
    return true;
  }

  @override
  bool removeAnalyzer(FrameAnalyzer analyzer) => analyzers.remove(analyzer);
}

AnalysisFrame analysis(Uint8List plane) => AnalysisFrame(
  width: 4,
  height: 2,
  rotationDegrees: 90,
  yPlane: plane,
  yRowStride: 8,
);

void main() {
  late FakePort port;
  late ScannerCameraAdapter adapter;

  setUp(() {
    port = FakePort();
    adapter = ScannerCameraAdapter(port);
  });
  tearDown(() async => adapter.dispose());

  test('connect fails clearly when the scanner has no camera', () async {
    port.ready = false;
    await expectLater(
      adapter.connect(CancelToken()),
      failsWith(DeviceFailureKind.connectionFailed),
    );
    port.ready = true;
    await adapter.connect(CancelToken());
  });

  test('acquisition registers one tap and keeps stride and rotation', () async {
    await adapter.startAcquisition(CancelToken());
    await adapter.startAcquisition(CancelToken());
    expect(port.analyzers, hasLength(1));

    final plane = Uint8List(16)..[0] = 7;
    final got = <DeviceFrame>[];
    final sub = adapter.frames.listen(got.add);
    addTearDown(sub.cancel);
    await port.analyzers.single.analyze(analysis(plane));
    await Future<void>.delayed(Duration.zero);

    final frame = got.single;
    expect(frame.format, DevicePixelFormat.luma8);
    expect(frame.planes.single.rowStride, 8);
    expect(frame.rotationDegrees, 90);
    expect(frame.sequence, 1);
    plane[0] = 99;
    expect(frame.planes.single.bytes[0], 7, reason: 'frame must be a copy');
  });

  test('without a listener frames are dropped, not queued', () async {
    await adapter.startAcquisition(CancelToken());
    await port.analyzers.single.analyze(analysis(Uint8List(16)));
    expect(adapter.framesDelivered, 0);
  });

  test('stop removes the tap and later frames are ignored', () async {
    await adapter.startAcquisition(CancelToken());
    final tap = port.analyzers.single;
    await adapter.stopAcquisition();
    await adapter.stopAcquisition();
    expect(port.analyzers, isEmpty);
    final got = <DeviceFrame>[];
    final sub = adapter.frames.listen(got.add);
    addTearDown(sub.cancel);
    await tap.analyze(analysis(Uint8List(16)));
    await Future<void>.delayed(Duration.zero);
    expect(got, isEmpty);
  });

  test(
    'single capture maps the grabbed frame; null becomes a timeout',
    () async {
      port.next = CapturedFrame(
        bytes: Uint8List(8 * 3),
        width: 6,
        height: 3,
        stride: 8,
        isBgra: false,
        rotationDegrees: 270,
      );
      final frame = await adapter.captureFrame(CancelToken());
      expect(frame.planes.single.rowStride, 8);
      expect(frame.rotationDegrees, 270);

      port.next = null;
      await expectLater(
        adapter.captureFrame(CancelToken()),
        failsWith(DeviceFailureKind.timeout),
      );
    },
  );

  test(
    'dispose is idempotent, removes the tap and blocks further use',
    () async {
      await adapter.startAcquisition(CancelToken());
      await adapter.dispose();
      await adapter.dispose();
      expect(port.analyzers, isEmpty);
      await expectLater(
        adapter.connect(CancelToken()),
        failsWith(DeviceFailureKind.disposed),
      );
    },
  );

  test('works through the hub and never touches the camera itself', () async {
    final hub = DeviceHub(
      backends: DeviceBackendFactory()
        ..register(scannerCameraRegistration(port)),
      cancelGrace: const Duration(milliseconds: 50),
    );
    addTearDown(hub.dispose);
    final id = DeviceIdentity.create(
      manufacturer: 'Generic',
      model: 'Scanner camera',
      interfaceType: DeviceInterfaceType.builtIn,
      transport: DeviceTransport.platformCamera,
      systemId: 'scanner-camera',
    );
    expect(hub.register(id).state, DeviceState.ready);
    await hub.connect(id.id);
    await hub.startAcquisition(id.id);
    expect(hub.status(id.id).state, DeviceState.acquiring);

    final next = hub.frameStream(id.id).first;
    await port.analyzers.single.analyze(analysis(Uint8List(16)));
    final frame = await next;
    expect(frame.rotationDegrees, 90);

    await hub.disconnect(id.id);
    expect(port.analyzers, isEmpty);
    expect(hub.status(id.id).state, DeviceState.disconnected);
  });

  test('a hub connect fails when the scanner camera is not running', () async {
    port.ready = false;
    final hub = DeviceHub(
      backends: DeviceBackendFactory()
        ..register(scannerCameraRegistration(port)),
    );
    addTearDown(hub.dispose);
    final id = DeviceIdentity.create(
      manufacturer: 'Generic',
      model: 'Scanner camera',
      interfaceType: DeviceInterfaceType.builtIn,
      transport: DeviceTransport.platformCamera,
      systemId: 'scanner-camera',
    );
    hub.register(id);
    await expectLater(
      hub.connect(id.id),
      failsWith(DeviceFailureKind.connectionFailed),
    );
  });
}
