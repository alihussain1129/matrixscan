import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/config/app_config.dart';

void main() {
  test('camera defaults match the app (balanced, preview on)', () {
    const c = CameraConfig();
    expect(c.quality, 'balanced');
    expect(c.showPreview, isTrue);
    expect(const AppConfig().validate(), isEmpty);
  });

  test('unknown quality is rejected', () {
    final i = const AppConfig(camera: CameraConfig(quality: 'extreme'))
        .validate();
    expect(i.any((x) => x.path == 'camera.quality'), isTrue);
  });

  test('quality names match CameraQuality names', () {
    expect(CameraConfig.qualities, ['balanced', 'high', 'ultra']);
  });

  test('json round trip keeps camera settings', () {
    const c = AppConfig(
      camera: CameraConfig(quality: 'ultra', deviceId: 'cam1'),
    );
    final issues = <ConfigIssue>[];
    final back = AppConfig.fromJson(c.toJson(), issues);
    expect(issues, isEmpty);
    expect(back.camera.quality, 'ultra');
    expect(back.camera.deviceId, 'cam1');
  });
}
