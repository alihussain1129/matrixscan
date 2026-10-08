import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'history_entry.dart';

/// Stores scan history as JSON in the app's private storage. It never leaves
/// the device. Newest entries come first.
class HistoryRepository {
  HistoryRepository({
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
    this.maxEntries = 5000,
    this.duplicateWindow = const Duration(seconds: 30),
  }) : _directory = directory ?? getApplicationDocumentsDirectory,
       _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final int maxEntries;

  /// A repeat of the newest entry inside this window is not stored again.
  final Duration duplicateWindow;

  int _counter = 0;

  // Operations run one at a time so quick saves cannot overwrite each other.
  Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}${Platform.pathSeparator}history.json');
  }

  Future<List<HistoryEntry>> _read() async {
    final file = await _file();
    if (!await file.exists()) return <HistoryEntry>[];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return <HistoryEntry>[];
      return [for (final item in raw) ?HistoryEntry.fromJson(item)];
    } catch (_) {
      // Keep the unreadable file instead of silently overwriting it.
      try {
        await file.copy('${file.path}.corrupt');
      } catch (_) {}
      return <HistoryEntry>[];
    }
  }

  Future<void> _write(List<HistoryEntry> entries) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode([for (final e in entries) e.toJson()]),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  List<HistoryEntry> _trim(List<HistoryEntry> entries) {
    var extra = entries.length - maxEntries;
    if (extra <= 0) return entries;
    final kept = <HistoryEntry>[];
    for (final entry in entries.reversed) {
      if (extra > 0 && !entry.pinned) {
        extra--;
        continue;
      }
      kept.add(entry);
    }
    return kept.reversed.toList();
  }

  /// All entries, newest first.
  Future<List<HistoryEntry>> loadAll() => _serialized(_read);

  /// Saves a scan. Returns the stored entry, the existing entry when this is
  /// a repeat inside [duplicateWindow], or null when saving failed. It never
  /// throws, so history can never break scanning.
  Future<HistoryEntry?> add({
    required HistoryKind kind,
    required HistorySource source,
    required String text,
    String? format,
  }) {
    return _serialized<HistoryEntry?>(() async {
      if (text.isEmpty) return null;
      try {
        final entries = await _read();
        final now = _clock();
        if (entries.isNotEmpty) {
          final newest = entries.first;
          if (newest.kind == kind &&
              newest.text == text &&
              now.difference(newest.createdAt) < duplicateWindow) {
            return newest;
          }
        }
        final entry = HistoryEntry(
          id: '${now.microsecondsSinceEpoch}-${_counter++}',
          kind: kind,
          source: source,
          text: text,
          createdAt: now,
          format: format,
        );
        entries.insert(0, entry);
        await _write(_trim(entries));
        return entry;
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> setPinned(String id, bool pinned) => _serialized<void>(() async {
    final entries = await _read();
    final index = entries.indexWhere((e) => e.id == id);
    if (index < 0) return;
    entries[index] = entries[index].copyWith(pinned: pinned);
    await _write(entries);
  });

  Future<void> delete(String id) => _serialized<void>(() async {
    final entries = await _read();
    entries.removeWhere((e) => e.id == id);
    await _write(entries);
  });
}

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository();
});
