import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/backup/backup_recovery_service.dart';
import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/storage/image_storage_service.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/ocr/services/ocr_history_repository.dart';
import 'package:exalted/features/ocv/services/ocv_rules_repository.dart';
import 'package:exalted/verify/verification_settings.dart';

void main() {
  late Directory tmp;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('data_dir_wiring_');
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

  Map<String, Object> snapshot() => {
    'image': c.read(imageStorageServiceProvider),
    'history': c.read(historyRepositoryProvider),
    'ocrHistory': c.read(ocrHistoryRepositoryProvider),
    'ocvRules': c.read(ocvRulesRepositoryProvider),
    'backup': c.read(backupRecoveryServiceProvider),
    'verification': c.read(verificationStoreProvider),
  };

  test('unrelated settings changes rebuild none of the providers', () async {
    final before = snapshot();
    await patch({
      'camera': {'quality': 'balanced'},
    });
    final after = snapshot();
    for (final k in before.keys) {
      expect(identical(before[k], after[k]), isTrue, reason: '$k rebuilt');
    }
  });

  test('changing the override rebuilds all of them', () async {
    final before = snapshot();
    await patch({
      'storage': {'dataDirOverride': '${tmp.path}${Platform.pathSeparator}d3'},
    });
    final after = snapshot();
    for (final k in before.keys) {
      expect(identical(before[k], after[k]), isFalse, reason: '$k not rebuilt');
    }
  });
}
