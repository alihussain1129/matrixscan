import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ocv_rule.dart';
import '../../../core/config/data_directory_provider.dart';
import '../../../core/storage/json_decode.dart';

/// Manages persistent storage and retrieval of industrial OCV verification rules.
class OcvRulesRepository {
  OcvRulesRepository({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<File> _file() async {
    final dir = await _directoryProvider();
    return File('${dir.path}${Platform.pathSeparator}ocv_rules.json');
  }

  /// Loads all rules from disk, initializing with factory presets if first run.
  Future<List<OcvRule>> loadRules() async {
    final file = await _file();
    if (!await file.exists()) {
      final presets = OcvRule.presets();
      await saveRules(presets);
      return presets;
    }

    try {
      final raw = await decodeJsonOffThread(await file.readAsString());
      if (raw is! List) return OcvRule.presets();

      final list = <OcvRule>[];
      for (final item in raw) {
        final r = OcvRule.fromJson(item);
        if (r != null) list.add(r);
      }

      if (list.isEmpty) {
        return OcvRule.presets();
      }
      return list;
    } catch (_) {
      return OcvRule.presets();
    }
  }

  /// Saves rules atomically to disk.
  Future<void> saveRules(List<OcvRule> rules) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(rules.map((r) => r.toJson()).toList()),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// Adds or updates a rule.
  Future<void> upsertRule(OcvRule rule) async {
    final rules = await loadRules();
    final idx = rules.indexWhere((r) => r.id == rule.id);
    if (idx != -1) {
      rules[idx] = rule;
    } else {
      rules.add(rule);
    }
    await saveRules(rules);
  }

  /// Deletes a rule by ID.
  Future<void> deleteRule(String id) async {
    final rules = await loadRules();
    rules.removeWhere((r) => r.id == id);
    await saveRules(rules);
  }
}

final ocvRulesRepositoryProvider = Provider<OcvRulesRepository>((ref) {
  return OcvRulesRepository(directoryProvider: ref.watch(dataDirectoryProvider));
});
