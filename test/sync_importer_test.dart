import 'dart:io';
import 'dart:typed_data';

import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/link/link_journal.dart';
import 'package:exalted/features/link/link_models.dart';
import 'package:exalted/features/link/sync_bridge.dart';
import 'package:exalted/features/link/sync_importer.dart';
import 'package:exalted/features/ocr/services/ocr_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late FileSyncStore store;
  late SyncBridge phone;
  late HistoryRepository history;
  late OcrHistoryRepository ocr;
  late SyncImporter importer;
  var imageCount = 0;

  final when = DateTime.utc(2026, 11, 11, 10);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sync_importer_test');
    store = FileSyncStore(Directory('${tmp.path}/journal'));
    await store.open();
    phone = SyncBridge(store: store, deviceId: 'phone-1');
    final data = Directory('${tmp.path}/data')..createSync();
    history = HistoryRepository(directory: () async => data);
    ocr = OcrHistoryRepository(directoryProvider: () async => data);
    importer = SyncImporter(
      store: store,
      ownDeviceId: 'desktop',
      history: history,
      ocr: ocr,
      saveImage: (Uint8List bytes, String prefix, String ext) async {
        final f = File('${tmp.path}/img_${imageCount++}.$ext');
        await f.writeAsBytes(bytes);
        return f.path;
      },
    );
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> journalScan(String id, String text, {String? image}) async {
    await phone.journalHistory(
      HistoryEntry(
        id: id,
        kind: HistoryKind.barcode,
        source: HistorySource.live,
        text: text,
        createdAt: when,
        format: 'Data Matrix',
        imagePath: image,
      ),
    );
  }

  Future<void> journalOcrText(String id, String text) async {
    await phone.journal(
      kind: SyncKind.ocr,
      localId: id,
      createdAt: when,
      payload: {
        'text': text,
        'rawText': text,
        'createdAt': when.toIso8601String(),
        'language': 'eng',
        'engine': 'Tesseract',
        'confidence': 0.9,
        'processingDurationMs': 12,
        'blockCount': 1,
        'lineCount': 1,
        'wordCount': 1,
        'pinned': false,
        'metadata': <String, Object?>{},
      },
    );
  }

  test('imports decoder and OCR records with images and origin', () async {
    final img = File('${tmp.path}/scan.png')..writeAsBytesSync([1, 2, 3, 4]);
    await journalScan('a1', '012345', image: img.path);
    await journalOcrText('o1', 'hello');
    expect(await importer.importNew(), 2);

    final h = await history.loadAll();
    expect(h.single.id, 'phone-1:decoder:a1');
    expect(h.single.originDeviceId, 'phone-1');
    expect(h.single.text, '012345');
    expect(File(h.single.imagePath!).readAsBytesSync(), [1, 2, 3, 4]);

    final o = await ocr.loadAll();
    expect(o.single.text, 'hello');
    expect(o.single.metadata['originDevice'], 'phone-1');
  });

  test('a second run adds nothing', () async {
    await journalScan('a1', 'A');
    await journalOcrText('o1', 'x');
    expect(await importer.importNew(), 2);
    expect(await importer.importNew(), 0);
    expect((await history.loadAll()).length, 1);
    expect((await ocr.loadAll()).length, 1);
  });

  test('saving a conflict creates a separate incoming History copy', () async {
    final current = SyncRecord(
      id: 'peer-1:decoder:shared',
      kind: SyncKind.decoder,
      originDeviceId: 'peer-1',
      createdAt: when,
      payload: {
        'kind': 'barcode',
        'source': 'live',
        'text': 'current',
        'createdAt': when.toIso8601String(),
      },
    );
    final incoming = SyncRecord(
      id: current.id,
      kind: SyncKind.decoder,
      originDeviceId: 'peer-1',
      createdAt: when,
      payload: {
        'kind': 'barcode',
        'source': 'live',
        'text': 'incoming alternate',
        'createdAt': when.toIso8601String(),
      },
    );
    await store.add(current);
    expect(await store.add(incoming), IngestResult.conflict);
    expect(await importer.importNew(), 1);

    final copyId = await importer.saveConflictCopy(incoming);
    expect(
      copyId,
      '${incoming.id}~conflict-${incoming.contentHash.substring(0, 12)}',
    );
    final records = await history.loadAll();
    expect(records, hasLength(2));
    expect(
      records.map((r) => r.text),
      containsAll(['current', 'incoming alternate']),
    );
    expect(records.where((r) => r.text == 'current').single.id, current.id);
    expect(
      records.where((r) => r.text == 'incoming alternate').single.id,
      copyId,
    );
    expect(await importer.saveConflictCopy(incoming), isNull);
    expect(await history.loadAll(), hasLength(2));
  });

  test('records from the offline period arrive later, once', () async {
    await journalScan('a1', 'A');
    expect(await importer.importNew(), 1);
    await journalScan('a2', 'B');
    await journalScan('a3', 'C');
    expect(await importer.importNew(), 2);
    expect(await importer.importNew(), 0);
    expect((await history.loadAll()).length, 3);
  });

  test('a deleted imported entry is not brought back', () async {
    await journalScan('a1', 'A');
    await importer.importNew();
    await history.delete('phone-1:decoder:a1');
    expect(await importer.importNew(), 0);
    expect(await history.loadAll(), isEmpty);
  });

  test('records from this device are never imported', () async {
    final own = SyncBridge(store: store, deviceId: 'desktop');
    await own.journal(
      kind: SyncKind.decoder,
      localId: 'x',
      createdAt: when,
      payload: {
        'kind': 'barcode',
        'source': 'live',
        'text': 'own',
        'createdAt': when.toIso8601String(),
      },
    );
    expect(await importer.importNew(), 0);
  });

  test('addImported ignores the repeat filter but not the same ID', () async {
    final e = HistoryEntry(
      id: 'p:decoder:1',
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: 'same',
      createdAt: when,
    );
    final e2 = HistoryEntry(
      id: 'p:decoder:2',
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: 'same',
      createdAt: when,
    );
    expect(await history.addImported(e), isTrue);
    expect(await history.addImported(e), isFalse);
    expect(await history.addImported(e2), isTrue);
    expect((await history.loadAll()).length, 2);
  });
}
