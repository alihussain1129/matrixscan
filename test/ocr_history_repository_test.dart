import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/storage/image_storage_service.dart';
import 'package:exalted/features/ocr/models/ocr_record.dart';
import 'package:exalted/features/ocr/services/ocr_history_repository.dart';

void main() {
  late Directory tempDir;
  late ImageStorageService imageStorage;
  late OcrHistoryRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ocr_repo_test_');
    imageStorage = ImageStorageService(directoryProvider: () async => tempDir);
    repository = OcrHistoryRepository(
      directoryProvider: () async => tempDir,
      imageStorageService: imageStorage,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'addRecord and loadAll correctly stores and retrieves OCR records',
    () async {
      final record1 = OcrRecord(
        id: 'ocr-1',
        imagePath: '/tmp/test1.png',
        text: 'BATCH 2026-X',
        rawText: 'BATCH 2026-X',
        createdAt: DateTime(2026, 11, 2, 10, 0),
        confidence: 0.95,
        language: 'eng',
        engine: 'Tesseract 5.3',
      );

      final record2 = OcrRecord(
        id: 'ocr-2',
        imagePath: '/tmp/test2.png',
        text: 'SERIAL 98765',
        rawText: 'SERIAL 98765',
        createdAt: DateTime(2026, 11, 2, 10, 5),
        confidence: 0.88,
        language: 'eng',
        engine: 'Tesseract 5.3',
      );

      await repository.addRecord(record1);
      await repository.addRecord(record2);

      final loaded = await repository.loadAll();
      expect(loaded.length, equals(2));
      expect(loaded[0].id, equals('ocr-2')); // Newest first
      expect(loaded[1].id, equals('ocr-1'));
      expect(loaded[0].text, equals('SERIAL 98765'));
      expect(loaded[0].confidence, equals(0.88));
    },
  );

  test('filter correctly searches by query and ocv status', () async {
    final list = [
      OcrRecord(
        id: '1',
        imagePath: '',
        text: 'EXALTED INDUSTRIAL VISION',
        rawText: 'EXALTED INDUSTRIAL VISION',
        createdAt: DateTime.now(),
        ocvPassed: true,
      ),
      OcrRecord(
        id: '2',
        imagePath: '',
        text: 'LOT NUM 10042',
        rawText: 'LOT NUM 10042',
        createdAt: DateTime.now(),
        ocvPassed: false,
      ),
    ];

    final filteredQuery = repository.filter(list, 'lot');
    expect(filteredQuery.length, equals(1));
    expect(filteredQuery.first.id, equals('2'));

    final filteredPassed = repository.filter(list, '', ocvPassed: true);
    expect(filteredPassed.length, equals(1));
    expect(filteredPassed.first.id, equals('1'));
  });

  test('updateRecord and togglePin work properly', () async {
    final record = OcrRecord(
      id: 'ocr-update',
      imagePath: '',
      text: 'Original Text',
      rawText: 'Original Text',
      createdAt: DateTime.now(),
    );

    await repository.addRecord(record);
    await repository.updateRecord(record.copyWith(text: 'Edited Text'));

    var loaded = await repository.loadAll();
    expect(loaded.first.text, equals('Edited Text'));
    expect(loaded.first.pinned, isFalse);

    await repository.togglePin('ocr-update');
    loaded = await repository.loadAll();
    expect(loaded.first.pinned, isTrue);
  });
}
