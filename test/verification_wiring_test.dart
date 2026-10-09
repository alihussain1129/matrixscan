import 'dart:convert';
import 'dart:io';

import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/scanner/connected_scan_result_card.dart';
import 'package:exalted/ffi/decode_result.dart';
import 'package:exalted/verify/open_food_facts_source.dart';
import 'package:exalted/verify/verification_engine.dart';
import 'package:exalted/verify/verification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _found = jsonEncode({
  'status': 1,
  'code': '4006381333931',
  'product': {
    'code': '4006381333931',
    'product_name': 'Test Biscuit',
    'last_modified_t': 1700000000,
  },
});

Directory _tmp() {
  final dir = Directory.systemTemp.createTempSync('exalted_verify_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir;
}

DecodedBarcode _barcode(String text) => DecodedBarcode(
  text: text,
  kind: BarcodeKind.dataMatrix,
  corners: const [Offset.zero, Offset.zero, Offset.zero, Offset.zero],
  decodeMicros: 1000,
  frameWidth: 640,
  frameHeight: 480,
);

class _MemStore extends VerificationSettingsStore {
  _MemStore(this.ids);
  final Set<String> ids;

  @override
  Future<Set<String>> load() async => {...ids};

  @override
  Future<void> save(Set<String> next) async {}
}

void main() {
  test('the store saves and reloads the allowed sources', () async {
    final dir = _tmp();
    final store = VerificationSettingsStore(directory: () async => dir);
    expect(await store.load(), isEmpty);
    await store.save({'openfoodfacts'});
    expect(
      await VerificationSettingsStore(directory: () async => dir).load(),
      {'openfoodfacts'},
    );
  });

  test('unknown source IDs in the file are ignored', () async {
    final dir = _tmp();
    File('${dir.path}${Platform.pathSeparator}verification_settings.json')
        .writeAsStringSync(jsonEncode({'allowed': ['openfoodfacts', 'evil']}));
    final store = VerificationSettingsStore(directory: () async => dir);
    expect(await store.load(), {'openfoodfacts'});
  });

  test('an unreadable file means nothing is allowed', () async {
    final dir = _tmp();
    File('${dir.path}${Platform.pathSeparator}verification_settings.json')
        .writeAsStringSync('{not json');
    final store = VerificationSettingsStore(directory: () async => dir);
    expect(await store.load(), isEmpty);
  });

  test('lookups are off by default and a switch persists', () async {
    final dir = _tmp();
    final store = VerificationSettingsStore(directory: () async => dir);
    final c1 = ProviderContainer(
      overrides: [verificationStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c1.dispose);
    expect(c1.read(allowedSourcesProvider), isEmpty);

    final n1 = c1.read(allowedSourcesProvider.notifier);
    await n1.setAllowed('evil', true);
    expect(c1.read(allowedSourcesProvider), isEmpty);
    await n1.setAllowed('openfoodfacts', true);
    expect(c1.read(allowedSourcesProvider), {'openfoodfacts'});

    final c2 = ProviderContainer(
      overrides: [verificationStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c2.dispose);
    expect(c2.read(allowedSourcesProvider), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(c2.read(allowedSourcesProvider), {'openfoodfacts'});

    await c2.read(allowedSourcesProvider.notifier).setAllowed('openfoodfacts', false);
    expect(c2.read(allowedSourcesProvider), isEmpty);
  });

  Future<int> pumpCard(WidgetTester tester, {required bool allowed}) async {
    final memStore = _MemStore(allowed ? {'openfoodfacts'} : <String>{});
    var calls = 0;
    final engine = VerificationEngine([
      OpenFoodFactsSource(
        fetch: (u) async {
          calls++;
          return HttpReply(200, _found);
        },
      ),
    ]);
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verificationStoreProvider.overrideWithValue(memStore),
          verificationEngineProvider.overrideWithValue(engine),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: ConnectedScanResultCard(
                barcode: _barcode('(01)04006381333931(17)270924(10)ABC123'),
                onCopy: () {},
                onScanAgain: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    return calls;
  }

  testWidgets('with the switch off, no lookup is made', (tester) async {
    final calls = await pumpCard(tester, allowed: false);
    expect(calls, 0);
    expect(find.text('Test Biscuit'), findsNothing);
  });

  testWidgets('with the switch on, the lookup result appears', (tester) async {
    await pumpCard(tester, allowed: true);
    expect(find.text('Test Biscuit'), findsOneWidget);
  });
}