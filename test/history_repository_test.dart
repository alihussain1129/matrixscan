import 'dart:io';

import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  var now = DateTime(2026, 10, 8, 12);

  HistoryRepository make({int maxEntries = 5000}) => HistoryRepository(
    directory: () async => dir,
    clock: () => now,
    maxEntries: maxEntries,
  );

  Future<HistoryEntry?> save(HistoryRepository repo, String text) => repo.add(
    kind: HistoryKind.barcode,
    source: HistorySource.live,
    text: text,
    format: 'QR Code',
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('exalted_history_test');
    now = DateTime(2026, 10, 8, 12);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('saves entries and loads them newest first', () async {
    final repo = make();
    await save(repo, 'A');
    now = now.add(const Duration(minutes: 1));
    await repo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.gallery,
      text: 'B',
      format: 'Data Matrix',
    );
    final all = await repo.loadAll();
    expect(all.map((e) => e.text), ['B', 'A']);
    expect(all.first.format, 'Data Matrix');
    expect(all.first.source, HistorySource.gallery);
  });

  test(
    'a repeat of the newest scan inside the window is stored once',
    () async {
      final repo = make();
      final first = await save(repo, 'A');
      now = now.add(const Duration(seconds: 10));
      final again = await save(repo, 'A');
      expect(again?.id, first?.id);
      expect((await repo.loadAll()).length, 1);

      now = now.add(const Duration(seconds: 40));
      await save(repo, 'A');
      expect((await repo.loadAll()).length, 2);
    },
  );

  test('pin and delete', () async {
    final repo = make();
    final a = await save(repo, 'A');
    now = now.add(const Duration(minutes: 1));
    final b = await save(repo, 'B');
    await repo.setPinned(a!.id, true);
    var all = await repo.loadAll();
    expect(all.firstWhere((e) => e.id == a.id).pinned, isTrue);
    await repo.delete(b!.id);
    all = await repo.loadAll();
    expect(all.map((e) => e.text), ['A']);
  });

  test('a corrupt file loads as empty and is backed up', () async {
    final path = '${dir.path}${Platform.pathSeparator}history.json';
    await File(path).writeAsString('{not json');
    final repo = make();
    expect(await repo.loadAll(), isEmpty);
    expect(File('$path.corrupt').existsSync(), isTrue);
  });

  test('trimming drops the oldest unpinned entries and keeps pinned', () async {
    final repo = make(maxEntries: 2);
    final a = await save(repo, 'A');
    await repo.setPinned(a!.id, true);
    now = now.add(const Duration(minutes: 1));
    await save(repo, 'B');
    now = now.add(const Duration(minutes: 1));
    await save(repo, 'C');
    final all = await repo.loadAll();
    expect(all.map((e) => e.text), ['C', 'A']);
  });
}
