import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/core/config/config_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('cfgc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer make({ConfigStore? store, AppConfig? initial}) {
    final c = ProviderContainer(
      overrides: [
        if (store != null) configStoreProvider.overrideWithValue(store),
        if (initial != null) configProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts from the loaded config', () {
    final c = make(
      initial: const AppConfig(scanner: ScannerConfig(host: '1.2.3.4')),
    );
    expect(c.read(configControllerProvider).scanner.host, '1.2.3.4');
  });

  test('a valid patch applies and is saved', () async {
    final c = make(store: ConfigStore(tmp));
    final r = await c.read(configControllerProvider.notifier).patch({
      'scanner': {'host': '10.0.0.5', 'port': 9100},
    });
    expect(r.saved, isTrue);
    expect(c.read(configControllerProvider).scanner.host, '10.0.0.5');
    final back = (await ConfigStore(tmp).load()).config;
    expect(back.scanner.host, '10.0.0.5');
    expect(back.scanner.port, 9100);
  });

  test('an out-of-range patch is rejected and changes nothing', () async {
    final c = make(store: ConfigStore(tmp));
    final r = await c.read(configControllerProvider.notifier).patch({
      'scanner': {'port': 70000},
    });
    expect(r.applied, isFalse);
    expect(r.issues.any((i) => i.path == 'scanner.port'), isTrue);
    expect(c.read(configControllerProvider).scanner.port, 9004);
    expect(tmp.listSync(), isEmpty);
  });

  test('a wrong-typed value is rejected', () async {
    final c = make();
    final r = await c.read(configControllerProvider.notifier).patch({
      'scanner': {'port': 'x'},
    });
    expect(r.applied, isFalse);
    expect(c.read(configControllerProvider).scanner.port, 9004);
  });

  test('an unknown section is rejected', () async {
    final c = make();
    final r = await c.read(configControllerProvider.notifier).patch({
      'nope': {'a': 1},
    });
    expect(r.applied, isFalse);
    expect(r.issues.single.path, 'nope');
  });

  test('without a store the change applies in memory only', () async {
    final c = make();
    final r = await c.read(configControllerProvider.notifier).patch({
      'camera': {'quality': 'high'},
    });
    expect(r.saved, isTrue);
    expect(c.read(configControllerProvider).camera.quality, 'high');
  });

  test('a file from a newer version is never overwritten', () async {
    final store = ConfigStore(tmp);
    store.file.writeAsStringSync('{"version": 99}');
    await store.load();
    final c = make(store: store);
    final r = await c.read(configControllerProvider.notifier).patch({
      'scanner': {'host': '9.9.9.9'},
    });
    expect(r.applied, isTrue);
    expect(r.saved, isFalse);
    expect(r.saveError, contains('newer'));
    expect(c.read(configControllerProvider).scanner.host, '9.9.9.9');
    expect(store.file.readAsStringSync(), '{"version": 99}');
  });

  test('quick consecutive patches both land and are saved in order', () async {
    final c = make(store: ConfigStore(tmp));
    final n = c.read(configControllerProvider.notifier);
    final a = n.patch({
      'scanner': {'host': '10.0.0.7'},
    });
    final b = n.patch({
      'scanner': {'port': 9200},
    });
    await Future.wait([a, b]);
    final s = c.read(configControllerProvider).scanner;
    expect(s.host, '10.0.0.7');
    expect(s.port, 9200);
    final back = (await ConfigStore(tmp).load()).config.scanner;
    expect(back.host, '10.0.0.7');
    expect(back.port, 9200);
  });
}
