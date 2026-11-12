import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_item_tile.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/history/history_screen.dart';
import 'package:exalted/features/ocr/models/ocr_record.dart';
import 'package:exalted/features/ocr/services/ocr_history_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository extends HistoryRepository {
  _FakeRepository(this.items);

  final List<HistoryEntry> items;

  @override
  Future<List<HistoryEntry>> loadAll() async => items;
}

class _CountingOcrRepository extends OcrHistoryRepository {
  int loads = 0;

  @override
  Future<List<OcrRecord>> loadAll() async {
    loads++;
    return const [];
  }
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

  testWidgets('OCR History refreshes on tab selection, not search rebuilds', (
    tester,
  ) async {
    final repo = _CountingOcrRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyRepositoryProvider.overrideWithValue(
            _FakeRepository(const []),
          ),
          ocrHistoryRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: HistoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.loads, 1);

    await tester.tap(find.text('OCR DOCUMENTS'));
    await tester.pumpAndSettle();
    expect(repo.loads, 2);

    await tester.enterText(find.byType(TextField), 'freshness');
    await tester.pump();
    expect(repo.loads, 2);
  });

  testWidgets('decoder history reveals older records in 100 record pages', (
    tester,
  ) async {
    final entries = [
      for (var i = 0; i < 120; i++)
        HistoryEntry(
          id: '$i',
          kind: HistoryKind.barcode,
          source: HistorySource.live,
          text: 'SCAN-$i',
          createdAt: DateTime.now().subtract(Duration(minutes: i)),
          format: 'Data Matrix',
        ),
    ];
    await _pump(tester, entries);

    expect(find.text('SCAN-0'), findsOneWidget);
    expect(find.text('SCAN-99'), findsNothing);
    expect(find.text('SCAN-100'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Load next 100 (20 remaining)'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Load next 100 (20 remaining)'), findsOneWidget);

    await tester.tap(find.text('Load next 100 (20 remaining)'));
    await tester.pump();

    expect(find.text('SCAN-100'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('SCAN-119'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('SCAN-119'), findsOneWidget);
    expect(find.textContaining('Load next 100'), findsNothing);
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
