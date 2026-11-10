import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_store.dart';

void main() {
  late Directory tmp;
  late ConfigStore store;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('exalted_cfg_');
    store = ConfigStore(tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'defaults are valid',
    () => expect(AppConfig.defaults().validate(), isEmpty),
  );

  test('missing file -> defaults', () async {
    final r = await store.load();
    expect(r.config.scanner.port, 9004);
    expect(r.notes.join(), contains('no config file'));
  });

  test('persistence and reload', () async {
    final c = AppConfig(
      scanner: const ScannerConfig(
        host: '10.0.0.5',
        port: 9100,
        autoConnect: true,
      ),
    );
    await store.save(c);
    final r = await ConfigStore(tmp).load();
    expect(r.config.scanner.host, '10.0.0.5');
    expect(r.config.scanner.port, 9100);
    expect(r.config.scanner.autoConnect, isTrue);
  });

  test('invalid scanner endpoint rejected on save', () async {
    expect(
      () => store.save(
        const AppConfig(scanner: ScannerConfig(host: '999.1.1.1', port: 70000)),
      ),
      throwsA(isA<ConfigInvalid>()),
    );
    expect(store.file.existsSync(), isFalse);
  });

  test('empty host and hostname rejected for tcp', () {
    expect(
      const AppConfig(scanner: ScannerConfig(host: '')).validate(),
      isNotEmpty,
    );
  });

  test('wrong types fall back to defaults with a note', () async {
    store.file.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'scanner': {'port': 'abc'},
      }),
    );
    final r = await store.load();
    expect(r.config.scanner.port, 9004);
    expect(r.notes.join(), contains('wrong type'));
  });

  test('migration from unversioned file', () async {
    store.file.writeAsStringSync(
      jsonEncode({
        'scanner': {'host': '10.1.1.1'},
      }),
    );
    final r = await store.load();
    expect(r.config.scanner.host, '10.1.1.1');
    expect(r.notes.join(), contains('migrated'));
  });

  test('corrupt file preserved, recovered from backup', () async {
    await store.save(const AppConfig(scanner: ScannerConfig(host: '10.2.2.2')));
    await store.save(
      const AppConfig(scanner: ScannerConfig(host: '10.3.3.3')),
    ); // creates .bak of first
    store.file.writeAsStringSync('{ not json');
    final r = await store.load();
    expect(r.config.scanner.host, '10.2.2.2');
    expect(tmp.listSync().any((f) => f.path.contains('.corrupt-')), isTrue);
  });

  test('corrupt file and no backup -> defaults, file preserved', () async {
    store.file.writeAsStringSync('garbage');
    final r = await store.load();
    expect(r.config.scanner.port, 9004);
    expect(tmp.listSync().any((f) => f.path.contains('.corrupt-')), isTrue);
  });

  test('newer version is never overwritten', () async {
    store.file.writeAsStringSync(
      jsonEncode({
        'version': 99,
        'scanner': {'host': '1.2.3.4'},
      }),
    );
    final r = await store.load();
    expect(r.readOnly, isTrue);
    expect(() => store.save(AppConfig.defaults()), throwsStateError);
    expect(jsonDecode(store.file.readAsStringSync())['version'], 99);
  });

  test('reset to defaults keeps previous file as backup', () async {
    await store.save(const AppConfig(scanner: ScannerConfig(host: '10.9.9.9')));
    await store.resetToDefaults();
    expect(
      jsonDecode(store.backup.readAsStringSync())['scanner']['host'],
      '10.9.9.9',
    );
  });

  test('redact hides secrets', () {
    final out = redact({
      'ftpPassword': 'x',
      'host': 'h',
      'n': {'apiToken': 't'},
    }) as Map;
    expect(out['ftpPassword'], '***');
    expect(out['host'], 'h');
    expect((out['n'] as Map)['apiToken'], '***');
  });
}
