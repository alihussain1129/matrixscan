import 'package:exalted/gs1/gtin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('check digit (hand-computed, independent of the code)', () {
    test('400638133393 -> 1', () => expect(gs1CheckDigit('400638133393'), 1));
    test('03600029145 -> 2', () => expect(gs1CheckDigit('03600029145'), 2));
    test('9638507 -> 4', () => expect(gs1CheckDigit('9638507'), 4));
    test('1061414100041 -> 5', () => expect(gs1CheckDigit('1061414100041'), 5));
  });

  group('valid GTINs', () {
    for (final v in [
      '96385074', // GTIN-8
      '036000291452', // GTIN-12
      '4006381333931', // GTIN-13
      '10614141000415', // GTIN-14
      '00036000291452', // GTIN-12 padded with leading zeros
    ]) {
      test(v, () => expect(validateGtin(v).isValid, isTrue));
    }

    test('leading zeros are preserved and normalized to 14 digits', () {
      final r = validateGtin('036000291452');
      expect(r.value, '036000291452');
      expect(r.normalized14, '00036000291452');
    });
  });

  group('invalid GTINs', () {
    test('wrong check digit reports the expected one', () {
      final r = validateGtin('4006381333932');
      expect(r.status, GtinStatus.invalidCheckDigit);
      expect(r.expectedCheckDigit, 1);
      expect(r.normalized14, isNull);
    });

    test('wrong length', () {
      expect(validateGtin('12345').status, GtinStatus.invalidLength);
      expect(validateGtin('').status, GtinStatus.invalidLength);
      expect(validateGtin('123456789012345').status, GtinStatus.invalidLength);
    });

    test('non-digit characters', () {
      expect(validateGtin('40063813339A1').status, GtinStatus.invalidCharacters);
    });

    test('GTIN seen on the A12 fails its check digit (expected 9)', () {
      final r = validateGtin('08976543211234');
      expect(r.status, GtinStatus.invalidCheckDigit);
      expect(r.expectedCheckDigit, 9);
      expect(validateGtin('08976543211239').isValid, isTrue);
    });
  });
}