import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_export.dart';
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

HistoryEntry _entry(
  String id,
  String text,
  String format, {
  HistorySource source = HistorySource.live,
  bool pinned = false,
}) => HistoryEntry(
  id: id,
  kind: HistoryKind.barcode,
  source: source,
  text: text,
  createdAt: DateTime.utc(2026, 10, 8, 9, 5),
  format: format,
  pinned: pinned,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _pump(
  WidgetTester tester,
  List<HistoryEntry> items, {
  Future<void> Function(List<HistoryEntry>)? exporter,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        historyRepositoryProvider.overrideWithValue(_FakeRepository(items)),
        if (exporter != null)
          historyExporterProvider.overrideWithValue(exporter),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: HistoryScreen()),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  final dm = _entry('2', 'LOT-4471-DM', 'Data Matrix');
  final qr = _entry(
    '1',
    'https://example.com',
    'QR Code',
    source: HistorySource.gallery,
  );

  test('filterHistory matches value, type and source, ignoring case', () {
    final all = [dm, qr];
    expect(filterHistory(all, ''), all);
    expect(filterHistory(all, '   '), all);
    expect(filterHistory(all, 'lot-4471'), [dm]);
    expect(filterHistory(all, 'QR'), [qr]);
    expect(filterHistory(all, 'data matrix'), [dm]);
    expect(filterHistory(all, 'gallery'), [qr]);
    expect(filterHistory(all, 'nothing like this'), isEmpty);
  });

  test('historyToCsv writes a header, quotes cells and blocks formulas', () {
    final csv = historyToCsv([
      dm,
      _entry('3', 'a,"b"\nc', 'QR Code'),
      _entry('4', '=1+1', 'QR Code', pinned: true),
    ]);

    expect(csv.startsWith('time,type,source,value,pinned\r\n'), isTrue);
    expect(
      csv,
      contains('2026-10-08T09:05:00.000Z,Data Matrix,Camera,LOT-4471-DM,false'),
    );
    expect(csv, contains('"a,""b""\nc"'));
    expect(csv, contains("'=1+1,true"));
  });

  testWidgets('typing in the search box filters the list', (tester) async {
    await _pump(tester, [dm, qr]);

    expect(find.text('LOT-4471-DM'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'qr');
    await _settle(tester);

    expect(find.text('LOT-4471-DM'), findsNothing);
    expect(find.text('https://example.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await _settle(tester);

    expect(find.textContaining('No scans match'), findsOneWidget);
  });

  testWidgets('Export CSV sends only the scans currently shown', (
    tester,
  ) async {
    List<HistoryEntry>? exported;
    await _pump(tester, [
      dm,
      qr,
    ], exporter: (entries) async => exported = entries);

    await tester.enterText(find.byType(TextField), 'qr');
    await _settle(tester);
    await tester.tap(find.byTooltip('Export CSV'));
    await _settle(tester);

    expect(exported, [qr]);
  });
}
