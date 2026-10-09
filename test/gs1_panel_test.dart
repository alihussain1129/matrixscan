import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/scanner/gs1_info_panel.dart';
import 'package:exalted/features/scanner/scan_result_card.dart';
import 'package:exalted/ffi/decode_result.dart';
import 'package:exalted/gs1/gs1_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DecodedBarcode _barcode(String text) => DecodedBarcode(
  text: text,
  kind: BarcodeKind.dataMatrix,
  corners: const [Offset.zero, Offset.zero, Offset.zero, Offset.zero],
  decodeMicros: 1000,
  frameWidth: 640,
  frameHeight: 480,
);

Future<void> _pumpCard(WidgetTester tester, String text) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: ScanResultCard(
            barcode: _barcode(text),
            onCopy: () {},
            onScanAgain: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

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
  const full = '(01)04006381333931(17)270924(10)ABC123(21)XYZ789';

  testWidgets('GS1 text shows its fields and the raw payload', (tester) async {
    await _pumpCard(tester, full);

    expect(find.byType(Gs1InfoPanel), findsOneWidget);
    expect(find.text('04006381333931'), findsOneWidget);
    expect(find.text('Check digit OK'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('XYZ789'), findsOneWidget);
    expect(find.text('2027-09-24'), findsOneWidget);
    expect(find.text('Encoded: 270924'), findsOneWidget);
    expect(find.text(full), findsOneWidget);
  });

  testWidgets('absent fields are reported as not present', (tester) async {
    await _pumpCard(tester, '(01)04006381333931');

    expect(find.text('Not present in barcode'), findsNWidgets(3));
  });

  testWidgets('the invalid GTIN from the phone is flagged, not approved', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      '(01)08976543211234(17)270924(10)272718(21)8760C6AEDE474',
    );

    expect(find.text('Invalid GTIN Check Digit (expected 9)'), findsOneWidget);
    expect(find.text('Check digit OK'), findsNothing);
    expect(find.text('272718'), findsOneWidget);
    expect(find.text('8760C6AEDE474'), findsOneWidget);
  });

  testWidgets('plain text and EAN-13 do not get a GS1 panel', (tester) async {
    await _pumpCard(tester, 'LOT-4471-DM');
    expect(find.byType(Gs1InfoPanel), findsNothing);
    expect(find.text('LOT-4471-DM'), findsOneWidget);
  });

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