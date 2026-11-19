import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/scanner/scanner_controller.dart';

void main() {
  final cameras = <CameraDescription>[
    CameraDescription(
      name: 'front-camera',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
    CameraDescription(
      name: 'rear-camera',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    CameraDescription(
      name: 'usb-camera',
      lensDirection: CameraLensDirection.external,
      sensorOrientation: 0,
    ),
  ];

  test('uses the saved camera when it is available', () {
    expect(
      resolveCameraDescription(cameras, preferredCameraId: 'usb-camera')?.name,
      'usb-camera',
    );
  });

  test('falls back to the back-facing camera when saved device is missing', () {
    expect(
      resolveCameraDescription(cameras, preferredCameraId: 'missing')?.name,
      'rear-camera',
    );
  });

  test('falls back to first camera when no back-facing camera exists', () {
    final frontOnly = [cameras.first];
    expect(resolveCameraDescription(frontOnly)?.name, 'front-camera');
  });

  test('returns null when no camera is available', () {
    expect(resolveCameraDescription(const []), isNull);
  });
}
