import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/config/data_directory_provider.dart';
import 'package:exalted/core/storage/image_storage_service.dart';
import 'package:exalted/features/history/history_repository.dart';

void main() {
  late Directory tmp;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('data_dir_test_');
    c = ProviderContainer();
  });

  tearDown(() {
    c.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> patch(Map<String, Map<String, dynamic>> p) async {
    final r = await c.read(configControllerProvider.notifier).patch(p);
    expect(r.applied, isTrue, reason: '${r.issues}');
  }

  test('an override redirects the resolver and creates the folder', () async {
    final target = '${tmp.path}${Platform.pathSeparator}data';
    await patch({
      'storage': {'dataDirOverride': target},
    });
    final dir = await c.read(dataDirectoryProvider)();
    expect(dir.path, target);
    expect(dir.existsSync(), isTrue);
  });

  test('unrelated settings changes keep the same repositories', () async {
    final img = c.read(imageStorageServiceProvider);
    final hist = c.read(historyRepositoryProvider);
    await patch({
      'camera': {'quality': 'balanced'},
    });
    expect(identical(c.read(imageStorageServiceProvider), img), isTrue);
    expect(identical(c.read(historyRepositoryProvider), hist), isTrue);
  });

  test('changing the override rebuilds the repositories', () async {
    final img = c.read(imageStorageServiceProvider);
    final hist = c.read(historyRepositoryProvider);
    await patch({
      'storage': {'dataDirOverride': '${tmp.path}${Platform.pathSeparator}d2'},
    });
    expect(identical(c.read(imageStorageServiceProvider), img), isFalse);
    expect(identical(c.read(historyRepositoryProvider), hist), isFalse);
  });
}
