import 'dart:io';

import 'package:exalted/interpret/default_registry.dart';
import 'package:exalted/interpret/interpreter.dart';
import 'package:exalted/verify/http_client.dart';
import 'package:exalted/verify/verification.dart';
import 'package:exalted/verify/verification_engine.dart';
import 'package:exalted/verify/verification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

final _registry = defaultInterpreterRegistry();

Interpretation _scan() => _registry.interpret(
  const ScanPayload(
    raw: '(01)00376282569901(17)270924(10)ABC123',
    symbology: 'Data Matrix',
    source: 'live',
  ),
);

// Real openFDA response saved on 2026-10-10.
String _fixture() =>
    File('test/fixtures/openfda/fda_pregabalin.json')
        .readAsStringSync()
        .replaceFirst('\uFEFF', '');

VerificationEngine _engine(List<Uri> calls) => defaultVerificationEngine(
  fetch: (u) async {
    calls.add(u);

    if (u.host == 'api.fda.gov') {
      return HttpReply(200, _fixture());
    }

    if (u.host == 'world.openfoodfacts.org') {
      return const HttpReply(
        200,
        '{"status":0,"status_verbose":"product not found"}',
      );
    }

    return const HttpReply(404, '{}');
  },
);

void main() {
  test(
    'without consent no request is sent and FDA is listed as not checked',
    () async {
      final calls = <Uri>[];
      final report = await _engine(calls).verify(_scan());

      expect(calls, isEmpty);
      expect(report.notChecked.map((s) => s.id), contains('openfda-ndc'));
      expect(report.results.where((r) => r.info.id == 'openfda-ndc'), isEmpty);
    },
  );

  test('consent for another source does not enable FDA', () async {
    final calls = <Uri>[];

    await _engine(calls).verify(
      _scan(),
      allowedSources: {'openfoodfacts'},
    );

    expect(calls, hasLength(1));
    expect(calls.single.host, 'world.openfoodfacts.org');
    expect(calls.where((u) => u.host == 'api.fda.gov'), isEmpty);
  });

  test(
    'with consent the engine calls the FDA source and reports a record',
    () async {
      final calls = <Uri>[];

      final report = await _engine(calls).verify(
        _scan(),
        allowedSources: {'openfda-ndc'},
      );

      expect(calls, hasLength(1));
      expect(calls.single.host, 'api.fda.gov');

      final fda = report.results
          .where((r) => r.info.id == 'openfda-ndc')
          .toList();

      expect(fda, hasLength(1));
      expect(fda.single.info.authoritative, isFalse);
      expect(fda.single.claims.single.status, VerificationStatus.recordFound);
      expect(
        fda.single.claims.single.status,
        isNot(VerificationStatus.verified),
      );
    },
  );

  test('FDA source is a known, user-selectable online source', () {
    expect(knownOnlineSources, contains('openfda-ndc'));

    final c = onlineSourceChoices
        .where((o) => o.id == 'openfda-ndc')
        .toList();

    expect(c, hasLength(1));
    expect(c.single.subtitle, contains('Off by default'));
    expect(c.single.subtitle, contains('UPC/GTIN'));
  });
}
