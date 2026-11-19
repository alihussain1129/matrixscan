import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/gs1/gs1_parser.dart';
import 'package:exalted/inspection/cross_verification.dart';
import 'package:exalted/inspection/text_diff.dart';

const _gs = gs1GroupSeparator;
const _policy = InspectionPolicy(assumeGs1: true);
final _now = DateTime(2026, 11, 17);

String code({
  String gtin = '04006381333931',
  String lot = 'LOT42',
  String exp = '280630',
  String serial = 'SN0001',
}) =>
    '01$gtin'
    '17$exp'
    '10$lot$_gs'
    '21$serial';

ExpectedValues expected({
  String? lot = 'LOT42',
  String? serial = 'SN0001',
  DateTime? expiry,
}) => ExpectedValues(
  gtin: '4006381333931',
  lot: lot,
  expiry: expiry ?? DateTime(2028, 6, 30),
  serial: serial,
  source: 'test',
  externalRef: 'ref-1',
);

OcrReading ocrAll({
  double c = 0.95,
  String serial = 'SN0001',
  String lot = 'LOT42',
}) => OcrReading(
  fields: {
    InspectionField.gtin: OcrFieldReading('04006381333931', confidence: c),
    InspectionField.lot: OcrFieldReading(lot, confidence: c),
    InspectionField.expiry: OcrFieldReading('2028-06-30', confidence: c),
    InspectionField.serial: OcrFieldReading(serial, confidence: c),
  },
);

InspectionResult run({
  String? barcode,
  OcrReading? ocr,
  ExpectedValues? exp,
  InspectionPolicy policy = _policy,
}) => verifyInspection(
  barcodeText: barcode,
  ocr: ocr,
  expected: exp,
  policy: policy,
  now: _now,
);

FieldResult field(InspectionResult r, InspectionField f) =>
    r.fields.firstWhere((x) => x.field == f);

void main() {
  test('barcode matches expected: PASS and traceability fields kept', () {
    final r = run(barcode: code(), exp: expected());
    expect(r.outcome, InspectionOutcome.pass);
    expect(r.reasons, isEmpty);
    expect(r.crossChecked, isFalse);
    expect(r.expectedSource, 'test');
    expect(r.expectedRef, 'ref-1');
    expect(r.policyVersion, 'default-1');
  });

  test('barcode, OCR and expected all agree: PASS and cross-checked', () {
    final r = run(barcode: code(), ocr: ocrAll(), exp: expected());
    expect(r.outcome, InspectionOutcome.pass);
    expect(r.crossChecked, isTrue);
    expect(r.reasons, isEmpty);
  });

  test('wrong serial in the barcode: FAIL with a character diff', () {
    final r = run(
      barcode: code(),
      exp: expected(serial: 'SN0002'),
    );
    expect(r.outcome, InspectionOutcome.fail);
    final d = field(r, InspectionField.serial).barcodeVsExpected!.diffs.single;
    expect(d.kind, DiffKind.substituted);
    expect(d.expectedChar, '2');
    expect(d.actualChar, '1');
  });

  test('wrong expiry date: FAIL', () {
    final r = run(
      barcode: code(),
      exp: expected(expiry: DateTime(2028, 6, 29)),
    );
    expect(r.outcome, InspectionOutcome.fail);
    expect(field(r, InspectionField.expiry).verdict, Verdict.mismatch);
  });

  test('nothing read: NO READ', () {
    expect(run().outcome, InspectionOutcome.noRead);
    expect(
      run(barcode: '  ', ocr: const OcrReading()).outcome,
      InspectionOutcome.noRead,
    );
  });

  test('barcode only, nothing expected: PASS', () {
    expect(run(barcode: code()).outcome, InspectionOutcome.pass);
  });

  test('invalid GTIN check digit in the barcode: FAIL', () {
    final r = run(barcode: code(gtin: '04006381333932'));
    expect(r.outcome, InspectionOutcome.fail);
    expect(r.reasons.any((x) => x.contains('GS1 (01)')), isTrue);
  });

  test('OCR ran but read nothing: REVIEW, not FAIL', () {
    final r = run(barcode: code(), ocr: const OcrReading(), exp: expected());
    expect(r.outcome, InspectionOutcome.review);
    expect(
      r.reasons.any((x) => x.contains('OCR ran but read no text')),
      isTrue,
    );
  });

  test('printed serial differs from the barcode: FAIL', () {
    final r = run(
      barcode: code(),
      ocr: ocrAll(serial: 'SN0002'),
      exp: expected(),
    );
    expect(r.outcome, InspectionOutcome.fail);
    expect(
      field(r, InspectionField.serial).barcodeVsOcr!.verdict,
      Verdict.mismatch,
    );
  });

  test('low-confidence OCR that differs: REVIEW, not FAIL', () {
    final r = run(
      barcode: code(),
      ocr: ocrAll(c: 0.5, serial: 'SN0002'),
      exp: expected(),
    );
    expect(r.outcome, InspectionOutcome.review);
  });

  test('low-confidence OCR that matches: still REVIEW', () {
    final r = run(barcode: code(), ocr: ocrAll(c: 0.5), exp: expected());
    expect(r.outcome, InspectionOutcome.review);
  });

  test('look-alike difference (O vs 0) is REVIEW, never PASS', () {
    final r = run(
      barcode: code(lot: 'L0T42'),
      ocr: OcrReading(
        fields: const {
          InspectionField.lot: OcrFieldReading('LOT42', confidence: 0.95),
        },
      ),
      exp: expected(lot: 'L0T42'),
    );
    expect(r.outcome, InspectionOutcome.review);
    expect(field(r, InspectionField.lot).verdict, Verdict.review);
  });

  test('look-alike handling can be switched off, then it is a FAIL', () {
    final r = run(
      barcode: code(lot: 'L0T42'),
      ocr: OcrReading(
        fields: const {
          InspectionField.lot: OcrFieldReading('LOT42', confidence: 0.95),
        },
      ),
      exp: expected(lot: 'L0T42'),
      policy: const InspectionPolicy(
        assumeGs1: true,
        confusablesNeedReview: false,
      ),
    );
    expect(r.outcome, InspectionOutcome.fail);
  });

  test('barcode not read but OCR text exists: NO READ', () {
    final r = run(
      ocr: OcrReading(
        fields: const {
          InspectionField.serial: OcrFieldReading('SN0001', confidence: 0.95),
        },
      ),
      exp: const ExpectedValues(serial: 'SN0001'),
    );
    expect(r.outcome, InspectionOutcome.noRead);
  });

  test('a mismatch beats a missing barcode: FAIL', () {
    final r = run(
      ocr: OcrReading(
        fields: const {
          InspectionField.serial: OcrFieldReading('SN0009', confidence: 0.95),
        },
      ),
      exp: const ExpectedValues(serial: 'SN0001'),
    );
    expect(r.outcome, InspectionOutcome.fail);
  });

  test('expected serial but the barcode is not GS1: FAIL', () {
    final r = run(
      barcode: 'HELLO',
      exp: const ExpectedValues(serial: 'SN0001'),
    );
    expect(r.outcome, InspectionOutcome.fail);
  });

  test('an invalid expected GTIN is flagged for review', () {
    final r = run(
      barcode: code(),
      exp: const ExpectedValues(gtin: '4006381333932'),
    );
    expect(r.outcome, InspectionOutcome.review);
    expect(
      r.reasons.any((x) => x.contains('Expected GTIN is not valid')),
      isTrue,
    );
  });
}
