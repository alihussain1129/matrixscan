import 'package:exalted/interpret/default_registry.dart';
import 'package:exalted/interpret/interpreter.dart';
import 'package:exalted/interpret/scan_field.dart';
import 'package:exalted/verify/open_food_facts_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registry = defaultInterpreterRegistry();

  Interpretation interpret(String raw) => registry.interpret(
    ScanPayload(raw: raw, symbology: 'QR Code', source: 'test'),
  );

  group('GS1-style identifiers in URL paths', () {
    test('extracts a valid GTIN and serial without changing URL interpretation', () {
      const raw =
          'https://example.com/01/09521207311511/21/1234ABDE1235';

      final result = interpret(raw);
      final identifiers = result.section('url_product_ids');

      expect(result.interpreterId, 'url');
      expect(result.formatName, 'Web link');
      expect(identifiers, isNotNull);

      final gtin = identifiers!.fields.firstWhere((f) => f.id == '01');
      final serial = identifiers.fields.firstWhere((f) => f.id == '21');

      expect(gtin.value, '09521207311511');
      expect(gtin.validation, FieldValidation.valid);
      expect(gtin.standard, 'GS1 URL path (unconfirmed)');
      expect(serial.value, '1234ABDE1235');

      // Product lookup may use only the GTIN, never the serial number.
      expect(gtinFrom(result), '09521207311511');
      expect(result.section('raw')!.fields.first.value, raw);
    });

    test('does not allow an invalid GTIN to trigger product lookup', () {
      final result = interpret(
        'https://example.com/01/09521207311510/21/SERIAL123',
      );

      final identifiers = result.section('url_product_ids');
      expect(identifiers, isNotNull);

      final gtin = identifiers!.fields.firstWhere((f) => f.id == '01');
      expect(gtin.validation, FieldValidation.invalid);
      expect(gtinFrom(result), isNull);
    });

    test('ordinary URLs do not become GS1 product URLs', () {
      final result = interpret('https://example.com/products/12345');

      expect(result.interpreterId, 'url');
      expect(result.section('url_product_ids'), isNull);
      expect(gtinFrom(result), isNull);
    });
  });
}

