import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/core/config/config_store.dart';
import 'package:exalted/core/config/legacy_settings.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('cfgp'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('provider defaults to AppConfig defaults', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(configProvider).toJson(), const AppConfig().toJson());
  });

  test('provider can be overridden', () {
    final c = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          const AppConfig(scanner: ScannerConfig(host: '1.2.3.4')),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(configProvider).scanner.host, '1.2.3.4');
  });

  test('first run builds from saved settings and writes nothing', () async {
    final r = await loadStartupConfig(
      dir: tmp,
      readLegacy: () async =>
          const LegacySettings(host: '10.0.0.5', port: 9100),
    );
    expect(r.config.scanner.host, '10.0.0.5');
    expect(r.config.scanner.port, 9100);
    expect(tmp.listSync(), isEmpty);
  });

  test('an existing config.json wins and legacy is not read', () async {
    await ConfigStore(tmp)
        .save(const AppConfig(scanner: ScannerConfig(host: '1.2.3.4')));
    final r = await loadStartupConfig(
      dir: tmp,
      readLegacy: () async => throw StateError('must not be called'),
    );
    expect(r.config.scanner.host, '1.2.3.4');
  });

  test('a failing legacy read falls back to defaults with a note', () async {
    final r = await loadStartupConfig(
      dir: tmp,
      readLegacy: () async => throw StateError('boom'),
    );
    expect(r.config.toJson(), const AppConfig().toJson());
    expect(r.notes.any((n) => n.contains('failed')), isTrue);
  });

  test('invalid migrated values fall back to defaults', () async {
    final r = await loadStartupConfig(
      dir: tmp,
      readLegacy: () async => const LegacySettings(port: 70000),
    );
    expect(r.config.toJson(), const AppConfig().toJson());
    expect(r.notes.any((n) => n.contains('invalid migrated')), isTrue);
  });
}
