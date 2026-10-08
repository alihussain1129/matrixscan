import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/scanner/scan_result_card.dart';
import 'package:exalted/features/scanner/wifi_connector.dart';
import 'package:exalted/features/scanner/wifi_utils.dart';
import 'package:exalted/ffi/decode_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _wpa = WifiNetworkInfo(
  ssid: 'CafeNet',
  security: WifiSecurity.wpa,
  password: 's3cret-pass',
  hidden: false,
);

const _open = WifiNetworkInfo(
  ssid: 'Guest',
  security: WifiSecurity.open,
  password: '',
  hidden: false,
);

DecodedBarcode _barcode(String text) => DecodedBarcode(
  text: text,
  kind: BarcodeKind.qrCode,
  corners: const [Offset.zero, Offset.zero, Offset.zero, Offset.zero],
  decodeMicros: 1000,
  frameWidth: 640,
  frameHeight: 480,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(wifiChannelName);
  final calls = <MethodCall>[];
  String? clipboard;

  void answer(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    clipboard = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('WifiConnector', () {
    test('sends the network details and reports a saved network', () async {
      answer((call) async => 'saved');

      final result = await WifiConnector().connect(_wpa);

      expect(result.outcome, WifiConnectOutcome.saved);
      expect(calls.single.method, 'connect');
      expect(calls.single.arguments, {
        'ssid': 'CafeNet',
        'password': 's3cret-pass',
        'security': 'wpa',
        'hidden': false,
      });
    });

    test('a direct connect is reported as connecting', () async {
      answer((call) async => 'connecting');

      final result = await WifiConnector().connect(_wpa);

      expect(result.outcome, WifiConnectOutcome.connecting);
      expect(result.message, contains('CafeNet'));
    });

    test('a dismissed panel is reported as cancelled', () async {
      answer((call) async => 'cancelled');

      final result = await WifiConnector().connect(_wpa);

      expect(result.outcome, WifiConnectOutcome.cancelled);
    });

    test('manual: copies the password and opens Wi-Fi settings', () async {
      answer((call) async => call.method == 'connect' ? 'manual' : null);

      final result = await WifiConnector().connect(_wpa);

      expect(result.outcome, WifiConnectOutcome.openedSettings);
      expect(clipboard, 's3cret-pass');
      expect(calls.map((c) => c.method), ['connect', 'openWifiSettings']);
      expect(result.message, contains('Password copied'));
    });

    test('manual on an open network copies nothing', () async {
      answer((call) async => call.method == 'connect' ? 'manual' : null);

      final result = await WifiConnector().connect(_open);

      expect(result.outcome, WifiConnectOutcome.openedSettings);
      expect(clipboard, isNull);
      expect(result.message, isNot(contains('Password copied')));
    });

    test('an Android error becomes a failed result', () async {
      answer((call) async {
        throw PlatformException(code: 'bad_password', message: 'too short');
      });

      final result = await WifiConnector().connect(_wpa);

      expect(result.outcome, WifiConnectOutcome.failed);
      expect(result.message, contains('password'));
    });

    test('without the Android side it fails instead of throwing', () async {
      final result = await WifiConnector().connect(_wpa);

      expect(result.outcome, WifiConnectOutcome.failed);
    });

    test('a network that cannot be joined never reaches Android', () async {
      answer((call) async => 'saved');
      const noPassword = WifiNetworkInfo(
        ssid: 'N',
        security: WifiSecurity.wpa,
        password: '',
        hidden: false,
      );

      final result = await WifiConnector().connect(noPassword);

      expect(result.outcome, WifiConnectOutcome.failed);
      expect(calls, isEmpty);
    });
  });

  group('Connect button on the result card', () {
    Future<void> pump(
      WidgetTester tester,
      String text, {
      VoidCallback? onConnectWifi,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: ScanResultCard(
                barcode: _barcode(text),
                onCopy: () {},
                onScanAgain: () {},
                onConnectWifi: onConnectWifi,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('a joinable Wi-Fi code shows the button and it works', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        'WIFI:S:CafeNet;T:WPA;P:s3cret-pass;;',
        onConnectWifi: () => taps++,
      );

      expect(find.text('Connect to Wi-Fi'), findsOneWidget);

      await tester.tap(find.text('Connect to Wi-Fi'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(taps, 1);
    });

    testWidgets('no button when the code has no password', (tester) async {
      await pump(tester, 'WIFI:S:CafeNet;T:WPA;;', onConnectWifi: () {});

      expect(find.text('Connect to Wi-Fi'), findsNothing);
    });

    testWidgets('no button for a code that is not Wi-Fi', (tester) async {
      await pump(tester, 'LOT-4471-DM', onConnectWifi: () {});

      expect(find.text('Connect to Wi-Fi'), findsNothing);
    });

    testWidgets('no button when the caller offers no connect action', (
      tester,
    ) async {
      await pump(tester, 'WIFI:S:CafeNet;T:WPA;P:s3cret-pass;;');

      expect(find.text('Connect to Wi-Fi'), findsNothing);
    });
  });
}
