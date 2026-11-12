import 'dart:io';

import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/link/link_journal.dart';
import 'package:exalted/features/link/link_models.dart';
import 'package:exalted/features/link/sync_bridge.dart';
import 'package:exalted/features/inspection/inspection_row.dart';
import 'package:exalted/features/ocr/models/ocr_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late FileSyncStore store;
  late SyncBridge bridge;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sync_bridge_test');
    store = FileSyncStore(Directory('${tmp.path}/journal'));
    await store.open();
    bridge = SyncBridge(store: store, deviceId: 'phone-1');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  final when = DateTime.utc(2026, 11, 11, 10);

  test('journals a record once; a repeat is a duplicate', () async {
    Future<IngestResult?> go() => bridge.journal(
      kind: SyncKind.decoder,
      localId: 'a1',
      createdAt: when,
      payload: {'text': '012345', 'format': 'Data Matrix'},
    );
    expect(await go(), IngestResult.added);
    expect(await go(), IngestResult.duplicate);
    expect(store.length, 1);
  });

  test('stores the image by SHA-256 and drops the local path', () async {
    final img = File('${tmp.path}/scan.png')..writeAsBytesSync([1, 2, 3, 4]);
    final r = await bridge.journal(
      kind: SyncKind.inspection,
      localId: 'i1',
      createdAt: when,
      payload: {'raw': 'x', 'imagePath': img.path},
      imagePath: img.path,
    );
    expect(r, IngestResult.added);
    final rec = store.allRecords().single;
    final sha = rec.blobs.single;
    expect(await store.hasBlob(sha), isTrue);
    expect(rec.payload.containsKey('imagePath'), isFalse);
    expect(rec.payload['imageSha256'], sha);
  });

  test('a missing image means nothing is journaled', () async {
    final r = await bridge.journal(
      kind: SyncKind.ocr,
      localId: 'o1',
      createdAt: when,
      payload: {'text': 'hello'},
      imagePath: '${tmp.path}/does_not_exist.png',
    );
    expect(r, isNull);
    expect(store.length, 0);
  });

  test('record IDs include the device, so devices never collide', () async {
    final other = SyncBridge(store: store, deviceId: 'phone-2');
    await bridge.journal(
      kind: SyncKind.decoder,
      localId: 'same',
      createdAt: when,
      payload: {'text': 't'},
    );
    final r = await other.journal(
      kind: SyncKind.decoder,
      localId: 'same',
      createdAt: when,
      payload: {'text': 't'},
    );
    expect(r, IngestResult.added);
    expect(store.length, 2);
  });

  test('sweep journals new records once and never duplicates', () async {
    HistoryEntry entry(String id, String text) => HistoryEntry(
      id: id,
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: text,
      createdAt: when,
    );
    final first = [entry('2', 'B'), entry('1', 'A')];
    expect(
      await bridge.sweep(history: first, ocr: const [], inspection: const []),
      2,
    );
    // Offline: one more record is saved, then the sweep runs again.
    final second = [entry('3', 'C'), ...first];
    expect(
      await bridge.sweep(history: second, ocr: const [], inspection: const []),
      1,
    );
    expect(
      await bridge.sweep(history: second, ocr: const [], inspection: const []),
      0,
    );
    expect(store.length, 3);
    expect(store.allRecords().first.payload['text'], 'A');
  });

  test('sweep does not re-journal imported records as local records', () async {
    final importedHistory = HistoryEntry(
      id: 'peer-1:decoder:scan-1',
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: 'remote scan',
      createdAt: when,
      originDeviceId: 'peer-1',
    );
    final importedOcr = OcrRecord(
      id: 'peer-1:ocr:ocr-1',
      imagePath: '',
      text: 'remote text',
      rawText: 'remote text',
      createdAt: when,
      metadata: const {'originDevice': 'peer-1'},
    );
    final importedInspection = InspectionRow(
      id: 'peer-1:inspection:row-1',
      createdAt: when,
      source: 'camera',
      symbology: 'Data Matrix',
      raw: 'remote inspection',
      fields: const {},
      status: RowStatus.pass,
      originDeviceId: 'peer-1',
    );

    expect(
      await bridge.sweep(
        history: [importedHistory],
        ocr: [importedOcr],
        inspection: [importedInspection],
      ),
      0,
    );
    expect(store.length, 0);
  });

  test(
    'legacy imported record already in journal is not copied under new ID',
    () async {
      final remote = SyncRecord(
        id: 'peer-1:decoder:legacy-1',
        kind: SyncKind.decoder,
        originDeviceId: 'peer-1',
        createdAt: when,
        payload: {
          'id': 'peer-1:decoder:legacy-1',
          'kind': 'barcode',
          'source': 'live',
          'text': 'legacy',
          'createdAt': when.toIso8601String(),
        },
      );
      await store.add(remote);
      final legacyHistory = HistoryEntry(
        id: remote.id,
        kind: HistoryKind.barcode,
        source: HistorySource.live,
        text: 'legacy',
        createdAt: when,
      );
      expect(
        await bridge.sweep(
          history: [legacyHistory],
          ocr: const [],
          inspection: const [],
        ),
        0,
      );
      expect(store.length, 1);
    },
  );
}
