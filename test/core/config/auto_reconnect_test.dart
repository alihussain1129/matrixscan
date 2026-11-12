import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/legacy_settings.dart';

void main() {
  test('auto-reconnect defaults to true like the coordinator', () {
    expect(const ScannerConfig().autoReconnect, isTrue);
  });

  test('saved auto-reconnect is carried over', () async {
    SharedPreferences.setMockInitialValues({
      'exalted_keyence_auto_reconnect': false,
    });
    final l = await readLegacySettings();
    expect(l.scannerJson(), {'autoReconnect': false});
  });

  test('json round trip keeps auto-reconnect', () {
    const c = AppConfig(scanner: ScannerConfig(autoReconnect: false));
    final issues = <ConfigIssue>[];
    final back = AppConfig.fromJson(c.toJson(), issues);
    expect(issues, isEmpty);
    expect(back.scanner.autoReconnect, isFalse);
  });
}
