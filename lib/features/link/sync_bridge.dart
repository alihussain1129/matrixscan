import 'dart:io';

import '../history/history_entry.dart';
import '../inspection/inspection_row.dart';
import '../ocr/models/ocr_record.dart';
import 'link_journal.dart';
import 'link_models.dart';

/// Turns locally saved records into journal entries so they can be synced.
/// It never throws: a failure here must not break scanning or saving.
class SyncBridge {
  SyncBridge({required this.store, required this.deviceId});

  final FileSyncStore store;

  /// ID of this device. Part of every record ID, so IDs never collide
  /// between devices.
  final String deviceId;

  Future<IngestResult?> journalHistory(HistoryEntry e) => journal(
    kind: SyncKind.decoder,
    localId: e.id,
    createdAt: e.createdAt,
    payload: Map<String, Object?>.from(e.toJson()),
    imagePath: e.imagePath,
  );

  Future<IngestResult?> journalOcr(OcrRecord r) => journal(
    kind: SyncKind.ocr,
    localId: r.id,
    createdAt: r.createdAt,
    payload: Map<String, Object?>.from(r.toJson()),
    imagePath: r.imagePath,
  );

  Future<IngestResult?> journalInspection(InspectionRow r) => journal(
    kind: SyncKind.inspection,
    localId: r.id,
    createdAt: r.createdAt,
    payload: Map<String, Object?>.from(r.toJson()),
    imagePath: r.imagePath,
  );

  /// Journals every local record that is not in the journal yet. Safe to run
  /// repeatedly: IDs are deterministic and known records are skipped before
  /// any image is read. Oldest first. Returns how many were newly journaled.
  Future<int> sweep({
    required Iterable<HistoryEntry> history,
    required Iterable<OcrRecord> ocr,
    required Iterable<InspectionRow> inspection,
  }) async {
    final known = <String>{for (final r in store.allRecords()) r.id};
    var added = 0;
    Future<void> one(
      SyncKind kind,
      String localId,
      Future<IngestResult?> Function() go,
    ) async {
      if (known.contains('$deviceId:${kind.name}:$localId')) return;
      if (await go() == IngestResult.added) added++;
    }

    for (final e in history.toList().reversed) {
      if (e.originDeviceId != null || known.contains(e.id)) continue;
      await one(SyncKind.decoder, e.id, () => journalHistory(e));
    }
    for (final r in ocr.toList().reversed) {
      if (r.metadata['originDevice'] is String || known.contains(r.id)) {
        continue;
      }
      await one(SyncKind.ocr, r.id, () => journalOcr(r));
    }
    for (final r in inspection.toList().reversed) {
      if (r.originDeviceId != null || known.contains(r.id)) continue;
      await one(SyncKind.inspection, r.id, () => journalInspection(r));
    }
    return added;
  }

  /// Journals one record. Returns null when nothing was journaled (for
  /// example the named image cannot be read), so the caller may retry.
  Future<IngestResult?> journal({
    required SyncKind kind,
    required String localId,
    required DateTime createdAt,
    required Map<String, Object?> payload,
    String? imagePath,
  }) async {
    try {
      final blobs = <String>[];
      if (imagePath != null && imagePath.isNotEmpty) {
        final file = File(imagePath);
        if (!await file.exists()) return null;
        blobs.add(await store.storeBlob(await file.readAsBytes()));
      }
      payload.remove('imagePath');
      if (blobs.isNotEmpty) payload['imageSha256'] = blobs.first;
      final rec = SyncRecord(
        id: '$deviceId:${kind.name}:$localId',
        kind: kind,
        originDeviceId: deviceId,
        createdAt: createdAt,
        payload: payload,
        blobs: blobs,
      );
      return await store.add(rec);
    } catch (_) {
      return null;
    }
  }
}

/// How many journal entries made by [deviceId] come after [after] (the
/// position up to which a desktop already has this device's records).
int pendingCount(FileSyncStore store, String deviceId, int after) {
  var n = 0;
  var cursor = after;
  while (true) {
    final page = store.page(after: cursor, limit: 1000, onlyOrigin: deviceId);
    n += page.entries.length;
    if (!page.more || page.next <= cursor) break;
    cursor = page.next;
  }
  return n;
}
