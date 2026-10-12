import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'verification_engine.dart';

/// Online sources the user is allowed to switch on. Anything else in the
/// saved file is ignored.
const Set<String> knownOnlineSources = {
  'openfoodfacts',
  'openbeautyfacts',
  'openproductsfacts',
  'openlibrary',
  'nhtsa-vpic',
  'openfda-ndc',
};

/// Saves which online sources are allowed, in the app's private storage.
class VerificationSettingsStore {
  VerificationSettingsStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}${Platform.pathSeparator}verification_settings.json');
  }

  /// Never throws. Anything unreadable means "nothing allowed".
  Future<Set<String>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String>{};
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return <String>{};
      final list = raw['allowed'];
      if (list is! List) return <String>{};
      return <String>{
        for (final e in list)
          if (e is String && knownOnlineSources.contains(e)) e,
      };
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> save(Set<String> ids) async {
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      final sorted = ids.where(knownOnlineSources.contains).toList()..sort();
      await tmp.writeAsString(jsonEncode({'allowed': sorted}), flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  }
}

final verificationStoreProvider = Provider<VerificationSettingsStore>(
  (ref) => VerificationSettingsStore(),
);

final verificationEngineProvider = Provider<VerificationEngine>(
  (ref) => defaultVerificationEngine(),
);

/// IDs of the online sources the user has switched on. Empty by default.
class AllowedSourcesNotifier extends Notifier<Set<String>> {
  bool _disposed = false;
  bool _touched = false;

  @override
  Set<String> build() {
    ref.onDispose(() => _disposed = true);
    _load();
    return <String>{};
  }

  Future<void> _load() async {
    final ids = await ref.read(verificationStoreProvider).load();
    if (_disposed || _touched) return;
    state = ids;
  }

  Future<void> setAllowed(String id, bool on) async {
    if (!knownOnlineSources.contains(id)) return;
    _touched = true;
    final next = {...state};
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = next;
    await ref.read(verificationStoreProvider).save(next);
  }
}

final allowedSourcesProvider =
    NotifierProvider<AllowedSourcesNotifier, Set<String>>(
      AllowedSourcesNotifier.new,
    );

/// What the Settings screen shows for each online source.
class OnlineSourceChoice {
  const OnlineSourceChoice(this.id, this.name, this.subtitle);
  final String id;
  final String name;
  final String subtitle;
}

const List<OnlineSourceChoice> onlineSourceChoices = [
  OnlineSourceChoice(
    'openfoodfacts',
    'Open Food Facts',
    'Food and drink. Sends the GTIN only. Off by default. Community data, never shown as verified.',
  ),
  OnlineSourceChoice(
    'openbeautyfacts',
    'Open Beauty Facts',
    'Cosmetics. Sends the GTIN only. Off by default. Community data.',
  ),
  OnlineSourceChoice(
    'openproductsfacts',
    'Open Products Facts',
    'Household and general products. Sends the GTIN only. Off by default. Community data.',
  ),
  OnlineSourceChoice(
    'openlibrary',
    'Open Library',
    'Books. Sends the ISBN only. Off by default. Community data.',
  ),
  OnlineSourceChoice(
    'nhtsa-vpic',
    'NHTSA VIN decoder',
    'Vehicles. Sends the VIN only. Off by default. Best for US vehicles.',
  ),
  OnlineSourceChoice(
    'openfda-ndc',
    'openFDA drug directory (US)',
    'US drug and health-product listings. Sends the scanned UPC/GTIN only. Off by default. Official FDA listing, not proof a pack is genuine.',
  ),
];



