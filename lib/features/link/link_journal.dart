import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'link_crypto.dart';
import 'link_models.dart';

enum IngestResult { added, duplicate, conflict }

class JournalEntry {
  JournalEntry(this.seq, this.rec);
  final int seq;
  final SyncRecord rec;
}

class JournalPage {
  JournalPage(this.entries, this.next, this.more);
  final List<JournalEntry> entries;
  final int next;
  final bool more;
}

/// Append-only evidence journal plus a store for original image files.
/// Records are never edited or deleted. If the same ID arrives with different
/// content, both versions are kept (the second goes to the conflicts file).
class FileSyncStore {
  FileSyncStore(this.dir);

  final Directory dir;
  final List<JournalEntry> _entries = [];
  final Map<String, String> _hashes = {};
  final Set<String> _conflictKeys = {};
  Future<void> _queue = Future<void>.value();

  String get _sep => Platform.pathSeparator;
  File get _journalFile => File('${dir.path}${_sep}link_journal.jsonl');
  File get _conflictFile => File('${dir.path}${_sep}link_conflicts.jsonl');
  Directory get _blobDir => Directory('${dir.path}${_sep}link_blobs');

  int get lastSeq => _entries.isEmpty ? 0 : _entries.last.seq;
  int get length => _entries.length;

  Future<void> open() async {
    await dir.create(recursive: true);
    await _blobDir.create(recursive: true);
    if (await _journalFile.exists()) {
      final text = await _journalFile.readAsString();
      for (final line in const LineSplitter().convert(text)) {
        try {
          final j = jsonDecode(line);
          final rec = SyncRecord.fromJson((j as Map)['rec']);
          final seq = j['seq'];
          if (rec == null || seq is! int) continue;
          _entries.add(JournalEntry(seq, rec));
          _hashes[rec.id] = rec.contentHash;
        } catch (_) {
          // A half-written last line after a crash is skipped.
        }
      }
      if (text.isNotEmpty && !text.endsWith('\n')) {
        await _journalFile.writeAsString('\n', mode: FileMode.append);
      }
    }
    if (await _conflictFile.exists()) {
      for (final line in const LineSplitter().convert(
        await _conflictFile.readAsString(),
      )) {
        try {
          final rec = SyncRecord.fromJson(jsonDecode(line));
          if (rec != null) _conflictKeys.add('${rec.id}:${rec.contentHash}');
        } catch (_) {}
      }
    }
  }

  Future<IngestResult> add(SyncRecord r) {
    final f = _queue.then((_) => _add(r));
    _queue = f.then<void>((_) {}, onError: (Object _) {});
    return f;
  }

  Future<IngestResult> _add(SyncRecord r) async {
    final existing = _hashes[r.id];
    if (existing != null) {
      if (existing == r.contentHash) return IngestResult.duplicate;
      final key = '${r.id}:${r.contentHash}';
      if (_conflictKeys.add(key)) {
        await _conflictFile.writeAsString(
          '${jsonEncode(r.toJson())}\n',
          mode: FileMode.append,
          flush: true,
        );
      }
      return IngestResult.conflict;
    }
    final seq = lastSeq + 1;
    await _journalFile.writeAsString(
      '${jsonEncode({'seq': seq, 'rec': r.toJson()})}\n',
      mode: FileMode.append,
      flush: true,
    );
    _entries.add(JournalEntry(seq, r));
    _hashes[r.id] = r.contentHash;
    return IngestResult.added;
  }

  Future<List<SyncRecord>> conflicts() async {
    if (!await _conflictFile.exists()) return [];
    final out = <SyncRecord>[];
    for (final line in const LineSplitter().convert(
      await _conflictFile.readAsString(),
    )) {
      try {
        final rec = SyncRecord.fromJson(jsonDecode(line));
        if (rec != null) out.add(rec);
      } catch (_) {}
    }
    return out;
  }

  List<SyncRecord> allRecords() => [for (final e in _entries) e.rec];

  int _firstAfter(int after) {
    var lo = 0;
    var hi = _entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_entries[mid].seq <= after) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  JournalPage page({
    required int after,
    int limit = 100,
    String? onlyOrigin,
    String? excludeOrigin,
  }) {
    final out = <JournalEntry>[];
    var next = after;
    var more = false;
    for (var i = _firstAfter(after); i < _entries.length; i++) {
      final e = _entries[i];
      if (out.length >= limit) {
        more = true;
        break;
      }
      next = e.seq;
      if (onlyOrigin != null && e.rec.originDeviceId != onlyOrigin) continue;
      if (excludeOrigin != null && e.rec.originDeviceId == excludeOrigin) {
        continue;
      }
      out.add(e);
    }
    return JournalPage(out, next, more);
  }

  // ---- original image files, named by their SHA-256 ----

  File blobFile(String sha) => File('${_blobDir.path}$_sep$sha');

  Future<bool> hasBlob(String sha) =>
      isSha256Hex(sha) ? blobFile(sha).exists() : Future.value(false);

  /// Stores the exact bytes and returns their hash. Nothing is re-encoded.
  Future<String> storeBlob(List<int> bytes) async {
    final sha = sha256Hex(bytes);
    await putBlob(sha, bytes);
    return sha;
  }

  Future<void> putBlob(String sha, List<int> bytes) async {
    if (!isSha256Hex(sha) || sha256Hex(bytes) != sha) {
      throw const FormatException('image hash mismatch');
    }
    final f = blobFile(sha);
    if (await f.exists()) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  Future<Uint8List?> getBlob(String sha) async {
    if (!isSha256Hex(sha)) return null;
    final f = blobFile(sha);
    return await f.exists() ? await f.readAsBytes() : null;
  }
}
