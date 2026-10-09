import 'dart:convert';

import 'interpreter.dart';
import 'scan_field.dart';

/// CRC-16/CCITT-FALSE (polynomial 0x1021, initial value 0xFFFF).
int emvCrc16(List<int> data) {
  var crc = 0xFFFF;
  for (final b in data) {
    crc ^= (b & 0xFF) << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc;
}

/// Four uppercase hex digits of the CRC of [text] as UTF-8.
String emvCrc16Hex(String text) =>
    emvCrc16(utf8.encode(text)).toRadixString(16).toUpperCase().padLeft(4, '0');

class _Tlv {
  _Tlv(this.id, this.value, this.start, this.valueStart);
  final String id;
  final String value;
  final int start;
  final int valueStart;
}

bool _digit(int c) => c >= 0x30 && c <= 0x39;

/// Splits "IILLvalue" records. Null when the structure is broken.
List<_Tlv>? _parse(List<int> b) {
  final out = <_Tlv>[];
  var i = 0;
  while (i < b.length) {
    if (i + 4 > b.length) return null;
    if (!_digit(b[i]) || !_digit(b[i + 1]) || !_digit(b[i + 2]) || !_digit(b[i + 3])) {
      return null;
    }
    final id = String.fromCharCodes(b.sublist(i, i + 2));
    final len = int.parse(String.fromCharCodes(b.sublist(i + 2, i + 4)));
    final end = i + 4 + len;
    if (end > b.length) return null;
    out.add(_Tlv(id, utf8.decode(b.sublist(i + 4, end), allowMalformed: true), i, i + 4));
    i = end;
  }
  return out;
}

const Map<String, String> _currencies = {
  '586': 'PKR (Pakistani rupee)',
  '840': 'USD (US dollar)',
  '978': 'EUR (euro)',
  '826': 'GBP (pound sterling)',
  '356': 'INR (Indian rupee)',
  '784': 'AED (UAE dirham)',
  '682': 'SAR (Saudi riyal)',
  '156': 'CNY (Chinese yuan)',
  '392': 'JPY (Japanese yen)',
  '124': 'CAD (Canadian dollar)',
  '036': 'AUD (Australian dollar)',
};

const Map<String, String> _additionalLabels = {
  '01': 'Bill number',
  '02': 'Mobile number',
  '03': 'Store label',
  '04': 'Loyalty number',
  '05': 'Reference label',
  '06': 'Customer label',
  '07': 'Terminal label',
  '08': 'Purpose of transaction',
  '09': 'Additional consumer data request',
};

final RegExp _amount = RegExp(r'^\d+(\.\d+)?$');
final RegExp _hex4 = RegExp(r'^[0-9A-Fa-f]{4}$');

/// EMVCo merchant-presented payment QR (generic). It does not identify a
/// payment network, verify the merchant, or make any payment.
class EmvInterpreter implements PayloadInterpreter {
  @override
  String get id => 'emv';

  @override
  Interpretation? interpret(ScanPayload payload) {
    final raw = payload.raw;
    if (!raw.startsWith('000201')) return null;

    final bytes = utf8.encode(raw);
    final tlv = _parse(bytes);
    if (tlv == null || tlv.isEmpty || tlv.first.id != '00') {
      if (!raw.contains('6304')) return null;
      return Interpretation(
        interpreterId: id,
        formatName: 'EMV payment QR (malformed)',
        rawIsSensitive: true,
        warnings: const [
          'The text looks like an EMV payment QR but its structure is '
              'broken or truncated. Nothing in it was interpreted.',
        ],
        sections: [
          ScanSection(
            id: 'payment',
            title: 'Payment QR',
            fields: const [
              ScanField(
                id: 'structure',
                label: 'Structure',
                value: 'Invalid',
                validation: FieldValidation.invalid,
                standard: 'EMVCo merchant-presented QR',
              ),
            ],
          ),
        ],
      );
    }

    const std = 'EMVCo merchant-presented QR';
    final warnings = <String>[
      'The merchant name and account details are as written in the QR. '
          'EXALTED has not verified who owns the account, and no payment '
          'was made or requested.',
    ];

    String? top(String tag) {
      for (final t in tlv) {
        if (t.id == tag) return t.value;
      }
      return null;
    }

    ScanField present(String tag, String label,
        {String? note, String? unit, String? display}) {
      final v = top(tag);
      if (v == null) return ScanField.notPresent(label, id: tag, standard: std);
      return ScanField(
        id: tag,
        label: label,
        value: v.isEmpty ? null : (display ?? v),
        original: display != null ? v : null,
        presence: v.isEmpty ? FieldPresence.empty : FieldPresence.present,
        standard: std,
        unit: unit,
        note: note,
      );
    }

    final init = top('01');
    final initField = init == null
        ? const ScanField.notPresent('Point of initiation', id: '01', standard: std)
        : ScanField(
            id: '01',
            label: 'Point of initiation',
            value: init == '11'
                ? 'Static (11)'
                : init == '12'
                ? 'Dynamic (12)'
                : init,
            original: init,
            standard: std,
            validation: (init == '11' || init == '12')
                ? FieldValidation.valid
                : FieldValidation.invalid,
          );

    final currency = top('53');
    final currencyField = currency == null
        ? const ScanField.notPresent('Currency', id: '53', standard: std)
        : ScanField(
            id: '53',
            label: 'Currency',
            value: _currencies[currency] ?? currency,
            original: currency,
            standard: std,
            note: _currencies.containsKey(currency)
                ? null
                : 'Numeric currency code; not in EXALTED\u2019s short list.',
          );

    final amount = top('54');
    final amountField = amount == null
        ? const ScanField.notPresent('Amount', id: '54', standard: std)
        : ScanField(
            id: '54',
            label: 'Amount',
            value: amount,
            standard: std,
            unit: currency,
            validation: _amount.hasMatch(amount)
                ? FieldValidation.valid
                : FieldValidation.invalid,
            warning: _amount.hasMatch(amount) ? null : 'Not a valid amount.',
          );

    final payment = <ScanField>[
      const ScanField(
        id: 'scheme',
        label: 'Payment scheme',
        value: 'EMVCo merchant-presented QR (generic)',
        origin: FieldOrigin.calculated,
        note: 'The specific payment network was not determined.',
      ),
      present('00', 'Payload format indicator'),
      initField,
      present(
        '59',
        'Merchant name (encoded in QR)',
        note: 'Written in the QR. Not verified as the account owner.',
      ),
      present('60', 'Merchant city'),
      present('58', 'Country code'),
      present('61', 'Postal code'),
      present('52', 'Merchant category code'),
      currencyField,
      amountField,
      if (top('55') != null) present('55', 'Tip or convenience fee indicator'),
      if (top('56') != null) present('56', 'Convenience fee (fixed)'),
      if (top('57') != null) present('57', 'Convenience fee (percentage)'),
    ];

    final accountSections = <ScanSection>[];
    for (final t in tlv) {
      final n = int.tryParse(t.id) ?? -1;
      if (n < 26 || n > 51) continue;
      final subs = _parse(utf8.encode(t.value));
      if (subs == null) {
        warnings.add('Account template ${t.id} could not be split into fields.');
        accountSections.add(ScanSection(
          id: 'acct${t.id}',
          title: 'Merchant account information (ID ${t.id})',
          fields: [
            ScanField(
              id: t.id,
              label: 'Template content',
              value: t.value,
              sensitive: true,
              validation: FieldValidation.invalid,
            ),
          ],
        ));
        continue;
      }
      accountSections.add(ScanSection(
        id: 'acct${t.id}',
        title: 'Merchant account information (ID ${t.id})',
        fields: [
          for (final s in subs)
            ScanField(
              id: '${t.id}.${s.id}',
              label: s.id == '00' ? 'Globally unique identifier' : 'Sub-field ${s.id}',
              value: s.value.isEmpty ? null : s.value,
              presence: s.value.isEmpty ? FieldPresence.empty : FieldPresence.present,
              standard: std,
              sensitive: s.id != '00',
              note: s.id == '00'
                  ? 'Identifies the scheme or provider that defines the other sub-fields. EXALTED does not interpret them.'
                  : 'Scheme-specific; may be an account identifier. Hidden in exports.',
            ),
        ],
      ));
    }

    final extra = top('62');
    final additional = <ScanField>[];
    if (extra != null) {
      final subs = _parse(utf8.encode(extra));
      if (subs == null) {
        warnings.add('The additional data template (ID 62) could not be split.');
      } else {
        for (final s in subs) {
          additional.add(ScanField(
            id: '62.${s.id}',
            label: _additionalLabels[s.id] ?? 'Sub-field ${s.id}',
            value: s.value.isEmpty ? null : s.value,
            presence: s.value.isEmpty ? FieldPresence.empty : FieldPresence.present,
            standard: std,
            sensitive: s.id == '02',
          ));
        }
      }
    }

    // CRC: tag 63, last, 4 hex digits, over everything up to and including "6304".
    final crcTlv = tlv.where((t) => t.id == '63').toList();
    final crcFields = <ScanField>[];
    if (crcTlv.isEmpty) {
      warnings.add('The QR has no CRC field, so its integrity cannot be checked.');
      crcFields.add(const ScanField.notPresent('CRC', id: '63', standard: std));
    } else {
      final c = crcTlv.last;
      final isLast = identical(c, tlv.last);
      if (!isLast || !_hex4.hasMatch(c.value)) {
        warnings.add('The CRC field is misplaced or malformed.');
        crcFields.add(ScanField(
          id: '63',
          label: 'CRC in QR',
          value: c.value,
          validation: FieldValidation.invalid,
          standard: std,
        ));
      } else {
        final expected = emvCrc16(bytes.sublist(0, c.valueStart))
            .toRadixString(16)
            .toUpperCase()
            .padLeft(4, '0');
        final ok = expected == c.value.toUpperCase();
        if (!ok) {
          warnings.add(
            'The CRC does not match (QR says ${c.value.toUpperCase()}, '
            'calculated $expected). The QR may be damaged or altered.',
          );
        }
        crcFields.addAll([
          ScanField(
            id: '63',
            label: 'CRC in QR',
            value: c.value.toUpperCase(),
            standard: std,
            validation: ok ? FieldValidation.valid : FieldValidation.invalid,
            note: 'A matching CRC shows the text was not damaged. It does not '
                'show the payee is genuine.',
          ),
          ScanField(
            id: 'crcCalc',
            label: 'CRC calculated',
            value: expected,
            origin: FieldOrigin.calculated,
          ),
        ]);
      }
    }

    const known = {'00', '01', '52', '53', '54', '55', '56', '57', '58', '59', '60', '61', '62', '63'};
    final other = <ScanField>[
      for (final t in tlv)
        if (!known.contains(t.id) && !((int.tryParse(t.id) ?? -1) >= 26 && (int.tryParse(t.id) ?? -1) <= 51))
          ScanField(
            id: t.id,
            label: 'Other field ${t.id}',
            value: t.value.isEmpty ? null : t.value,
            presence: t.value.isEmpty ? FieldPresence.empty : FieldPresence.present,
            note: 'Not interpreted by EXALTED; kept as encoded.',
          ),
    ];

    return Interpretation(
      interpreterId: id,
      formatName: 'EMV payment QR (merchant-presented)',
      rawIsSensitive: true,
      warnings: warnings,
      sections: [
        ScanSection(id: 'payment', title: 'Payment details', fields: payment),
        ScanSection(
          id: 'accounts',
          title: 'Merchant account information',
          fields: accountSections.isEmpty
              ? const [ScanField.notPresent('Merchant account information', id: '26-51', standard: std)]
              : const [],
          sections: accountSections,
        ),
        ScanSection(
          id: 'additional',
          title: 'Additional data',
          fields: additional.isEmpty
              ? const [ScanField.notPresent('Additional data', id: '62', standard: std)]
              : additional,
        ),
        ScanSection(id: 'integrity', title: 'Integrity check', fields: crcFields),
        if (other.isNotEmpty) ScanSection(id: 'other', title: 'Other fields', fields: other),
      ],
    );
  }
}