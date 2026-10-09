import 'dart:convert';

import 'package:exalted/interpret/default_registry.dart';
import 'package:exalted/interpret/emv_interpreter.dart';
import 'package:exalted/interpret/interpreter.dart';
import 'package:exalted/interpret/scan_field.dart';
import 'package:flutter_test/flutter_test.dart';

/// "IILLvalue", with the length counted in UTF-8 bytes.
String _t(String id, String v) =>
    '$id${utf8.encode(v).length.toString().padLeft(2, '0')}$v';

String _withCrc(String body) {
  final pre = '${body}6304';
  return pre + emvCrc16Hex(pre);
}

final _registry = defaultInterpreterRegistry();

Interpretation _run(String raw) =>
    _registry.interpret(ScanPayload(raw: raw, symbology: 'QR Code', source: 'live'));

ScanField _f(Interpretation i, String id) =>
    i.allFields.firstWhere((f) => f.id == id);

final _body = _t('00', '01') +
    _t('01', '12') +
    _t('26', _t('00', 'com.example.pay') + _t('01', 'ACC-0001234567')) +
    _t('52', '5411') +
    _t('53', '586') +
    _t('54', '150.50') +
    _t('58', 'PK') +
    _t('59', 'Test Shop') +
    _t('60', 'Lahore') +
    _t('62', _t('01', 'INV-42') + _t('05', 'REF-9'));

void main() {
  test('CRC routine matches the standard CRC-16/CCITT-FALSE check value', () {
    expect(emvCrc16Hex('123456789'), '29B1');
  });

  test('a complete dynamic payment QR is read field by field', () {
    final raw = _withCrc(_body);
    final i = _run(raw);
    expect(i.interpreterId, 'emv');
    expect(_f(i, '01').value, 'Dynamic (12)');
    final name = _f(i, '59');
    expect(name.label, 'Merchant name (encoded in QR)');
    expect(name.value, 'Test Shop');
    expect(name.verification, FieldVerification.notVerified);
    expect(_f(i, '60').value, 'Lahore');
    expect(_f(i, '58').value, 'PK');
    expect(_f(i, '52').value, '5411');
    expect(_f(i, '53').value, 'PKR (Pakistani rupee)');
    expect(_f(i, '53').original, '586');
    expect(_f(i, '54').value, '150.50');
    expect(_f(i, '54').validation, FieldValidation.valid);
    expect(_f(i, '26.00').value, 'com.example.pay');
    expect(_f(i, '26.01').value, 'ACC-0001234567');
    expect(_f(i, '62.01').label, 'Bill number');
    expect(_f(i, '62.05').value, 'REF-9');
    expect(_f(i, '63').validation, FieldValidation.valid);
    expect(_f(i, 'raw').value, raw);
    expect(i.warnings.any((w) => w.contains('not verified who owns')), isTrue);
    expect(i.allFields.every((f) => f.verification == FieldVerification.notVerified), isTrue);
  });

  test('a changed CRC is reported as invalid', () {
    final good = _withCrc(_body);
    final bad = good.substring(0, good.length - 1) + (good.endsWith('0') ? '1' : '0');
    final i = _run(bad);
    expect(_f(i, '63').validation, FieldValidation.invalid);
    expect(i.warnings.any((w) => w.contains('CRC does not match')), isTrue);
  });

  test('a tampered amount breaks the CRC', () {
    final good = _withCrc(_body);
    final altered = good.replaceFirst('150.50', '950.50');
    expect(_f(_run(altered), '63').validation, FieldValidation.invalid);
  });

  test('a static QR without an amount says the amount is not present', () {
    final raw = _withCrc(
      _t('00', '01') + _t('01', '11') + _t('59', 'Shop') + _t('58', 'PK'),
    );
    final i = _run(raw);
    expect(_f(i, '01').value, 'Static (11)');
    expect(_f(i, '54').presence, FieldPresence.notPresent);
    expect(_f(i, '26-51').presence, FieldPresence.notPresent);
  });

  test('a truncated payment QR is reported as malformed', () {
    final good = _withCrc(_body);
    final i = _run(good.substring(0, good.length - 2));
    expect(i.formatName, contains('malformed'));
    expect(_f(i, 'structure').validation, FieldValidation.invalid);
    expect(_f(i, 'raw').value, good.substring(0, good.length - 2));
  });

  test('account identifiers and the raw payload are hidden in exports', () {
    final raw = _withCrc(_body);
    final i = _run(raw);
    final hidden = i.toJson().toString();
    expect(hidden, isNot(contains('ACC-0001234567')));
    expect(hidden, contains('Test Shop'));
    expect(i.toJson(includeSensitive: true).toString(), contains('ACC-0001234567'));
  });

  test('lengths count UTF-8 bytes, so non-ASCII names parse', () {
    final raw = _withCrc(_t('00', '01') + _t('59', 'Caf\u00e9') + _t('58', 'PK'));
    expect(_f(_run(raw), '59').value, 'Caf\u00e9');
    expect(_f(_run(raw), '63').validation, FieldValidation.valid);
  });

  test('other text is not treated as a payment QR', () {
    expect(_run('hello').interpreterId, 'none');
    expect(_run('0002011234').interpreterId, 'none');
  });
}