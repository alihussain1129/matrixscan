import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/history/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRepository extends HistoryRepository {
  _MemoryRepository(this.items);

  List<HistoryEntry> items;

  @override
  Future<List<HistoryEntry>> loadAll() async => List.of(items);

  @override
  Future<void> setPinned(String id, bool pinned) async {
    items = [
      for (final e in items) e.id == id ? e.copyWith(pinned: pinned) : e,
    ];
  }

  @override
  Future<void> delete(String id) async {
    items = [
      for (final e in items)
        if (e.id != id) e,
    ];
  }
}

HistoryEntry _entry(String id, String text, {bool pinned = false}) =>
    HistoryEntry(
      id: id,
      kind: HistoryKind.barcode,
      source: HistorySource.live,
      text: text,
      createdAt: DateTime.now(),
      format: 'Data Matrix',
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
  testWidgets('tapping a scan opens details and Copy copies the value', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    final repo = _MemoryRepository([_entry('1', 'LOT-4471-DM')]);
    await _pump(tester, repo);

    await tester.tap(find.text('LOT-4471-DM'));
    await _settle(tester);

    expect(find.text('Scan details'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await _settle(tester);

    expect(copied, 'LOT-4471-DM');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('Pin stores the pin and the button becomes Unpin', (
    tester,
  ) async {
    final repo = _MemoryRepository([_entry('1', 'LOT-4471-DM')]);
    await _pump(tester, repo);

    await tester.tap(find.text('LOT-4471-DM'));
    await _settle(tester);
    await tester.tap(find.text('Pin'));
    await _settle(tester);

    expect(repo.items.first.pinned, isTrue);
    expect(find.text('Unpin'), findsOneWidget);
  });

  testWidgets('Delete asks first, then removes the scan', (tester) async {
    final repo = _MemoryRepository([_entry('1', 'LOT-4471-DM')]);
    await _pump(tester, repo);

    await tester.tap(find.text('LOT-4471-DM'));
    await _settle(tester);
    await tester.tap(find.text('Delete'));
    await _settle(tester);

    expect(find.text('Delete this scan?'), findsOneWidget);
    expect(repo.items.length, 1);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await _settle(tester);

    expect(repo.items, isEmpty);
    expect(find.text('No scans yet'), findsOneWidget);
  });

  testWidgets('a pinned scan is listed above newer unpinned ones', (
    tester,
  ) async {
    final repo = _MemoryRepository([
      _entry('2', 'NEWER-SCAN'),
      _entry('1', 'OLDER-PINNED', pinned: true),
    ]);
    await _pump(tester, repo);

    final pinnedTop = tester.getTopLeft(find.text('OLDER-PINNED')).dy;
    final newerTop = tester.getTopLeft(find.text('NEWER-SCAN')).dy;
    expect(pinnedTop, lessThan(newerTop));
  });
}
