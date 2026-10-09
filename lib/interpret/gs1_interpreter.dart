import '../gs1/gs1_parser.dart';
import 'interpreter.dart';
import 'scan_field.dart';

/// Expiry status calculated on this device from the date in the barcode.
String gs1ExpiryStatus(Gs1Date date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final end = date.date;
  if (end.isBefore(today)) return 'Expired';
  if (end.difference(today).inDays <= 30) return 'Near expiry (within 30 days)';
  return 'Not expired';
}

/// GS1 data in text form. Works on the decoded text only, so it cannot
/// confirm that the symbol itself was encoded as GS1.
class Gs1Interpreter implements PayloadInterpreter {
  Gs1Interpreter({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  String get id => 'gs1';

  @override
  Interpretation? interpret(ScanPayload payload) {
    final now = _clock();
    final result = parseGs1(payload.raw, now: now);
    if (result == null) return null;

    final used = Set<Gs1Field>.identity();
    final warnings = <String>[
      'The text is GS1-formatted, but the symbol is not confirmed as GS1 '
          '(the symbology identifier is not available yet). Nothing was '
          'checked against a database.',
    ];

    ScanField convert(Gs1Field f) {
      used.add(f);
      final spec = gs1AiTable[f.ai];
      String? note;
      if (f.status == Gs1FieldStatus.unknownAi) {
        note = 'Not interpreted by EXALTED; kept as encoded.';
      } else if (f.isValid && spec?.type == Gs1ValueType.gtin) {
        note =
            'Check digit is valid. This checks structure only, not whether '
            'the product exists or is genuine.';
      } else if (f.isValid && spec?.type == Gs1ValueType.date) {
        note = 'Encoded as YYMMDD.';
      }
      if (f.status == Gs1FieldStatus.invalid) {
        warnings.add('${f.name} (AI ${f.ai}): ${f.error}');
      }
      return ScanField(
        id: f.ai,
        label: f.name,
        value: f.value.isEmpty ? null : f.display,
        original: f.value,
        standard: 'GS1',
        dataType: spec?.type.name,
        presence: f.value.isEmpty ? FieldPresence.empty : FieldPresence.present,
        validation: switch (f.status) {
          Gs1FieldStatus.valid => FieldValidation.valid,
          Gs1FieldStatus.invalid => FieldValidation.invalid,
          Gs1FieldStatus.unknownAi => FieldValidation.notChecked,
        },
        note: note,
        warning: f.error,
      );
    }

    List<ScanField> group(Map<String, String> always, List<String> optional) {
      final out = <ScanField>[];
      always.forEach((ai, label) {
        final matches = result.fields.where((f) => f.ai == ai).toList();
        if (matches.isEmpty) {
          out.add(ScanField.notPresent(label, id: ai, standard: 'GS1'));
        } else {
          out.addAll(matches.map(convert));
        }
      });
      for (final ai in optional) {
        out.addAll(result.fields.where((f) => f.ai == ai).map(convert));
      }
      return out;
    }

    final product = group({'01': 'GTIN'}, ['02', '20', '240']);
    final batch = group({'10': 'Batch/Lot number', '21': 'Serial number'}, [
      '250',
    ]);
    final dates = group({'17': 'Expiration date'}, ['11', '13', '15']);

    final expiry = result.fields.where((f) => f.ai == '17' && f.isValid);
    if (expiry.isNotEmpty) {
      final parsed = parseGs1Date(expiry.first.value, now: now);
      if (parsed != null) {
        final status = gs1ExpiryStatus(parsed, now);
        if (status == 'Expired') {
          warnings.add('The expiry date in the barcode has passed.');
        }
        dates.add(
          ScanField(
            id: 'expiryStatus',
            label: 'Expiry status',
            value: status,
            origin: FieldOrigin.calculated,
            note:
                'Calculated on this device from the date in the barcode. '
                'Not checked against any record.',
            warning: status == 'Expired' ? 'This date has passed.' : null,
          ),
        );
      }
    }

    final other = <ScanField>[
      for (final f in result.fields)
        if (!used.contains(f)) convert(f),
    ];
    if (result.unparsed.isNotEmpty) {
      warnings.add('Part of the text could not be split into GS1 fields.');
      other.add(
        ScanField(
          id: 'unparsed',
          label: 'Unparsed remainder',
          value: result.unparsed,
          origin: FieldOrigin.parsed,
          validation: FieldValidation.invalid,
          warning: 'Could not be split into GS1 fields.',
        ),
      );
    }

    return Interpretation(
      interpreterId: id,
      formatName: result.form == Gs1Form.parenthesized
          ? 'GS1 data (Application Identifiers in text)'
          : 'GS1 element string',
      sections: [
        ScanSection(id: 'product', title: 'Product identification', fields: product),
        ScanSection(id: 'batch', title: 'Batch and serial', fields: batch),
        ScanSection(id: 'dates', title: 'Dates and expiry', fields: dates),
        if (other.isNotEmpty)
          ScanSection(id: 'other', title: 'Other GS1 fields', fields: other),
      ],
      warnings: warnings,
    );
  }
}