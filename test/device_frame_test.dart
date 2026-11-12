import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/core/device_backend_factory.dart';
import 'package:exalted/features/devices/core/device_frame.dart';
import 'package:exalted/features/devices/core/device_hub.dart';

import 'support/fake_device_adapter.dart';

void main() {
  final stamp = DateTime.utc(2026, 11, 5, 12);

  group('DeviceImagePlane', () {
    test('rejects a buffer shorter than its layout', () {
      expect(
        () => DeviceImagePlane(
          bytes: Uint8List(10),
          width: 4,
          height: 4,
          rowStride: 4,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a stride smaller than the row', () {
      expect(
        () => DeviceImagePlane(
          bytes: Uint8List(100),
          width: 4,
          height: 2,
          rowStride: 12,
          pixelStride: 4,
        ),
        throwsArgumentError,
      );
    });

    test('allows a short last row (no trailing padding)', () {
      final plane = DeviceImagePlane(
        bytes: Uint8List(8 * 1 + 4),
        width: 4,
        height: 2,
        rowStride: 8,
      );
      expect(plane.isTightlyPacked, isFalse);
    });
  });

  group('DeviceFrame metadata', () {
    DeviceFrame padded({void Function()? onRelease}) => DeviceFrame.single(
      width: 4,
      height: 2,
      format: DevicePixelFormat.bgra8888,
      bytes: Uint8List(20 * 2),
      rowStride: 20,
      rotationDegrees: 90,
      mirrored: true,
      timestamp: stamp,
      sequence: 7,
      onRelease: onRelease,
    );

    test('keeps size, format, stride, rotation, timestamp and sequence', () {
      final frame = padded();
      final plane = frame.planes.single;
      expect(frame.width, 4);
      expect(frame.height, 2);
      expect(frame.format, DevicePixelFormat.bgra8888);
      expect(plane.rowStride, 20);
      expect(plane.pixelStride, 4);
      expect(frame.rotationDegrees, 90);
      expect(frame.mirrored, isTrue);
      expect(frame.timestamp, stamp);
      expect(frame.sequence, 7);
    });

    test('rotation is normalized and must be a multiple of 90', () {
      DeviceFrame make(int r) => DeviceFrame.single(
        width: 1,
        height: 1,
        format: DevicePixelFormat.luma8,
        bytes: Uint8List(1),
        timestamp: stamp,
        rotationDegrees: r,
      );
      expect(make(-90).rotationDegrees, 270);
      expect(make(450).rotationDegrees, 90);
      expect(() => make(45), throwsArgumentError);
    });

    test('multi-plane frames keep each plane layout', () {
      final frame = DeviceFrame(
        width: 4,
        height: 4,
        format: DevicePixelFormat.nv21,
        planes: [
          DeviceImagePlane(
            bytes: Uint8List(8 * 4),
            width: 4,
            height: 4,
            rowStride: 8,
          ),
          DeviceImagePlane(
            bytes: Uint8List(8 * 2),
            width: 2,
            height: 2,
            rowStride: 8,
            pixelStride: 2,
          ),
        ],
        timestamp: stamp,
      );
      expect(frame.planes, hasLength(2));
      expect(frame.planes[0].rowStride, 8);
      expect(frame.planes[1].pixelStride, 2);
      expect(frame.planes[1].height, 2);
    });

    test('copy is independent and keeps all metadata', () {
      final bytes = Uint8List(20 * 2)..[0] = 9;
      final frame = DeviceFrame.single(
        width: 4,
        height: 2,
        format: DevicePixelFormat.bgra8888,
        bytes: bytes,
        rowStride: 20,
        rotationDegrees: 180,
        timestamp: stamp,
        sequence: 3,
      );
      final copy = frame.copy();
      bytes[0] = 1;
      expect(copy.planes.single.bytes[0], 9);
      expect(copy.planes.single.rowStride, 20);
      expect(copy.rotationDegrees, 180);
      expect(copy.sequence, 3);
      expect(copy.timestamp, stamp);
      expect(copy.format, DevicePixelFormat.bgra8888);
    });

    test('release runs the callback once and blocks later access', () {
      var released = 0;
      final frame = padded(onRelease: () => released++);
      frame.release();
      frame.release();
      expect(released, 1);
      expect(frame.isReleased, isTrue);
      expect(() => frame.planes, throwsStateError);
    });
  });

  test('the hub hands a captured frame over with its layout intact', () async {
    final original = DeviceFrame.single(
      width: 4,
      height: 2,
      format: DevicePixelFormat.bgra8888,
      bytes: Uint8List(20 * 2),
      rowStride: 20,
      rotationDegrees: 90,
      timestamp: stamp,
      sequence: 7,
    );
    final camera = testCamera();
    final hub = DeviceHub(
      backends: DeviceBackendFactory()
        ..register(
          fakeRegistration(
            make: (i, c) => FakeAdapter()..frameToReturn = original,
          ),
        ),
    );
    addTearDown(hub.dispose);
    hub.register(camera);
    await hub.connect(camera.id);
    final frame = await hub.captureFrame(camera.id);
    expect(identical(frame, original), isTrue);
    expect(frame.planes.single.rowStride, 20);
    expect(frame.rotationDegrees, 90);
    expect(frame.sequence, 7);
  });
}
