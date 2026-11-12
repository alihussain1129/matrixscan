import 'app_config.dart';
import 'legacy_settings.dart';

/// Builds a config from values the app saved before config.json existed.
/// Pure: reads [legacy], writes nothing. Fields never saved keep defaults.
AppConfig migrateFromLegacy(LegacySettings legacy) {
  final issues = <ConfigIssue>[];
  return AppConfig.fromJson({
    'version': AppConfig.currentVersion,
    'scanner': {
      ...legacy.scannerJson(),
      if (legacy.host != null) 'hostSaved': true,
    },
    'camera': legacy.cameraJson(),
    'decoder': legacy.decoderJson(),
    'storage': legacy.storageJson(),
    'appearance': legacy.appearanceJson(),
  }, issues);
}
