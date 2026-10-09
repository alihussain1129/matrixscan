import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/scanner/gs1_info_panel.dart';
import 'package:exalted/gs1/gs1_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpPanel(WidgetTester tester, String text, DateTime now) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Gs1InfoPanel(result: parseGs1(text)!, now: now),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('expiry status (fixed clock 2026-10-09)', () {
    final now = DateTime(2026, 10, 9);

    testWidgets('past date is Expired', (tester) async {
      await _pumpPanel(tester, '(17)200101', now);
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('within 30 days is Near expiry', (tester) async {
      await _pumpPanel(tester, '(17)261015', now);
      expect(find.text('Near expiry (within 30 days)'), findsOneWidget);
    });

    testWidgets('far future is Not expired', (tester) async {
      await _pumpPanel(tester, '(17)270924', now);
      expect(find.text('Not expired'), findsOneWidget);
    });

    testWidgets('an invalid date gets no status', (tester) async {
      await _pumpPanel(tester, '(17)271332', now);
      expect(find.text('Expired'), findsNothing);
      expect(find.text('Not expired'), findsNothing);
      expect(find.text('not a valid date (YYMMDD)'), findsOneWidget);
    });
  });
}