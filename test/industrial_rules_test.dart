import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/gs1/gs1_parser.dart';
import 'package:exalted/industrial/domain/industrial_rules.dart';
import 'package:exalted/industrial/domain/print_job_status.dart';
import 'package:exalted/industrial/domain/serial_status.dart';

void main() {
  group('gtinProblem', () {
    test('a valid GTIN has no problem', () {
      expect(gtinProblem('4006381333931'), isNull);
    });
    test('a wrong check digit is a problem', () {
      expect(gtinProblem('4006381333932'), isNotNull);
    });
    test('letters and wrong length are problems', () {
      expect(gtinProblem('40063813X3931'), isNotNull);
      expect(gtinProblem('12345'), isNotNull);
    });
  });

  group('serial and lot rules', () {
    test('normal values pass', () {
      expect(serialProblem('SN0001'), isNull);
      expect(lotProblem('LOT-42/B'), isNull);
    });
    test('empty and too long fail', () {
      expect(serialProblem(''), isNotNull);
      expect(serialProblem('ABCDEFGHIJKLMNOPQRSTU'), isNotNull);
      expect(lotProblem('ABCDEFGHIJKLMNOPQRSTU'), isNotNull);
    });
    test('spaces and the group separator fail', () {
      expect(serialProblem('A B'), isNotNull);
      expect(serialProblem('A${gs1GroupSeparator}B'), isNotNull);
      expect(lotProblem('BAD LOT'), isNotNull);
    });
  });

  group('buildGs1ElementString', () {
    test('full string has the right layout', () {
      final s = buildGs1ElementString(
        gtin: '4006381333931',
        expiry: DateTime(2028, 6, 30),
        lot: 'LOT42',
        serial: 'SN0001',
      );
      expect(
        s,
        '0104006381333931'
        '17280630'
        '10LOT42$gs1GroupSeparator'
        '21SN0001',
      );
    });

    test('the existing parser reads it back with no errors', () {
      final s = buildGs1ElementString(
        gtin: '4006381333931',
        expiry: DateTime(2028, 6, 30),
        lot: 'LOT42',
        serial: 'SN0001',
      );
      final r = parseGs1(s, assumeGs1: true, now: DateTime(2026, 11, 17))!;
      expect(r.hasErrors, isFalse);
      expect(r.field('01')!.value, '04006381333931');
      expect(r.field('17')!.display, '2028-06-30');
      expect(r.field('10')!.value, 'LOT42');
      expect(r.field('21')!.value, 'SN0001');
    });

    test('GTIN only, and lot without serial, have no separator', () {
      expect(buildGs1ElementString(gtin: '4006381333931'), '0104006381333931');
      expect(
        buildGs1ElementString(gtin: '4006381333931', lot: 'L1'),
        '010400638133393110L1',
      );
    });

    test('bad input throws', () {
      expect(
        () => buildGs1ElementString(gtin: '4006381333932'),
        throwsArgumentError,
      );
      expect(
        () => buildGs1ElementString(gtin: '4006381333931', serial: 'A B'),
        throwsArgumentError,
      );
    });
  });

  group('status machines', () {
    test('serial flow', () {
      expect(SerialStatus.allocated.allowedNext, {
        SerialStatus.printed,
        SerialStatus.voided,
      });
      expect(SerialStatus.printed.canMoveTo(SerialStatus.verified), isTrue);
      expect(SerialStatus.rejected.allowedNext, {SerialStatus.voided});
      expect(SerialStatus.verified.isFinal, isTrue);
      expect(SerialStatus.voided.isFinal, isTrue);
      expect(SerialStatus.allocated.canMoveTo(SerialStatus.verified), isFalse);
    });
    test('print job flow', () {
      expect(PrintJobStatus.queued.allowedNext, {
        PrintJobStatus.printing,
        PrintJobStatus.cancelled,
      });
      expect(PrintJobStatus.failed.canMoveTo(PrintJobStatus.queued), isTrue);
      expect(PrintJobStatus.completed.isFinal, isTrue);
      expect(PrintJobStatus.cancelled.isFinal, isTrue);
    });
    test('database values round-trip', () {
      for (final s in SerialStatus.values) {
        expect(SerialStatus.fromDb(s.dbValue), s);
      }
      for (final s in PrintJobStatus.values) {
        expect(PrintJobStatus.fromDb(s.dbValue), s);
      }
      expect(SerialStatus.fromDb('x'), isNull);
      expect(PrintJobStatus.fromDb('x'), isNull);
    });
  });
}
