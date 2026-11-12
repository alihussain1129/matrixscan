import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/legacy_settings.dart';

void main() {
  test('auto-connect defaults to true like the existing coordinator', () {
    expect(const ScannerConfig().autoConnect, isTrue);
  });

  test('fresh install reads as empty', () async {
    SharedPreferences.setMockInitialValues({});
    final l = await readLegacySettings();
    expect(l.isEmpty, isTrue);
    expect(l.scannerJson(), isEmpty);
  });

  test('saved KEYENCE values are carried over', () async {
    SharedPreferences.setMockInitialValues({
      'exalted_keyence_last_host': '10.0.0.5',
      'exalted_keyence_last_port': 9100,
      'exalted_keyence_last_model': 'SR-1000',
      'exalted_keyence_auto_connect': false,
      'exalted_camera_quality': 'high',
    });
    final l = await readLegacySettings();
    expect(l.isEmpty, isFalse);
    expect(l.cameraQuality, 'high');
    expect(l.scannerJson(), {
      'host': '10.0.0.5',
      'port': 9100,
      'deviceLabel': 'SR-1000',
      'autoConnect': false,
    });
  });

  test('values of the wrong type are ignored, not thrown', () async {
    SharedPreferences.setMockInitialValues({
      'exalted_keyence_last_host': 5,
      'exalted_keyence_last_port': 'x',
    });
    final l = await readLegacySettings();
    expect(l.host, isNull);
    expect(l.port, isNull);
  });

  test('reading never changes the old store', () async {
    SharedPreferences.setMockInitialValues({
      'exalted_keyence_last_host': '10.0.0.5',
    });
    final p = await SharedPreferences.getInstance();
    final before = {for (final k in p.getKeys()) k: p.get(k)};
    await readLegacySettings(p);
    final after = {for (final k in p.getKeys()) k: p.get(k)};
    expect(after, before);
  });
}
