import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/config/app_config.dart';

void main() {
  test('defaults: auto-restart off, 3 restarts per hour', () {
    final c = AppConfig.defaults();
    expect(c.startup.autoRestart, isFalse);
    expect(c.startup.maxRestartsPerHour, 3);
    expect(c.validate(), isEmpty);
  });

  test('reads and writes the startup section', () {
    final issues = <ConfigIssue>[];
    final c = AppConfig.fromJson({
      'startup': {'autoRestart': true, 'maxRestartsPerHour': 5},
    }, issues);
    expect(c.startup.autoRestart, isTrue);
    expect(c.startup.maxRestartsPerHour, 5);
    expect(c.toJson()['startup'], {
      'autoRestart': true,
      'maxRestartsPerHour': 5,
    });
  });

  test('a config file without the section gets the defaults', () {
    final c = AppConfig.fromJson({}, <ConfigIssue>[]);
    expect(c.startup.autoRestart, isFalse);
    expect(c.startup.maxRestartsPerHour, 3);
  });

  test('rejects restart limits outside 1 to 20', () {
    for (final bad in [0, 21, 99]) {
      final c = AppConfig(startup: StartupConfig(maxRestartsPerHour: bad));
      expect(
        c.validate().any((i) => '$i'.contains('maxRestartsPerHour')),
        isTrue,
        reason: '$bad',
      );
    }
  });
}
