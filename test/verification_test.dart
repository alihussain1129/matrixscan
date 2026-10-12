import 'dart:convert';
import 'dart:io';

import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/scanner/verified_interpretation_view.dart';
import 'package:exalted/interpret/default_registry.dart';
import 'package:exalted/interpret/emv_interpreter.dart';
import 'package:exalted/interpret/interpreter.dart';
import 'package:exalted/interpret/scan_field.dart';
import 'package:exalted/verify/open_food_facts_source.dart';
import 'package:exalted/verify/structural_source.dart';
import 'package:exalted/verify/verification.dart';
import 'package:exalted/verify/verification_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _reg = defaultInterpreterRegistry();
Interpretation _i(String raw) => _reg.interpret(
  ScanPayload(raw: raw, symbology: 'Data Matrix', source: 'live'),
);

ScanField _f(Interpretation i, String label) =>
    i.allFields.firstWhere((f) => f.label == label);

const _gs1 = '(01)04006381333931(17)270924(10)ABC123(21)XYZ789';
const _allow = {'openfoodfacts'};

final _found = jsonEncode({
  'status': 1,
  'code': '4006381333931',
  'product': {
    'code': '4006381333931',
    'product_name': 'Test Biscuit',
    'brands': 'Acme',
    'quantity': '200 g',
    'allergens_tags': ['en:gluten', 'en:milk'],
    'nutriments': {'sugars_100g': 12.5},
    'last_modified_t': 1700000000,
  },
});

class _Fake implements VerificationSource {
  _Fake(this.info, this.claims);
  @override
  final SourceInfo info;
  final List<Claim> claims;
  @override
  bool appliesTo(Interpretation i) => true;
  @override
  Future<SourceResult> check(Interpretation i) async => SourceResult(
    info: info,
    checkedAt: DateTime(2026, 10, 10),
    claims: claims,
  );
}

String _t(String id, String v) =>
    '$id${utf8.encode(v).length.toString().padLeft(2, '0')}$v';

void main() {
  test('GTIN check digit routine', () {
    expect(gtinCheckOk('04006381333931'), isTrue);
    expect(gtinCheckOk('08976543211234'), isFalse);
    expect(gtinCheckOk('12345'), isFalse);
  });

  test('a found record enriches but is never "Verified"', () async {
    final uris = <Uri>[];
    final engine = VerificationEngine([
      OpenFoodFactsSource(
        fetch: (u) async {
          uris.add(u);
          return HttpReply(200, _found);
        },
      ),
    ]);
    final base = _i(_gs1);
    final out = applyVerification(
      base,
      await engine.verify(base, allowedSources: _allow),
    );

    final name = _f(out, 'Product name');
    expect(name.value, 'Test Biscuit');
    expect(name.origin, FieldOrigin.external);
    expect(name.updatedAt, isNotNull);
    expect(_f(out, 'Allergens (as listed in record)').value, 'gluten, milk');
    expect(_f(out, 'Sugars').unit, 'g per 100 g');
    expect(_f(out, 'Record exists').value, 'Record found');
    expect(
      out.allFields.any((f) => f.verification == FieldVerification.verified),
      isFalse,
    );
    expect(_f(out, 'Open Food Facts').note, contains('Not an authoritative'));

    final sent = uris.single.toString();
    expect(sent, contains('4006381333931'));
    expect(sent, isNot(contains('ABC123')));
    expect(sent, isNot(contains('XYZ789')));
  });

  test('without consent nothing is sent and the source is listed', () async {
    final engine = VerificationEngine([
      OpenFoodFactsSource(fetch: (u) async => throw StateError('called')),
    ]);
    final base = _i(_gs1);
    final report = await engine.verify(base);
    expect(report.results, isEmpty);
    final out = applyVerification(base, report);
    final src = _f(out, 'Open Food Facts');
    expect(src.presence, FieldPresence.unavailable);
    expect(src.note, contains('Not checked'));
    expect(src.note, contains('GTIN only'));
  });

  test('not found does not call the code invalid', () async {
    final engine = VerificationEngine([
      OpenFoodFactsSource(
        fetch: (u) async => HttpReply(
          404,
          jsonEncode({'status': 0, 'status_verbose': 'product not found'}),
        ),
      ),
    ]);
    final base = _i(_gs1);
    final out = applyVerification(
      base,
      await engine.verify(base, allowedSources: _allow),
    );
    final c = _f(out, 'Record exists');
    expect(c.value, 'Not found');
    expect(c.note, contains('does not mean'));
  });

  test('a network failure is Source unavailable', () async {
    final engine = VerificationEngine([
      OpenFoodFactsSource(
        fetch: (u) async => throw const SocketException('offline'),
      ),
    ]);
    final base = _i(_gs1);
    final out = applyVerification(
      base,
      await engine.verify(base, allowedSources: _allow),
    );
    expect(_f(out, 'Source check').value, 'Source unavailable');
    expect(_f(out, 'Open Food Facts').value, 'Source unavailable');
  });

  test('an unreadable reply is Unable to verify', () async {
    final engine = VerificationEngine([
      OpenFoodFactsSource(fetch: (u) async => const HttpReply(200, '<html>')),
    ]);
    final base = _i(_gs1);
    final out = applyVerification(
      base,
      await engine.verify(base, allowedSources: _allow),
    );
    expect(_f(out, 'Record exists').value, 'Unable to verify');
  });

  test('unexpected HTTP status cannot return product data', () async {
    final result = await OpenFoodFactsSource(
      fetch: (u) async => HttpReply(503, _found),
    ).check(_i(_gs1));

    expect(result.fields, isEmpty);
    expect(
      result.claims.any((c) => (c.detail?.contains('HTTP 503') ?? false)),
      isTrue,
    );
  });

  test('mismatched product GTIN cannot enrich the scanned code', () async {
    final body = jsonDecode(_found) as Map<String, dynamic>;
    final product = body['product'] as Map<String, dynamic>;
    product['code'] = '5901234123457';

    final result = await OpenFoodFactsSource(
      fetch: (u) async => HttpReply(200, jsonEncode(body)),
    ).check(_i(_gs1));

    expect(result.fields, isEmpty);
    expect(
      result.claims.any((c) => c.status == VerificationStatus.mismatch),
      isTrue,
    );
    expect(
      result.claims.any((c) => c.status == VerificationStatus.unableToVerify),
      isTrue,
    );
  });

  test('missing product GTIN cannot enrich the scanned code', () async {
    final body = jsonDecode(_found) as Map<String, dynamic>;
    final product = body['product'] as Map<String, dynamic>;
    product.remove('code');

    final result = await OpenFoodFactsSource(
      fetch: (u) async => HttpReply(200, jsonEncode(body)),
    ).check(_i(_gs1));

    expect(result.fields, isEmpty);
    expect(
      result.claims.any((c) => c.status == VerificationStatus.unableToVerify),
      isTrue,
    );
  });

  test('payment QR data is never sent to an online source', () async {
    var calls = 0;
    final engine = VerificationEngine([
      OpenFoodFactsSource(
        fetch: (u) async {
          calls++;
          return HttpReply(200, _found);
        },
      ),
    ]);
    final body = _t('00', '01') + _t('59', 'Shop') + _t('58', 'PK');
    final pre = '${body}6304';
    final base = _i(pre + emvCrc16Hex(pre));
    final report = await engine.verify(base, allowedSources: _allow);
    expect(calls, 0);
    expect(report.results, isEmpty);
    expect(report.notChecked, isEmpty);
  });

  test('two sources that disagree are reported as a conflict', () async {
    SourceInfo info(String id) =>
        SourceInfo(id: id, name: id, kind: SourceKind.industry);
    final engine = VerificationEngine([
      _Fake(info('A'), const [
        Claim(
          aspect: 'Product name in record',
          status: VerificationStatus.recordFound,
          value: 'Biscuit',
        ),
      ]),
      _Fake(info('B'), const [
        Claim(
          aspect: 'Product name in record',
          status: VerificationStatus.recordFound,
          value: 'Crackers',
        ),
      ]),
    ]);
    final base = _i(_gs1);
    final report = await engine.verify(base);
    expect(report.conflicts, hasLength(1));
    final out = applyVerification(base, report);
    expect(out.warnings.any((w) => w.contains('Conflict')), isTrue);
  });

  test('only authoritative sources may report Verified', () async {
    const claim = Claim(
      aspect: 'Registration',
      status: VerificationStatus.verified,
    );
    const community = SourceInfo(
      id: 'c',
      name: 'C',
      kind: SourceKind.community,
    );
    const official = SourceInfo(
      id: 'o',
      name: 'O',
      kind: SourceKind.official,
      authoritative: true,
    );
    final engine = VerificationEngine([
      _Fake(community, const [claim]),
      _Fake(official, const [claim]),
    ]);
    final report = await engine.verify(_i(_gs1));
    expect(
      report.results[0].claims.single.status,
      VerificationStatus.recordFound,
    );
    expect(report.results[1].claims.single.status, VerificationStatus.verified);
  });

  test('local checks flag an invalid GTIN and skip online lookup', () async {
    var calls = 0;
    final engine = VerificationEngine([
      StructuralSource(),
      OpenFoodFactsSource(
        fetch: (u) async {
          calls++;
          return HttpReply(200, _found);
        },
      ),
    ]);
    final base = _i('(01)08976543211234(17)270924');
    final out = applyVerification(
      base,
      await engine.verify(base, allowedSources: _allow),
    );
    expect(calls, 0);
    final claim = out
        .section('verification')!
        .fields
        .firstWhere((f) => f.label == 'GTIN');
    expect(claim.value, 'Invalid format');
    expect(claim.validation, FieldValidation.invalid);
    expect(out.warnings.any((w) => w.contains('Invalid format')), isTrue);
  });

  test(
    'verification sections come before the raw payload, which is kept',
    () async {
      final engine = VerificationEngine([StructuralSource()]);
      final base = _i(_gs1);
      final out = applyVerification(base, await engine.verify(base));
      final ids = out.sections.map((s) => s.id).toList();
      expect(ids.indexOf('verification'), lessThan(ids.indexOf('raw')));
      expect(ids.indexOf('provenance'), lessThan(ids.indexOf('raw')));
      expect(_f(out, 'Raw decoded data').value, _gs1);
      expect(_f(out, 'GTIN').value, isNotNull);
    },
  );

  test('GS1-style URL sends only its valid GTIN to Open Food Facts', () async {
    const raw = 'https://example.com/01/09521207311511/21/1234ABDE1235';

    final base = _reg.interpret(
      ScanPayload(raw: raw, symbology: 'QR Code', source: 'test'),
    );

    Uri? requestedUri;
    final source = OpenFoodFactsSource(
      fetch: (uri) async {
        requestedUri = uri;
        return const HttpReply(404, '{"status":0}');
      },
    );

    expect(base.interpreterId, 'url');
    expect(source.appliesTo(base), isTrue);

    await source.check(base);

    expect(requestedUri, isNotNull);
    expect(requestedUri!.host, 'world.openfoodfacts.org');
    expect(requestedUri!.path, '/api/v2/product/9521207311511');
    expect(requestedUri.toString(), isNot(contains('1234ABDE1235')));
    expect(requestedUri.toString(), isNot(contains('example.com')));
  });
  Future<void> pumpView(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('without a verifier the view shows no lookup results', (
    tester,
  ) async {
    await pumpView(
      tester,
      VerifiedInterpretationView(interpretation: _i(_gs1)),
    );
    expect(find.text('Test Biscuit'), findsNothing);
    expect(find.text('Verification results'), findsNothing);
  });

  testWidgets('with consent the lookup results appear after the checks', (
    tester,
  ) async {
    final engine = VerificationEngine([
      OpenFoodFactsSource(fetch: (u) async => HttpReply(200, _found)),
    ]);
    await pumpView(
      tester,
      VerifiedInterpretationView(
        interpretation: _i(_gs1),
        verifier: engine,
        allowedSources: _allow,
      ),
    );
    expect(find.text('Test Biscuit'), findsOneWidget);
    expect(find.text('Verification results'), findsOneWidget);
  });
}
