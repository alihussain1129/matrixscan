import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/legacy_settings.dart';
import 'package:exalted/core/config/migrate.dart';
import 'package:exalted/core/config/storage_resolver.dart';

void main() {
  test('fresh install migrates to plain defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final c = migrateFromLegacy(await readLegacySettings());
    expect(c.toJson(), const AppConfig().toJson());
    expect(c.validate(), isEmpty);
  });

  test('saved values land in the right sections', () async {
    SharedPreferences.setMockInitialValues({
      'exalted_keyence_last_host': '10.0.0.5',
      'exalted_keyence_last_port': 9100,
      'exalted_keyence_auto_connect': false,
      'exalted_keyence_auto_reconnect': false,
      'exalted_camera_quality': 'ultra',
      'exalted_ocr_with_decode': false,
      'exalted_keep_images': true,
    });
    final c = migrateFromLegacy(await readLegacySettings());
    expect(c.scanner.host, '10.0.0.5');
    expect(c.scanner.port, 9100);
    expect(c.scanner.autoConnect, isFalse);
    expect(c.scanner.autoReconnect, isFalse);
    expect(c.camera.quality, 'ultra');
    expect(c.decoder.ocrWithDecode, isFalse);
    expect(c.storage.keepImages, isTrue);
    expect(c.validate(), isEmpty);
  });

  test('migration leaves the old store untouched', () async {
    SharedPreferences.setMockInitialValues({'exalted_keyence_last_host': 'h'});
    final p = await SharedPreferences.getInstance();
    final before = {for (final k in p.getKeys()) k: p.get(k)};
    migrateFromLegacy(await readLegacySettings(p));
    expect({for (final k in p.getKeys()) k: p.get(k)}, before);
  });

  test('resolver uses the fallback unless an override is set', () async {
    final tmp = Directory.systemTemp.createTempSync('res');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final d = await storageResolver(
      const StorageConfig(),
      fallback: () async => tmp,
    )();
    expect(d.path, tmp.path);
    final o = '${tmp.path}/custom';
    final d2 = await storageResolver(
      StorageConfig(dataDirOverride: o),
      fallback: () async => tmp,
    )();
    expect(d2.path, o);
    expect(Directory(o).existsSync(), isTrue);
  });
}
