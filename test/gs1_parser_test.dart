import 'package:exalted/gs1/gs1_parser.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 9);
const _gs = gs1GroupSeparator;

void main() {
  group('parenthesized form', () {
    test('GTIN, expiry, lot and serial', () {
      const text = '(01)04006381333931(17)270924(10)ABC123(21)XYZ789';
      final r = parseGs1(text, now: _now)!;
      expect(r.original, text);
      expect(r.form, Gs1Form.parenthesized);
      expect(r.fields.map((f) => f.ai), ['01', '17', '10', '21']);
      expect(r.hasErrors, isFalse);
      expect(r.field('10')!.value, 'ABC123');
      expect(r.field('21')!.value, 'XYZ789');
      expect(r.field('17')!.display, '2027-09-24');
      expect(r.field('17')!.value, '270924');
    });

    test('symbol read on the phone: decodes, but its GTIN is invalid', () {
      const text = '(01)08976543211234(17)270924(10)272718(21)8760C6AEDE474';
      final r = parseGs1(text, now: _now)!;
      expect(r.field('01')!.isValid, isFalse);
      expect(r.field('01')!.error, contains('expected 9'));
      expect(r.field('17')!.isValid, isTrue);
      expect(r.field('10')!.value, '272718');
      expect(r.field('21')!.value, '8760C6AEDE474');
      expect(r.hasErrors, isTrue);
    });

    test('unknown AI is kept, not dropped', () {
      final r = parseGs1('(01)04006381333931(99)hello', now: _now)!;
      expect(r.fields.length, 2);
      expect(r.field('99')!.status, Gs1FieldStatus.unknownAi);
      expect(r.field('99')!.value, 'hello');
    });

    test('truncated GTIN is reported', () {
      final r = parseGs1('(01)0400638', now: _now)!;
      expect(r.field('01')!.status, Gs1FieldStatus.invalid);
      expect(r.field('01')!.error, contains('14'));
    });

    test('count AI must be numeric', () {
      final r = parseGs1('(30)12A', now: _now)!;
      expect(r.field('30')!.isValid, isFalse);
    });
  });

  group('element string form', () {
    test('group separator ends a variable-length field', () {
      const text = '010400638133393117270924' '10ABC123$_gs' '21XYZ789';
      final r = parseGs1(text, assumeGs1: true, now: _now)!;
      expect(r.form, Gs1Form.elementString);
      expect(r.fields.map((f) => f.ai), ['01', '17', '10', '21']);
      expect(r.field('10')!.value, 'ABC123');
      expect(r.field('21')!.value, 'XYZ789');
      expect(r.hasErrors, isFalse);
    });

    test('without a separator the variable field swallows the rest', () {
      const text = '0104006381333931' '10ABC123' '21XYZ';
      final r = parseGs1(text, assumeGs1: true, now: _now)!;
      expect(r.fields.map((f) => f.ai), ['01', '10']);
      expect(r.field('10')!.value, 'ABC12321XYZ');
    });

    test('symbology prefix is recognised and reported', () {
      final r = parseGs1(']d20104006381333931', now: _now)!;
      expect(r.symbologyPrefix, ']d2');
      expect(r.field('01')!.isValid, isTrue);
    });

    test('unparseable remainder is preserved', () {
      final r = parseGs1('0104006381333931ZZtail', assumeGs1: true, now: _now)!;
      expect(r.unparsed, 'ZZtail');
      expect(r.hasErrors, isTrue);
    });
  });

  group('not GS1', () {
    test('plain text, EAN-13 digits and unprefixed digits give null', () {
      expect(parseGs1('hello world'), isNull);
      expect(parseGs1('8600250286876'), isNull);
      expect(parseGs1('0104006381333931'), isNull);
    });
  });

  group('dates (rules marked UNVERIFIED in the parser)', () {
    test('valid and invalid calendar dates', () {
      expect(parseGs1Date('280229', now: _now), isNotNull); // leap year
      expect(parseGs1Date('270229', now: _now), isNull);
      expect(parseGs1Date('270230', now: _now), isNull);
      expect(parseGs1Date('271332', now: _now), isNull);
      expect(parseGs1Date('27092', now: _now), isNull);
      expect(parseGs1Date('27ab24', now: _now), isNull);
    });

    test('day 00 means the end of the month', () {
      final d = parseGs1Date('270900', now: _now)!;
      expect(d.dayUnspecified, isTrue);
      expect(d.date, DateTime(2027, 9, 30));
    });

    test('century window around 2026', () {
      expect(parseGs1Date('270924', now: _now)!.year, 2027);
      expect(parseGs1Date('760101', now: _now)!.year, 1976);
      expect(parseGs1Date('750101', now: _now)!.year, 2075);
    });

    test('invalid date field is reported with the original value kept', () {
      final r = parseGs1('(17)271332', now: _now)!;
      expect(r.field('17')!.isValid, isFalse);
      expect(r.field('17')!.value, '271332');
    });
  });
}