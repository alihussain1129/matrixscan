import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'config_provider.dart';
import 'config_store.dart';

/// Where changes are saved. null = in memory only (tests, and until main()
/// provides a store). Use the same ConfigStore instance that loaded the file,
/// so its "file is from a newer version" guard applies to saves.
final configStoreProvider = Provider<ConfigStore?>((ref) => null);

class ConfigUpdateResult {
  const ConfigUpdateResult({this.issues = const [], this.saveError});

  /// Validation problems. When not empty, nothing was changed.
  final List<ConfigIssue> issues;

  /// Set when the change applied in memory but could not be written to disk.
  final String? saveError;

  bool get applied => issues.isEmpty;
  bool get saved => applied && saveError == null;
}

/// The editable app config. Starts from [configProvider]. Settings screens and
/// the coordinator change it through [patch].
class ConfigController extends Notifier<AppConfig> {
  Future<void> _queue = Future<void>.value();

  @override
  AppConfig build() => ref.read(configProvider);

  /// Merges [sections] (for example {'scanner': {'host': '10.0.0.5'}}) into
  /// the config, validates the result and saves it. Calls run one at a time.
  Future<ConfigUpdateResult> patch(Map<String, Map<String, dynamic>> sections) {
    final result = _queue.then((_) => _apply(sections));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<ConfigUpdateResult> _apply(
    Map<String, Map<String, dynamic>> sections,
  ) async {
    if (!ref.mounted) {
      return const ConfigUpdateResult(saveError: 'config controller disposed');
    }
    final json = state.toJson();
    for (final e in sections.entries) {
      final current = json[e.key];
      if (current is! Map<String, dynamic>) {
        return ConfigUpdateResult(
          issues: [ConfigIssue(e.key, 'unknown config section')],
        );
      }
      json[e.key] = {...current, ...e.value};
    }
    final issues = <ConfigIssue>[];
    final next = AppConfig.fromJson(json, issues);
    issues.addAll(next.validate());
    if (issues.isNotEmpty) return ConfigUpdateResult(issues: issues);

    state = next;
    final store = ref.read(configStoreProvider);
    if (store == null) return const ConfigUpdateResult();
    try {
      await store.save(next);
      return const ConfigUpdateResult();
    } catch (e) {
      return ConfigUpdateResult(saveError: '$e');
    }
  }
}

final configControllerProvider = NotifierProvider<ConfigController, AppConfig>(
  ConfigController.new,
);
