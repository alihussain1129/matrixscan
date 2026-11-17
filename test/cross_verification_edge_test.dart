import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/gs1/gs1_parser.dart';
import 'package:exalted/inspection/cross_verification.dart';

const _gs = gs1GroupSeparator;
final _now = DateTime(2026, 11, 17);

String code({String lot = 'LOT42'}) =>
    '0104006381333931'
    '172806'
    '30'
    '10$lot$_gs'
    '21SN0001';

void main() {
  test('non-GS1 barcode with nothing to compare is REVIEW, not PASS', () {
    final r = verifyInspection(
      barcodeText: 'PLAIN12345',
      policy: const InspectionPolicy(),
      now: _now,
    );
    expect(r.outcome, InspectionOutcome.review);
  });

  test('GS1 barcode with nothing expected still passes', () {
    final r = verifyInspection(
      barcodeText: code(),
      policy: const InspectionPolicy(assumeGs1: true),
      now: _now,
    );
    expect(r.outcome, InspectionOutcome.pass);
  });

  test('case-insensitive look-alike difference is REVIEW', () {
    final r = verifyInspection(
      barcodeText: code(lot: 'IOT42'),
      expected: const ExpectedValues(lot: 'l0t42'),
      policy: const InspectionPolicy(assumeGs1: true, caseSensitive: false),
      now: _now,
    );
    expect(r.outcome, InspectionOutcome.review);
  });

  test('case-insensitive real difference is still FAIL', () {
    final r = verifyInspection(
      barcodeText: code(lot: 'XYZ99'),
      expected: const ExpectedValues(lot: 'l0t42'),
      policy: const InspectionPolicy(assumeGs1: true, caseSensitive: false),
      now: _now,
    );
    expect(r.outcome, InspectionOutcome.fail);
  });
}
