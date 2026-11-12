import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// Returns the folder the app stores data in today
/// (getApplicationDocumentsDirectory), or storage.dataDirOverride if set.
/// Matches the directoryProvider parameter of the existing repositories.
/// Changing the override never moves or deletes existing data.
Future<Directory> Function() storageResolver(
  StorageConfig storage, {
  Future<Directory> Function()? fallback,
}) {
  final base = fallback ?? getApplicationDocumentsDirectory;
  final override = storage.dataDirOverride;
  if (override == null || override.trim().isEmpty) return base;
  return () async {
    final dir = Directory(override);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  };
}
