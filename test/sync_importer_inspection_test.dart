import 'dart:io';
import 'dart:typed_data';

import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/inspection/inspection_log.dart';
import 'package:exalted/features/inspection/inspection_row.dart';
import 'package:exalted/features/link/link_journal.dart';
import 'package:exalted/features/link/sync_bridge.dart';
import 'package:exalted/features/link/sync_importer.dart';
import 'package:exalted/features/ocr/services/ocr_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late FileSyncStore store;
  late SyncBridge phone;
  late InspectionLog log;
  late SyncImporter importer;

  final when = DateTime.utc(2026, 11, 11, 10);

  InspectionRow row(String id, String serial, RowStatus status) =>
      InspectionRow(
        id: id,
        createdAt: when,
        source: 'live',
        symbology: 'Data Matrix',
        raw: 'raw-$id',
        fields: {'21': serial},
        status: status,
        reasons: const ['r'],
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sync_inspection_test');
    store = FileSyncStore(Directory('${tmp.path}/journal'));
    await store.open();
    phone = SyncBridge(store: store, deviceId: 'phone-1');
    final data = Directory('${tmp.path}/data')..createSync();
    log = InspectionLog(directory: () async => data);
    importer = SyncImporter(
      store: store,
      ownDeviceId: 'desktop',
      history: HistoryRepository(directory: () async => data),
      ocr: OcrHistoryRepository(directoryProvider: () async => data),
      inspection: log,
      saveImage: (Uint8List b, String prefix, String ext) async {
        final f = File('${tmp.path}/img.$ext');
        await f.writeAsBytes(b);
        return f.path;
      },
    );
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('imports inspection rows once, keeping their own result', () async {
    await phone.journalInspection(row('r1', 'S1', RowStatus.fail));
    await phone.journalInspection(row('r2', 'S1', RowStatus.pass));
    expect(await importer.importNew(), 2);
    final rows = await log.loadAll();
    expect(rows.length, 2);
    expect(rows.map((r) => r.id).toSet(), {
      'phone-1:inspection:r1',
      'phone-1:inspection:r2',
    });
    expect(rows.firstWhere((r) => r.raw == 'raw-r2').status, RowStatus.pass);
    expect(rows.firstWhere((r) => r.raw == 'raw-r2').originDeviceId, 'phone-1');
    expect(await importer.importNew(), 0);
    expect((await log.loadAll()).length, 2);
  });
}
