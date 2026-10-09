import 'dart:io';

import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/history/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRepository extends HistoryRepository {
  _MemoryRepository(this.items);

  List<HistoryEntry> items;

  @override
  Future<List<HistoryEntry>> loadAll() async => List.of(items);

  @override
  Future<void> clear() async {
    items = [];
  }
}

HistoryEntry _entry(String id, String text, {bool pinned = false}) =>
    HistoryEntry(
      id: id,
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: text,
      createdAt: DateTime.now(),
      format: 'QR Code',
      pinned: pinned,
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _pump(WidgetTester tester, _MemoryRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [historyRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: HistoryScreen()),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  test('clear removes every entry, pinned ones included', () async {
    final dir = Directory.systemTemp.createTempSync('exalted_clear_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = HistoryRepository(directory: () async => dir);

    final a = await repo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: 'A',
    );
    await repo.add(
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: 'B',
    );
    await repo.setPinned(a!.id, true);
    expect((await repo.loadAll()).length, 2);

    await repo.clear();

    expect(await repo.loadAll(), isEmpty);
  });

  testWidgets('Delete all asks first, and Cancel keeps everything', (
    tester,
  ) async {
    final repo = _MemoryRepository([_entry('1', 'KEEP-ME', pinned: true)]);
    await _pump(tester, repo);

    await tester.tap(find.byTooltip('Delete all history'));
    await _settle(tester);

    expect(find.text('Delete all history?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    expect(repo.items.length, 1);
    expect(find.text('KEEP-ME'), findsOneWidget);
  });

  testWidgets('confirming Delete all empties History', (tester) async {
    final repo = _MemoryRepository([
      _entry('2', 'SCAN-TWO'),
      _entry('1', 'SCAN-ONE', pinned: true),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.byTooltip('Delete all history'));
    await _settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete all'),
      ),
    );
    await _settle(tester);

    expect(repo.items, isEmpty);
    expect(find.text('No scans yet'), findsOneWidget);
  });
}
