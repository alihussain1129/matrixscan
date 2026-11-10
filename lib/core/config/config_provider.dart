import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';
import 'config_store.dart';
import 'legacy_settings.dart';
import 'migrate.dart';

/// The app config. Defaults to [AppConfig.defaults] so code and tests that
/// never override it keep working. main() overrides it with the loaded value.
final configProvider = Provider<AppConfig>((ref) => AppConfig.defaults());

/// Loads config.json, or on first run builds a config from the settings the
/// app saved earlier. Never writes and never throws: on any failure it
/// returns defaults plus a note.
Future<ConfigLoadResult> loadStartupConfig({
  Directory? dir,
  Future<LegacySettings> Function()? readLegacy,
  ConfigStore? store,
}) async {
  final notes = <String>[];
  try {
    final d = dir ?? await getApplicationSupportDirectory();
    final st = store ?? ConfigStore(d);
    if (await st.file.exists()) {
      return await st.load();
    }
    notes.add('no config.json: built from saved settings (not written)');
    final legacy = await (readLegacy ?? readLegacySettings)();
    final cfg = migrateFromLegacy(legacy);
    final bad = cfg.validate();
    if (bad.isNotEmpty) {
      for (final i in bad) {
        notes.add('invalid migrated value: $i');
      }
      notes.add('using defaults');
      return ConfigLoadResult(AppConfig.defaults(), notes);
    }
    return ConfigLoadResult(cfg, notes);
  } catch (e) {
    notes.add('config load failed: $e, using defaults');
    return ConfigLoadResult(AppConfig.defaults(), notes);
  }
}
