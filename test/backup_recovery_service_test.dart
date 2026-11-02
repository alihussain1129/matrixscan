import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/backup/backup_recovery_service.dart';
import 'package:exalted/core/storage/image_storage_service.dart';
import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/ocr/models/ocr_record.dart';
import 'package:exalted/features/ocr/services/ocr_history_repository.dart';
import 'package:exalted/features/ocv/models/ocv_rule.dart';
import 'package:exalted/features/ocv/services/ocv_rules_repository.dart';

void main() {
  late Directory tempDir;
  late HistoryRepository historyRepo;
  late OcrHistoryRepository ocrRepo;
  late OcvRulesRepository ocvRulesRepo;
  late ImageStorageService imageStorage;
  late BackupRecoveryService backupService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_test_');
    historyRepo = HistoryRepository(directory: () async => tempDir);
    imageStorage = ImageStorageService(directoryProvider: () async => tempDir);
    ocrRepo = OcrHistoryRepository(
      directoryProvider: () async => tempDir,
      imageStorageService: imageStorage,
    );
    ocvRulesRepo = OcvRulesRepository(directoryProvider: () async => tempDir);
    backupService = BackupRecoveryService(
      historyRepo: historyRepo,
      ocrRepo: ocrRepo,
      ocvRulesRepo: ocvRulesRepo,
      imageStorage: imageStorage,
      directoryProvider: () async => tempDir,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('exportBackupJson and restoreBackupJson round-trip accurately', () async {
    // 1. Add some initial records
    await historyRepo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: 'BARCODE-999',
      format: 'Data Matrix',
    );

    await ocrRepo.addRecord(
      OcrRecord(
        id: 'ocr-100',
        imagePath: '',
        text: 'EXTRACTED TEST',
        rawText: 'EXTRACTED TEST',
        createdAt: DateTime.now(),
      ),
    );

    // 2. Export backup
    final backupJson = await backupService.exportBackupJson();
    expect(backupJson, contains('BARCODE-999'));
    expect(backupJson, contains('EXTRACTED TEST'));
    expect(backupJson, contains('exalted_schema_version'));

    // 3. Clear repositories
    await historyRepo.clear();
    await ocrRepo.clearAll();
    expect((await historyRepo.loadAll()), isEmpty);
    expect((await ocrRepo.loadAll()), isEmpty);

    // 4. Restore backup
    final summary = await backupService.restoreBackupJson(backupJson);
    expect(summary.isSuccess, isTrue);
    expect(summary.decoderRecordsRestored, equals(1));
    expect(summary.ocrRecordsRestored, equals(1));

    // Verify restored items
    final restoredDecoder = await historyRepo.loadAll();
    expect(restoredDecoder.first.text, equals('BARCODE-999'));

    final restoredOcr = await ocrRepo.loadAll();
    expect(restoredOcr.first.text, equals('EXTRACTED TEST'));
  });

  test('checkStorageIntegrity detects valid and missing image files', () async {
    // Create one valid dummy image file
    final dummyImg = File('${tempDir.path}/valid.jpg');
    await dummyImg.writeAsString('image-payload');

    await historyRepo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.gallery,
      text: 'VALID-IMG-CODE',
      imagePath: dummyImg.path,
    );

    await ocrRepo.addRecord(
      OcrRecord(
        id: 'ocr-missing',
        imagePath: '${tempDir.path}/non_existent_file.jpg',
        text: 'MISSING TEST',
        rawText: 'MISSING TEST',
        createdAt: DateTime.now(),
      ),
    );

    final integrity = await backupService.checkStorageIntegrity();
    expect(integrity['totalImagesTracked'], equals(2));
    expect(integrity['validImages'], equals(1));
    expect(integrity['missingImages'], equals(1));
    expect(integrity['isHealthy'], isFalse);
  });
}
