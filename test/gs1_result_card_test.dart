import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/scanner/interpretation_view.dart';
import 'package:exalted/features/scanner/scan_result_card.dart';
import 'package:exalted/ffi/decode_result.dart';
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
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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

void main() {
  const full = '(01)04006381333931(17)270924(10)ABC123(21)XYZ789';

  testWidgets('GS1 text shows its fields, and the raw payload on demand', (
    tester,
  ) async {
    await _pumpCard(tester, full);

    expect(find.byType(InterpretationView), findsOneWidget);
    expect(find.text('04006381333931'), findsOneWidget);
    expect(find.textContaining('Check digit is valid'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('XYZ789'), findsOneWidget);
    expect(find.text('2027-09-24'), findsOneWidget);
    expect(find.text('Encoded: 270924'), findsOneWidget);

    expect(find.text(full), findsNothing);
    await tester.ensureVisible(find.text('Raw payload'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Raw payload'));
    await tester.pump(const Duration(milliseconds: 400));
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
    expect(find.textContaining('Check digit is valid'), findsNothing);
    expect(find.text('272718'), findsOneWidget);
    expect(find.text('8760C6AEDE474'), findsOneWidget);
  });

  testWidgets('plain text does not get the interpretation view', (tester) async {
    await _pumpCard(tester, 'LOT-4471-DM');
    expect(find.byType(InterpretationView), findsNothing);
    expect(find.text('LOT-4471-DM'), findsOneWidget);
  });
}