import 'package:exalted/interpret/interpreter.dart';
import 'package:exalted/interpret/scan_field.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixed implements PayloadInterpreter {
  _Fixed(this.id, this.prefix);
  @override
  final String id;
  final String prefix;
  @override
  Interpretation? interpret(ScanPayload p) {
    if (!p.raw.startsWith(prefix)) return null;
    return Interpretation(
      interpreterId: id,
      formatName: 'Format $id',
      sections: [
        ScanSection(
          id: 'main',
          title: 'Main',
          fields: [ScanField(label: 'Body', value: p.raw.substring(prefix.length))],
        ),
      ],
    );
  }
}

class _Throws implements PayloadInterpreter {
  @override
  String get id => 'boom';
  @override
  Interpretation? interpret(ScanPayload p) =>
      throw StateError('secret ${p.raw}');
}

ScanPayload _p(String raw) => ScanPayload(
  raw: raw,
  symbology: 'QR Code',
  source: 'live',
  scannedAt: DateTime.utc(2026, 10, 9, 12),
);

String _value(Interpretation i, String section, String id) =>
    i.section(section)!.fields.firstWhere((f) => f.id == id).value!;

void main() {
  test('raw payload is preserved exactly, control characters included', () {
    final registry = InterpreterRegistry([]);
    const raw = 'A\x1DB\x1D C';
    final i = registry.interpret(_p(raw));
    expect(_value(i, 'raw', 'raw'), raw);
    expect(_value(i, 'raw', 'chars'), '6');
    expect(_value(i, 'raw', 'control'), 'U+001D x2');
  });

  test('plain text has no control characters, reported as not present', () {
    final i = InterpreterRegistry([]).interpret(_p('hello'));
    final f = i.section('raw')!.fields.firstWhere((f) => f.id == 'control');
    expect(f.presence, FieldPresence.notPresent);
    expect(f.value, isNull);
  });

  test('byte length counts UTF-8 bytes, not characters', () {
    final i = InterpreterRegistry([]).interpret(_p('\u00e9'));
    expect(_value(i, 'raw', 'chars'), '1');
    expect(_value(i, 'raw', 'bytes'), '2');
  });

  test('unknown format is reported and keeps raw and technical sections', () {
    final i = InterpreterRegistry([_Fixed('a', 'X:')]).interpret(_p('zzz'));
    expect(i.formatName, 'Unknown format');
    expect(i.interpreterId, 'none');
    expect(i.warnings.single, contains('No interpreter recognised'));
    expect(i.sections.map((s) => s.id), ['raw', 'technical']);
  });

  test('first matching interpreter wins and raw sections follow it', () {
    final registry = InterpreterRegistry([
      _Fixed('first', 'X:'),
      _Fixed('second', 'X:'),
    ]);
    final i = registry.interpret(_p('X:body'));
    expect(i.interpreterId, 'first');
    expect(i.sections.map((s) => s.id), ['main', 'raw', 'technical']);
    expect(_value(i, 'technical', 'interpreter'), 'first');
  });

  test('a throwing interpreter is isolated and reported without its message', () {
    final registry = InterpreterRegistry([_Throws(), _Fixed('ok', 'X:')]);
    final i = registry.interpret(_p('X:body'));
    expect(i.interpreterId, 'ok');
    expect(i.warnings.single, contains('failed'));
    final err = _value(i, 'technical', 'errors');
    expect(err, 'boom: StateError');
    expect(err, isNot(contains('secret')));
  });

  test('missing, empty and present are distinguishable', () {
    final empty = InterpreterRegistry([]).interpret(_p(''));
    expect(
      empty.section('raw')!.fields.first.presence,
      FieldPresence.empty,
    );
    expect(
      empty.section('technical')!.fields.firstWhere((f) => f.id == 'errors').presence,
      FieldPresence.notPresent,
    );
  });

  test('sensitive values are hidden in exports unless asked', () {
    final field = const ScanField(
      label: 'Password',
      value: 'hunter2',
      original: 'hunter2',
      sensitive: true,
    );
    expect(field.toJson()['value'], '[hidden]');
    expect(field.toJson()['original'], '[hidden]');
    expect(field.toJson(includeSensitive: true)['value'], 'hunter2');
  });

  test('verification defaults to not verified', () {
    expect(
      const ScanField(label: 'x', value: 'y').verification,
      FieldVerification.notVerified,
    );
  });

  test('export contains nested sections and the raw payload', () {
    final registry = InterpreterRegistry([_Fixed('a', 'X:')]);
    final json = registry.interpret(_p('X:body')).toJson();
    expect(json['format'], 'Format a');
    final text = json.toString();
    expect(text, contains('X:body'));
    expect(text, contains('Technical details'));
  });

  test('allFields walks nested sections', () {
    final section = ScanSection(
      id: 'a',
      title: 'A',
      fields: [const ScanField(label: 'one', value: '1')],
      sections: [
        ScanSection(
          id: 'b',
          title: 'B',
          fields: [const ScanField(label: 'two', value: '2')],
        ),
      ],
    );
    expect(section.allFields.map((f) => f.label), ['one', 'two']);
  });
}