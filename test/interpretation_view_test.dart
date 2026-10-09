import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/scanner/interpretation_view.dart';
import 'package:exalted/interpret/default_registry.dart';
import 'package:exalted/interpret/interpreter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, String raw) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final i = defaultInterpreterRegistry(clock: () => DateTime(2026, 10, 9))
      .interpret(ScanPayload(raw: raw, symbology: 'Data Matrix', source: 'live'));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(child: InterpretationView(interpretation: i)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  const gs1 = '(01)04006381333931(17)270924(10)ABC123(21)XYZ789';

  testWidgets('GS1 fields, encoded value and warning are shown', (tester) async {
    await _pump(tester, gs1);
    expect(find.text('GTIN'), findsOneWidget);
    expect(find.text('04006381333931'), findsOneWidget);
    expect(find.text('2027-09-24'), findsOneWidget);
    expect(find.text('Encoded: 270924'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.textContaining('not confirmed as GS1'), findsOneWidget);
  });

  testWidgets('absent fields say so', (tester) async {
    await _pump(tester, '(01)04006381333931');
    expect(find.text('Not present in barcode'), findsNWidgets(3));
  });

  testWidgets('an invalid GTIN shows its reason', (tester) async {
    await _pump(tester, '(01)08976543211234(17)270924');
    expect(find.text('Invalid GTIN Check Digit (expected 9)'), findsOneWidget);
  });

  testWidgets('raw and technical sections open on demand', (tester) async {
    await _pump(tester, gs1);
    expect(find.text('Raw decoded data'), findsNothing);
    await tester.tap(find.text('Raw payload'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Raw decoded data'), findsOneWidget);
  });

  testWidgets('search keeps only matching fields', (tester) async {
    await _pump(tester, gs1);
    await tester.enterText(find.byType(TextField), 'serial');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Serial number'), findsOneWidget);
    expect(find.text('GTIN'), findsNothing);
  });

  testWidgets('sensitive values are masked, revealable and copyable', (
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
    await _pump(tester, 'WIFI:S:CafeNet;T:WPA;P:s3cret-pass;;');
    expect(find.text('s3cret-pass'), findsNothing);
    expect(find.text('\u2022' * 8), findsOneWidget);

    await tester.tap(find.byTooltip('Copy Password'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(copied, 's3cret-pass');

    await tester.tap(find.byTooltip('Reveal Password'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('s3cret-pass'), findsOneWidget);
  });
}