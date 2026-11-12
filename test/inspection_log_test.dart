import 'dart:io';

import 'package:exalted/features/inspection/gs1_fields.dart';
import 'package:exalted/features/inspection/inspection_log.dart';
import 'package:exalted/features/inspection/inspection_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = '(01)09504000059101(21)19067811811(10)563GS1(17)200331';

  test('parses the GS1 sample into labelled fields', () {
    final f = Gs1Fields.parse(sample);
    expect(f.map((e) => e.ai), ['01', '21', '10', '17']);
    expect(f[0].label, 'GTIN');
    expect(f[1].value, '19067811811');
    expect(f[2].value, '563GS1');
    expect(Gs1Fields.parse('HELLO'), isEmpty);
  });

  test('dates and check digits', () {
    final now = DateTime(2026, 11, 3);
    expect(Gs1Fields.formatDate('200331', now: now), '2020-03-31');
    expect(Gs1Fields.formatDate('271231', now: now), '2027-12-31');
    expect(Gs1Fields.formatDate('991231', now: now), '1999-12-31');
    expect(Gs1Fields.formatDate('250200', now: now), '2025-02');
    expect(Gs1Fields.formatDate('250231', now: now), isNull);
    expect(Gs1Fields.gtinIsValid('09504000059101'), isTrue);
    expect(Gs1Fields.gtinIsValid('01234567890128'), isTrue);
    expect(Gs1Fields.gtinIsValid('09504000059102'), isFalse);
  });

  group('InspectionLog', () {
    late Directory dir;
    late InspectionLog log;
    final now = DateTime(2026, 11, 3, 10);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('exalted_rows_');
      log = InspectionLog(directory: () async => dir, clock: () => now);
    });
    tearDown(() async => dir.delete(recursive: true));

    String code(String serial, String lot) =>
        '(01)09504000059101(21)$serial(10)$lot(17)271231';

    test('repeated serial fails, new serial passes', () async {
      final a = await log.recordDecode(
        raw: code('SN1', 'L1'),
        symbology: 'Data Matrix',
        source: 'live',
      );
      expect(a!.status, RowStatus.pass);
      final b = await log.recordDecode(
        raw: code('SN1', 'L1'),
        symbology: 'Data Matrix',
        source: 'live',
      );
      expect(b!.status, RowStatus.fail);
      expect(b.duplicateOf, a.id);
      final c = await log.recordDecode(
        raw: code('SN2', 'L1'),
        symbology: 'Data Matrix',
        source: 'live',
      );
      expect(c!.status, RowStatus.pass);
    });

    test('returning to an earlier lot needs review', () async {
      Future<InspectionRow?> rec(String s, String l) => log.recordDecode(
        raw: code(s, l),
        symbology: 'Data Matrix',
        source: 'live',
      );
      expect((await rec('A', 'L1'))!.status, RowStatus.pass);
      expect((await rec('B', 'L2'))!.status, RowStatus.pass);
      expect((await rec('C', 'L1'))!.status, RowStatus.review);
    });

    test('duplicate detection survives a restart', () async {
      await log.recordDecode(
        raw: code('SN9', 'L1'),
        symbology: 'Data Matrix',
        source: 'live',
      );
      final again = InspectionLog(directory: () async => dir, clock: () => now);
      final r = await again.recordDecode(
        raw: code('SN9', 'L1'),
        symbology: 'Data Matrix',
        source: 'live',
      );
      expect(r!.status, RowStatus.fail);
      expect((await again.loadAll()).length, 2);
    });

    test('bad check digit fails, plain code passes, expired reviews', () async {
      final bad = await log.recordDecode(
        raw: '(01)09504000059102(21)X1',
        symbology: 'Data Matrix',
        source: 'live',
      );
      expect(bad!.status, RowStatus.fail);
      final plain = await log.recordDecode(
        raw: 'HELLO',
        symbology: 'QR Code',
        source: 'live',
      );
      expect(plain!.status, RowStatus.pass);
      final expired = await log.recordDecode(
        raw: sample,
        symbology: 'Data Matrix',
        source: 'live',
      );
      expect(expired!.status, RowStatus.review);
      expect(expired.expiryDisplay, '2020-03-31');
    });

    test('OCR text is compared with the decoded fields', () async {
      final ok = await log.recordDecode(
        raw: code('O1', 'L1'),
        symbology: 'Data Matrix',
        source: 'live',
        ocrText: '(01)09504000059101\n(21)O1\n(10)L1\n(17)271231',
      );
      expect(ok!.status, RowStatus.pass);
      final bad = await log.recordDecode(
        raw: code('O2', 'L1'),
        symbology: 'Data Matrix',
        source: 'live',
        ocrText: '(01)09504000059101 (21)O3 (10)L1 (17)271231',
      );
      expect(bad!.status, RowStatus.fail);
      expect(bad.reasons.single, contains('Serial number'));
    });

    test('CSV has one line per row', () async {
      await log.recordDecode(
        raw: code('C1', 'L1'),
        symbology: 'Data Matrix',
        source: 'live',
      );
      final csv = inspectionRowsToCsv(await log.loadAll());
      expect(csv.trim().split('\n').length, 2);
      expect(csv, contains('C1'));
    });
  });
}
