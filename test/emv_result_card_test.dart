import 'dart:convert';

import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/scanner/interpretation_view.dart';
import 'package:exalted/features/scanner/scan_result_card.dart';
import 'package:exalted/features/scanner/wifi_info_panel.dart';
import 'package:exalted/ffi/decode_result.dart';
import 'package:exalted/interpret/emv_interpreter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _t(String id, String v) =>
    '$id${utf8.encode(v).length.toString().padLeft(2, '0')}$v';

String _emv() {
  final body = _t('00', '01') +
      _t('01', '12') +
      _t('26', _t('00', 'com.example.pay') + _t('01', 'ACC-0001234567')) +
      _t('53', '586') +
      _t('54', '150.50') +
      _t('58', 'PK') +
      _t('59', 'Test Shop') +
      _t('60', 'Lahore');
  final pre = '${body}6304';
  return pre + emvCrc16Hex(pre);
}

DecodedBarcode _barcode(String text) => DecodedBarcode(
  text: text,
  kind: BarcodeKind.qrCode,
  corners: const [Offset.zero, Offset.zero, Offset.zero, Offset.zero],
  decodeMicros: 1000,
  frameWidth: 640,
  frameHeight: 480,
);

Future<void> _pump(WidgetTester tester, String text) async {
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
  testWidgets('a payment QR is shown with the interpretation view', (tester) async {
    await _pump(tester, _emv());
    expect(find.byType(InterpretationView), findsOneWidget);
    expect(find.text('Test Shop'), findsOneWidget);
    expect(find.text('PKR (Pakistani rupee)'), findsOneWidget);
  });

  testWidgets('the account identifier stays masked', (tester) async {
    await _pump(tester, _emv());
    expect(find.text('ACC-0001234567'), findsNothing);
  });

  testWidgets('plain text still uses the raw view', (tester) async {
    await _pump(tester, 'LOT-4471-DM');
    expect(find.byType(InterpretationView), findsNothing);
    expect(find.byType(WifiInfoPanel), findsNothing);
    expect(find.text('LOT-4471-DM'), findsOneWidget);
  });
}