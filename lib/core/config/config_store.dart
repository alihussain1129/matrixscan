import 'dart:convert';
import 'dart:io';

import 'app_config.dart';

class ConfigLoadResult {
  final AppConfig config;
  final List<String> notes;

  /// True when the file was written by a NEWER app version. We run on defaults
  /// in memory and refuse to overwrite it.
  final bool readOnly;
  const ConfigLoadResult(this.config, this.notes, {this.readOnly = false});
}

class ConfigStore {
  ConfigStore(this.dir);
  final Directory dir;
  File get file => File('${dir.path}${Platform.pathSeparator}config.json');
  File get backup =>
      File('${dir.path}${Platform.pathSeparator}config.json.bak');
  bool _readOnly = false;

  /// Migrations run in order. Key N upgrades a map from version N to N+1.
  static final Map<int, Map<String, dynamic> Function(Map<String, dynamic>)>
  migrations = {
    0: (m) => {
      ...m,
      'version': 1,
    }, // pre-versioned files: same shape, add version
  };

  Future<ConfigLoadResult> load() async {
    final notes = <String>[];
    if (!await file.exists()) {
      notes.add('no config file, using defaults');
      return ConfigLoadResult(AppConfig.defaults(), notes);
    }
    final primary = await _tryRead(file, notes, 'config.json');
    if (primary != null) return primary;

    // Corrupt: keep it for inspection, never delete.
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final kept = '${file.path}.corrupt-$stamp';
    try {
      await file.rename(kept);
      notes.add('corrupt config preserved as $kept');
    } catch (e) {
      notes.add('could not preserve corrupt config: $e');
    }
    if (await backup.exists()) {
      final fromBak = await _tryRead(backup, notes, 'config.json.bak');
      if (fromBak != null) {
        notes.add('recovered from backup');
        return fromBak;
      }
    }
    notes.add('no usable backup, using defaults');
    return ConfigLoadResult(AppConfig.defaults(), notes);
  }

  Future<ConfigLoadResult?> _tryRead(
    File f,
    List<String> notes,
    String label,
  ) async {
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('root is not an object');
      }
      var map = raw;
      var v = map['version'] is int ? map['version'] as int : 0;
      if (v > AppConfig.currentVersion) {
        _readOnly = true;
        notes.add(
          '$label is from a newer app version ($v), left untouched, using defaults in memory',
        );
        return ConfigLoadResult(AppConfig.defaults(), notes, readOnly: true);
      }
      while (v < AppConfig.currentVersion) {
        final step = migrations[v];
        if (step == null) throw FormatException('no migration from version $v');
        map = step(map);
        v++;
        notes.add('migrated $label to version $v');
      }
      final issues = <ConfigIssue>[];
      final cfg = AppConfig.fromJson(map, issues);
      for (final i in issues) {
        notes.add('load issue: $i');
      }
      final bad = cfg.validate();
      if (bad.isNotEmpty) {
        // Values out of range: fall back to defaults but keep the file for the user to fix.
        for (final i in bad) {
          notes.add('invalid value: $i');
        }
        notes.add('invalid config in $label, using defaults in memory');
        return ConfigLoadResult(AppConfig.defaults(), notes);
      }
      return ConfigLoadResult(cfg, notes);
    } catch (e) {
      notes.add('$label unreadable: $e');
      return null;
    }
  }

  /// Validates, backs up the current file, then writes atomically (tmp + rename).
  Future<void> save(AppConfig c) async {
    if (_readOnly) {
      throw StateError(
        'config.json is from a newer app version, refusing to overwrite',
      );
    }
    final issues = c.validate();
    if (issues.isNotEmpty) throw ConfigInvalid(issues);
    await dir.create(recursive: true);
    if (await file.exists()) await file.copy(backup.path);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(c.toJson()),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// Restore safe defaults. The previous file is kept as .bak by save().
  Future<AppConfig> resetToDefaults() async {
    final d = AppConfig.defaults();
    await save(d);
    return d;
  }
}
