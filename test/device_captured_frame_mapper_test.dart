import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/camera/captured_frame_mapper.dart';
import 'package:exalted/features/devices/core/device_frame.dart';
import 'package:exalted/features/scanner/captured_frame.dart';

void main() {
  final stamp = DateTime.utc(2026, 11, 5, 12);

  test('a padded BGRA frame keeps size, stride, rotation and bytes', () {
    final bytes = Uint8List(20 * 2)..[3] = 200;
    final captured = CapturedFrame(
      bytes: bytes,
      width: 4,
      height: 2,
      stride: 20,
      isBgra: true,
      rotationDegrees: 90,
    );
    final frame = deviceFrameFromCaptured(
      captured,
      timestamp: stamp,
      sequence: 5,
    );
    final plane = frame.planes.single;
    expect(frame.format, DevicePixelFormat.bgra8888);
    expect(frame.width, 4);
    expect(frame.height, 2);
    expect(plane.rowStride, 20);
    expect(plane.pixelStride, 4);
    expect(frame.rotationDegrees, 90);
    expect(frame.timestamp, stamp);
    expect(frame.sequence, 5);
    expect(plane.bytes[3], 200);
  });

  test('a luma frame keeps its row padding', () {
    final captured = CapturedFrame(
      bytes: Uint8List(8 * 3),
      width: 6,
      height: 3,
      stride: 8,
      isBgra: false,
      rotationDegrees: 270,
    );
    final frame = deviceFrameFromCaptured(captured, timestamp: stamp);
    final plane = frame.planes.single;
    expect(frame.format, DevicePixelFormat.luma8);
    expect(plane.rowStride, 8);
    expect(plane.pixelStride, 1);
    expect(plane.isTightlyPacked, isFalse);
    expect(frame.rotationDegrees, 270);
  });

  test('rotation 0 and 180 pass through', () {
    for (final r in [0, 180]) {
      final captured = CapturedFrame(
        bytes: Uint8List(16),
        width: 4,
        height: 4,
        stride: 4,
        isBgra: false,
        rotationDegrees: r,
      );
      expect(
        deviceFrameFromCaptured(captured, timestamp: stamp).rotationDegrees,
        r,
      );
    }
  });

  test('a buffer too short for its stride is rejected, not truncated', () {
    final captured = CapturedFrame(
      bytes: Uint8List(10),
      width: 4,
      height: 4,
      stride: 4,
      isBgra: false,
      rotationDegrees: 0,
    );
    expect(
      () => deviceFrameFromCaptured(captured, timestamp: stamp),
      throwsArgumentError,
    );
  });
}
