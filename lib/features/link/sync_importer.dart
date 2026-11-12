import 'dart:io';
import 'dart:typed_data';

import '../history/history_entry.dart';
import '../history/history_repository.dart';
import '../inspection/inspection_log.dart';
import '../inspection/inspection_row.dart';
import '../ocr/models/ocr_record.dart';
import '../ocr/services/ocr_history_repository.dart';
import 'link_journal.dart';
import 'link_models.dart';

/// Saves image bytes in local storage and returns the new file path.
typedef ImageSaver = Future<String> Function(
  Uint8List bytes,
  String prefix,
  String ext,
);

/// Adds records that arrived from linked devices to this device's History.
/// Each device keeps its own records; nothing is overwritten. How far each
/// kind has been read is stored, so an entry the user deleted is not
/// brought back.
class SyncImporter {
  SyncImporter({
    required this.store,
    required this.ownDeviceId,
    required this.history,
    required this.ocr,
    required this.saveImage,
    this.inspection,
  });

  final FileSyncStore store;
  final String ownDeviceId;
  final HistoryRepository history;
  final OcrHistoryRepository ocr;
  final InspectionLog? inspection;
  final ImageSaver saveImage;

  List<SyncKind> get supported => [
    SyncKind.decoder,
    SyncKind.ocr,
    if (inspection != null) SyncKind.inspection,
  ];

  File _seqFile(SyncKind k) => File(
    '${store.dir.path}${Platform.pathSeparator}link_import_${k.name}.seq',
  );

  Future<int> _readSeq(SyncKind k) async {
    try {
      return int.parse((await _seqFile(k).readAsString()).trim());
    } catch (_) {
      return 0;
    }
  }

  /// Imports everything new from other devices. Returns how many records
  /// were added. Safe to run repeatedly.
  Future<int> importNew() async {
    var total = 0;
    for (final kind in supported) {
      total += await _importKind(kind);
    }
    return total;
  }

  /// Keeps an incoming conflict without replacing the current record.
  /// The deterministic suffix makes repeat attempts idempotent.
  Future<String?> saveConflictCopy(SyncRecord incoming) async {
    if (incoming.kind == SyncKind.image) return null;
    final copyId =
        '${incoming.id}~conflict-${incoming.contentHash.substring(0, 12)}';
    final copy = SyncRecord(
      id: copyId,
      kind: incoming.kind,
      originDeviceId: incoming.originDeviceId,
      createdAt: incoming.createdAt,
      payload: <String, Object?>{
        ...incoming.payload,
        'conflictOf': incoming.id,
        'conflictContentHash': incoming.contentHash,
      },
      blobs: incoming.blobs,
    );
    return await _import(copy) ? copyId : null;
  }

  Future<int> _importKind(SyncKind kind) async {
    var after = await _readSeq(kind);
    var imported = 0;
    while (true) {
      final page = store.page(
        after: after,
        limit: 200,
        excludeOrigin: ownDeviceId,
      );
      var done = after;
      var failed = false;
      for (final e in page.entries) {
        if (e.rec.kind == kind) {
          try {
            if (await _import(e.rec)) imported++;
          } catch (_) {
            failed = true;
            break;
          }
        }
        done = e.seq;
      }
      if (!failed && page.next > done) done = page.next;
      if (done != after) {
        await _seqFile(kind).writeAsString('$done', flush: true);
      }
      if (failed || !page.more || done == after) break;
      after = done;
    }
    return imported;
  }

  Future<bool> _import(SyncRecord rec) async {
    switch (rec.kind) {
      case SyncKind.decoder:
        return _importHistory(rec);
      case SyncKind.ocr:
        return _importOcr(rec);
      case SyncKind.inspection:
        return _importInspection(rec);
      case SyncKind.image:
        return false;
    }
  }

  Future<String?> _saveBlob(SyncRecord rec, String prefix) async {
    if (rec.blobs.isEmpty) return null;
    final bytes = await store.getBlob(rec.blobs.first);
    if (bytes == null) return null;
    final jpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    return saveImage(bytes, prefix, jpeg ? 'jpg' : 'png');
  }

  Future<bool> _importHistory(SyncRecord rec) async {
    final p = Map<String, Object?>.from(rec.payload);
    p['id'] = rec.id;
    p['originDeviceId'] = rec.originDeviceId;
    p.remove('imageSha256');
    p['imagePath'] = await _saveBlob(rec, 'linked');
    final entry = HistoryEntry.fromJson(p);
    if (entry == null) return false;
    return history.addImported(entry);
  }

  Future<bool> _importInspection(SyncRecord rec) async {
    final log = inspection;
    if (log == null) return false;
    final p = Map<String, Object?>.from(rec.payload);
    p['id'] = rec.id;
    p['originDeviceId'] = rec.originDeviceId;
    p.remove('imageSha256');
    p['imagePath'] = await _saveBlob(rec, 'linked_inspection');
    final row = InspectionRow.fromJson(p);
    if (row == null) return false;
    return log.addImported(row);
  }

  Future<bool> _importOcr(SyncRecord rec) async {
    final existing = await ocr.loadAll();
    if (existing.any((r) => r.id == rec.id)) return false;
    final p = Map<String, Object?>.from(rec.payload);
    p['id'] = rec.id;
    p.remove('imageSha256');
    p['imagePath'] = await _saveBlob(rec, 'linked_ocr') ?? '';
    final meta = p['metadata'] is Map
        ? Map<String, Object?>.from(p['metadata'] as Map)
        : <String, Object?>{};
    meta['originDevice'] = rec.originDeviceId;
    p['metadata'] = meta;
    final record = OcrRecord.fromJson(p);
    if (record == null) return false;
    await ocr.addRecord(record);
    return true;
  }
}
