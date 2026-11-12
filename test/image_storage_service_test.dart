import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/storage/image_storage_service.dart';

void main() {
  late Directory tempDir;
  late ImageStorageService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('exalted_storage_test_');
    service = ImageStorageService(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'saveImageBytes writes file permanently to exalted_media directory',
    () async {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final path = await service.saveImageBytes(
        bytes,
        prefix: 'test_capture',
        ext: 'jpg',
      );

      expect(File(path).existsSync(), isTrue);
      expect(path, contains('exalted_media'));
      expect(path, contains('test_capture_'));
      expect(path.endsWith('.jpg'), isTrue);

      final readBytes = await File(path).readAsBytes();
      expect(readBytes, equals(bytes));
    },
  );

  test('persistSourceImage copies external file to media repository', () async {
    final srcFile = File('${tempDir.path}/external_source.png');
    await srcFile.writeAsString('sample-image-data-payload');

    final copiedPath = await service.persistSourceImage(
      srcFile.path,
      prefix: 'ocr_doc',
    );
    expect(File(copiedPath).existsSync(), isTrue);
    expect(copiedPath, contains('exalted_media'));
    expect(copiedPath, contains('ocr_doc_'));
    expect(copiedPath.endsWith('.png'), isTrue);

    final content = await File(copiedPath).readAsString();
    expect(content, equals('sample-image-data-payload'));
  });

  test('deleteImage deletes file', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final path = await service.saveImageBytes(bytes);
    expect(File(path).existsSync(), isTrue);

    final deleted = await service.deleteImage(path);
    expect(deleted, isTrue);
    expect(File(path).existsSync(), isFalse);
  });
}
