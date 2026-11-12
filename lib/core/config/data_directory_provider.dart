import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'config_controller.dart';
import 'storage_resolver.dart';

/// The folder every repository stores its data in: the app default, or
/// storage.dataDirOverride when set. Watches only the override string, so
/// unrelated settings changes do not rebuild the repositories. Changing the
/// override never moves or deletes existing data.
final dataDirectoryProvider = Provider<Future<Directory> Function()>((ref) {
  final override = ref.watch(
    configControllerProvider.select((c) => c.storage.dataDirOverride),
  );
  return storageResolver(StorageConfig(dataDirOverride: override));
});
