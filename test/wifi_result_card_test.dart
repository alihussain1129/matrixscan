import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/scanner/scan_result_card.dart';
import 'package:exalted/features/scanner/wifi_info_panel.dart';
import 'package:exalted/ffi/decode_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

DecodedBarcode _barcode(String text) => DecodedBarcode(
  text: text,
  kind: BarcodeKind.qrCode,
  corners: const [Offset.zero, Offset.zero, Offset.zero, Offset.zero],
  decodeMicros: 1000,
  frameWidth: 640,
  frameHeight: 480,
);

Future<void> _pump(WidgetTester tester, String text) async {
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
  const wifiText = 'WIFI:S:CafeNet;T:WPA;P:s3cret-pass;;';

  testWidgets('a Wi-Fi code shows network and security, password hidden', (
    tester,
  ) async {
    await _pump(tester, wifiText);

    expect(find.byType(WifiInfoPanel), findsOneWidget);
    expect(find.text('CafeNet'), findsOneWidget);
    expect(find.text('WPA/WPA2'), findsOneWidget);
    expect(find.text('s3cret-pass'), findsNothing);
    expect(find.text(wifiText), findsNothing);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('s3cret-pass'), findsOneWidget);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('Copy password copies only the password', (tester) async {
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
    await _pump(tester, wifiText);

    await tester.tap(find.text('Copy password'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(copied, 's3cret-pass');
    expect(find.text('Password copied'), findsOneWidget);
  });

  testWidgets('an open network shows no password controls', (tester) async {
    await _pump(tester, 'WIFI:S:Guest;T:nopass;;');

    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Open (no password)'), findsOneWidget);
    expect(find.text('Copy password'), findsNothing);
    expect(find.byTooltip('Show password'), findsNothing);
  });

  testWidgets('other codes still show their raw text, with no Wi-Fi panel', (
    tester,
  ) async {
    await _pump(tester, 'LOT-4471-DM');

    expect(find.byType(WifiInfoPanel), findsNothing);
    expect(find.text('LOT-4471-DM'), findsOneWidget);
  });
}
