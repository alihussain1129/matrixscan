import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:exalted/interpret/default_registry.dart';
import 'package:exalted/interpret/interpreter.dart';
import 'package:exalted/verify/http_client.dart';
import 'package:exalted/verify/open_fda_ndc_source.dart';
import 'package:exalted/verify/verification.dart';
import 'package:flutter_test/flutter_test.dart';

final _registry = defaultInterpreterRegistry();
final _now = DateTime.utc(2026, 10, 10);

// Real openFDA responses saved on 2026-10-10 (see test/fixtures/openfda).
String _fixture(String name) =>
    File('test/fixtures/openfda/$name')
        .readAsStringSync()
        .replaceFirst('\uFEFF', '');

const _pregabalinUpc = '0376282569901';
const _retailUpc = '0850022941283';
// Real openFDA 404 body for "No matches found!".
const _notFoundBody =
    '{"error":{"code":"NOT_FOUND","message":"No matches found!"}}';

Interpretation _scan(String gtin14) => _registry.interpret(
  ScanPayload(
    raw: '(01)$gtin14(17)270924(10)ABC123',
    symbology: 'Data Matrix',
    source: 'live',
  ),
);

OpenFdaNdcSource _source(
  Future<HttpReply> Function(Uri) handler, [
  List<Uri>? log,
]) => OpenFdaNdcSource(
  clock: () => _now,
  fetch: (u) async {
    log?.add(u);
    return handler(u);
  },
);

String _f(SourceResult r, String label) {
  for (final f in r.fields) {
    if (f.label == label) return '${f.value}';
  }
  return '<absent>';
}

VerificationStatus _status(SourceResult r) => r.claims.single.status;

String _withCheck(String body12) {
  var s = 0;
  for (var i = 0; i < body12.length; i++) {
    s += (body12.codeUnitAt(body12.length - 1 - i) - 48) * (i.isEven ? 3 : 1);
  }
  return '$body12${(10 - s % 10) % 10}';
}

// Minimal structural mock used only for paths the real fixtures do not
// exercise (layouts, missing fields, disagreement). Not real FDA data.
Map<String, Object?> _rec(
  String upc,
  List<String> packages, {
  String? brand,
  String? strength,
}) => {
  'openfda': {
    'upc': [upc],
  },
  'packaging': [
    for (final p in packages) {'package_ndc': p},
  ],
  'brand_name': ?brand,
  if (strength != null)
    'active_ingredients': [
      {'name': 'X', 'strength': strength},
    ],
};

String _body(List<Map<String, Object?>> records) =>
    jsonEncode({'meta': {}, 'results': records});

void main() {
  group('fdaUpcKey', () {
    test('12-digit UPC-A is padded to 13 digits', () {
      expect(fdaUpcKey('376282569901'), _pregabalinUpc);
    });
    test('13-digit stays; 14-digit with leading 0 loses it', () {
      expect(fdaUpcKey(_pregabalinUpc), _pregabalinUpc);
      expect(fdaUpcKey('00376282569901'), _pregabalinUpc);
    });
    test('rejects bad characters, length, check digit, indicator, zeros', () {
      expect(fdaUpcKey('03762825699O1'), isNull);
      expect(fdaUpcKey('0376282569902'), isNull);
      expect(fdaUpcKey('12345'), isNull);
      expect(fdaUpcKey('12345670'), isNull); // EAN-8: unsupported
      expect(fdaUpcKey('10376282569908'), isNull); // non-zero indicator
      expect(fdaUpcKey('0000000000000'), isNull);
      expect(fdaUpcKey(''), isNull);
    });
  });

  group('OpenFdaNdcSource', () {
    test('is not authoritative and discloses what it sends', () {
      expect(OpenFdaNdcSource.sourceInfo.authoritative, isFalse);
      expect(OpenFdaNdcSource.sourceInfo.sendsData, isTrue);
    });

    test('appliesTo: valid GTIN yes, non-GTIN and zero code no', () {
      final s = _source((_) async => HttpReply(200, '{}'));
      expect(s.appliesTo(_scan('00376282569901')), isTrue);
      expect(s.appliesTo(_scan('00000000000000')), isFalse);
      expect(
        s.appliesTo(
          _registry.interpret(
            const ScanPayload(
              raw: 'hello',
              symbology: 'QR Code',
              source: 'live',
            ),
          ),
        ),
        isFalse,
      );
    });

    test('real record: exact UPC and package NDC match', () async {
      final calls = <Uri>[];
      final r = await _source(
        (_) async => HttpReply(200, _fixture('fda_pregabalin.json')),
        calls,
      ).check(_scan('00376282569901'));

      expect(calls.single.host, 'api.fda.gov');
      expect(
        calls.single.queryParameters['search'],
        'openfda.upc:"$_pregabalinUpc"',
      );
      expect(_status(r), VerificationStatus.recordFound);
      expect(r.claims.single.detail, contains('does not authenticate'));
      expect(r.checkedAt, _now);
      expect(_f(r, 'Package NDC'), '76282-569-90');
      expect(_f(r, 'Matched UPC'), _pregabalinUpc);
      expect(_f(r, 'Brand name'), 'Pregabalin');
    });

    test('real retail UPC (not NDC-shaped) matches by direct UPC', () async {
      final r = await _source(
        (_) async => HttpReply(200, _fixture('fda_retail.json')),
      ).check(_scan('00850022941283'));
      expect(_status(r), VerificationStatus.recordFound);
      expect(_f(r, 'Package NDC'), '<absent>');
      expect(_f(r, 'Matched UPC'), _retailUpc);
    });

    test(
      'label-level match without the package NDC shows no package',
      () async {
        final data = jsonDecode(_fixture('fda_pregabalin.json')) as Map;
        data['results'] = (data['results'] as List)
            .where(
              (r) => !((r as Map)['packaging'] as List).any(
                (p) => (p as Map)['package_ndc'] == '76282-569-90',
              ),
            )
            .toList();
        final r = await _source((_) async => HttpReply(200, jsonEncode(data)))
            .check(_scan('00376282569901'));
        expect(_status(r), VerificationStatus.recordFound);
        expect(_f(r, 'Package NDC'), '<absent>');
        expect(
          r.claims.single.detail,
          contains('none of the returned records'),
        );
      },
    );

    for (final c in const [
      ('4-4-2', '0363-6251-12'),
      ('5-3-2', '76282-569-90'),
      ('5-4-1', '76472-3009-1'),
    ]) {
      test('NDC layout ${c.$1} matches by digits', () async {
        final upc = _withCheck('03${c.$2.replaceAll('-', '')}');
        final r = await _source(
          (_) async => HttpReply(
            200,
            _body([
              _rec(upc, [c.$2]),
            ]),
          ),
        ).check(_scan('0$upc'));
        expect(_status(r), VerificationStatus.recordFound);
        expect(_f(r, 'Package NDC'), c.$2);
      });
    }

    test(
      'candidate that does not list the scanned code is a mismatch',
      () async {
        final r = await _source(
          (_) async => HttpReply(200, _fixture('fda_retail.json')),
        ).check(_scan('00376282569901'));
        expect(_status(r), VerificationStatus.mismatch);
        expect(r.fields, isEmpty);
      },
    );

    test('404 with the real no-match body is Not found', () async {
      final r = await _source((_) async => HttpReply(404, _notFoundBody))
          .check(_scan('00376282569901'));
      expect(_status(r), VerificationStatus.notFound);
    });

    test('404 with any other payload is not "not found"', () async {
      for (final body in ['', 'oops', '{"error":{"code":"OTHER"}}']) {
        final r = await _source((_) async => HttpReply(404, body))
            .check(_scan('00376282569901'));
        expect(_status(r), VerificationStatus.unableToVerify);
      }
    });

    test('429, 500 and 503 are Source unavailable', () async {
      for (final code in [429, 500, 503]) {
        final r = await _source(
          (_) async => HttpReply(code, '{"error":{"code":"SERVER_ERROR"}}'),
        ).check(_scan('00376282569901'));
        expect(_status(r), VerificationStatus.sourceUnavailable);
        expect(r.error, isNotNull);
      }
    });

    test('timeout and connection failure are Source unavailable', () async {
      final t = await _source(
        (_) => Future<HttpReply>.error(TimeoutException('t')),
      ).check(_scan('00376282569901'));
      final n = await _source(
        (_) => Future<HttpReply>.error(const SocketException('down')),
      ).check(_scan('00376282569901'));
      expect(_status(t), VerificationStatus.sourceUnavailable);
      expect(_status(n), VerificationStatus.sourceUnavailable);
    });

    test(
      'malformed JSON, wrong structure and empty results are inconclusive',
      () async {
        for (final body in [
          'not json',
          '{"results":"x"}',
          '{"results":[]}',
          '[]',
        ]) {
          final r = await _source((_) async => HttpReply(200, body))
              .check(_scan('00376282569901'));
          expect(_status(r), VerificationStatus.unableToVerify);
          expect(r.fields, isEmpty);
        }
      },
    );

    test('invalid or zero codes make no request', () async {
      final calls = <Uri>[];
      final s = _source((_) async => HttpReply(200, '{}'), calls);
      for (final g in ['00000000000000', '00376282569902']) {
        final r = await s.check(_scan(g));
        expect(_status(r), VerificationStatus.unableToVerify);
      }
      expect(calls, isEmpty);
    });

    test('missing optional fields are not invented', () async {
      final r = await _source(
        (_) async => HttpReply(
          200,
          _body([
            _rec(_retailUpc, ['76472-3009-1']),
          ]),
        ),
      ).check(_scan('00850022941283'));
      expect(_status(r), VerificationStatus.recordFound);
      for (final l in [
        'Brand name',
        'Generic name',
        'Active ingredients',
        'Labeler',
        'Dosage form',
      ]) {
        expect(_f(r, l), '<absent>', reason: l);
      }
      expect(_f(r, 'Matched UPC'), _retailUpc);
    });

    test(
      'records that disagree contribute only the fields they share',
      () async {
        final r = await _source(
          (_) async => HttpReply(
            200,
            _body([
              _rec(_retailUpc, ['1-1-1'], brand: 'Same', strength: '10 mg'),
              _rec(_retailUpc, ['2-2-2'], brand: 'Same', strength: '20 mg'),
            ]),
          ),
        ).check(_scan('00850022941283'));
        expect(_f(r, 'Brand name'), 'Same');
        expect(_f(r, 'Active ingredients'), '<absent>');
        expect(_f(r, 'Records sharing this UPC'), '2');
      },
    );
  });
}
