import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_item_tile.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/history/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository extends HistoryRepository {
  _FakeRepository(this.items);

  final List<HistoryEntry> items;

  @override
  Future<List<HistoryEntry>> loadAll() async => items;
}

Future<void> _pump(WidgetTester tester, List<HistoryEntry> items) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        historyRepositoryProvider.overrideWithValue(_FakeRepository(items)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: HistoryScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('saved scans show their value, type and source', (tester) async {
    final now = DateTime.now();
    await _pump(tester, [
      HistoryEntry(
        id: '2',
        kind: HistoryKind.barcode,
        source: HistorySource.live,
        text: 'LOT-4471-DM',
        createdAt: now,
        format: 'Data Matrix',
      ),
      HistoryEntry(
        id: '1',
        kind: HistoryKind.barcode,
        source: HistorySource.gallery,
        text: 'https://example.com',
        createdAt: now.subtract(const Duration(days: 1)),
        format: 'QR Code',
        pinned: true,
      ),
    ]);

    expect(find.text('LOT-4471-DM'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);
    expect(find.textContaining('Data Matrix · Camera'), findsOneWidget);
    expect(find.textContaining('QR Code · Gallery'), findsOneWidget);
    expect(find.textContaining('Today,'), findsOneWidget);
    expect(find.textContaining('Yesterday,'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });

  testWidgets('with no saved scans the empty state shows', (tester) async {
    await _pump(tester, const []);

    expect(find.text('No scans yet'), findsOneWidget);
  });

  test('formatHistoryTime says today, yesterday, or the date', () {
    final now = DateTime(2026, 10, 8, 18, 0);
    expect(formatHistoryTime(DateTime(2026, 10, 8, 9, 5), now), 'Today, 09:05');
    expect(
      formatHistoryTime(DateTime(2026, 10, 7, 23, 59), now),
      'Yesterday, 23:59',
    );
    expect(
      formatHistoryTime(DateTime(2026, 9, 2, 14, 30), now),
      '2 Sep 2026, 14:30',
    );
  });
}
