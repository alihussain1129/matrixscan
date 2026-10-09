import 'dart:convert';

import 'scan_field.dart';

/// What the decoder gave us, before any interpretation.
class ScanPayload {
  const ScanPayload({
    required this.raw,
    required this.symbology,
    this.source,
    this.scannedAt,
  });

  /// Exactly as decoded. Never modified.
  final String raw;
  final String symbology;

  /// For example "live" or "gallery".
  final String? source;
  final DateTime? scannedAt;
}

/// The result of interpreting one payload.
class Interpretation {
  Interpretation({
    required this.interpreterId,
    required this.formatName,
    List<ScanSection> sections = const [],
    List<String> warnings = const [],
    this.rawIsSensitive = false,
  }) : sections = List.unmodifiable(sections),
       warnings = List.unmodifiable(warnings);

  final String interpreterId;
  final String formatName;
  final List<ScanSection> sections;
  final List<String> warnings;

  /// True when the raw payload itself holds a secret (for example a Wi-Fi
  /// password), so exports hide it.
  final bool rawIsSensitive;

  ScanSection? section(String id) {
    for (final s in sections) {
      if (s.id == id) return s;
    }
    return null;
  }

  Iterable<ScanField> get allFields sync* {
    for (final s in sections) {
      yield* s.allFields;
    }
  }

  Map<String, Object?> toJson({bool includeSensitive = false}) => {
    'interpreter': interpreterId,
    'format': formatName,
    'warnings': warnings,
    'sections': [
      for (final s in sections) s.toJson(includeSensitive: includeSensitive),
    ],
  };
}

/// Recognises one kind of payload. Return null when the payload is not yours.
/// Interpreters must not do network or database work.
abstract class PayloadInterpreter {
  String get id;
  Interpretation? interpret(ScanPayload payload);
}

/// Tries interpreters in order; the first match wins. Always adds the raw
/// payload and technical sections, and never loses a scan because an
/// interpreter failed.
class InterpreterRegistry {
  InterpreterRegistry(List<PayloadInterpreter> interpreters)
    : _interpreters = List.unmodifiable(interpreters);

  final List<PayloadInterpreter> _interpreters;

  Interpretation interpret(ScanPayload payload) {
    final errors = <String>[];
    Interpretation? found;
    for (final interpreter in _interpreters) {
      try {
        final result = interpreter.interpret(payload);
        if (result != null) {
          found = result;
          break;
        }
      } catch (e) {
        // Only the type: the message could contain payload data.
        errors.add('${interpreter.id}: ${e.runtimeType}');
      }
    }

    final warnings = <String>[
      ...?found?.warnings,
      if (found == null)
        'No interpreter recognised this payload. The raw data is preserved.',
      if (errors.isNotEmpty)
        'An interpreter failed; other results are still shown.',
    ];

    return Interpretation(
      interpreterId: found?.interpreterId ?? 'none',
      formatName: found?.formatName ?? 'Unknown format',
      sections: [
        ...?found?.sections,
        _rawSection(payload, sensitive: found?.rawIsSensitive ?? false),
        _technicalSection(payload, found, errors),
      ],
      warnings: warnings,
      rawIsSensitive: found?.rawIsSensitive ?? false,
    );
  }
}

ScanSection _rawSection(ScanPayload p, {required bool sensitive}) {
  final controls = <int, int>{};
  for (final unit in p.raw.codeUnits) {
    if (unit < 0x20 || unit == 0x7F) {
      controls[unit] = (controls[unit] ?? 0) + 1;
    }
  }
  final controlText = controls.entries
      .map(
        (e) =>
            'U+${e.key.toRadixString(16).toUpperCase().padLeft(4, '0')}'
            ' x${e.value}',
      )
      .join(', ');

  return ScanSection(
    id: 'raw',
    title: 'Raw payload',
    fields: [
      ScanField(
        id: 'raw',
        label: 'Raw decoded data',
        value: p.raw,
        origin: FieldOrigin.decoded,
        presence: p.raw.isEmpty ? FieldPresence.empty : FieldPresence.present,
        sensitive: sensitive,
      ),
      ScanField(
        id: 'chars',
        label: 'Length (characters)',
        value: '${p.raw.length}',
        origin: FieldOrigin.calculated,
      ),
      ScanField(
        id: 'bytes',
        label: 'Length (UTF-8 bytes)',
        value: '${utf8.encode(p.raw).length}',
        origin: FieldOrigin.calculated,
      ),
      if (controls.isNotEmpty)
        ScanField(
          id: 'control',
          label: 'Control characters',
          value: controlText,
          origin: FieldOrigin.calculated,
          note: 'Invisible characters such as the GS1 group separator.',
        )
      else
        const ScanField.notPresent('Control characters', id: 'control'),
    ],
  );
}

ScanSection _technicalSection(
  ScanPayload p,
  Interpretation? found,
  List<String> errors,
) {
  return ScanSection(
    id: 'technical',
    title: 'Technical details',
    fields: [
      ScanField(
        id: 'symbology',
        label: 'Symbology',
        value: p.symbology,
        origin: FieldOrigin.decoded,
      ),
      p.source == null
          ? const ScanField.notPresent('Scan source', id: 'source')
          : ScanField(
              id: 'source',
              label: 'Scan source',
              value: p.source,
              origin: FieldOrigin.decoded,
            ),
      p.scannedAt == null
          ? const ScanField.notPresent('Scanned at', id: 'scannedAt')
          : ScanField(
              id: 'scannedAt',
              label: 'Scanned at',
              value: p.scannedAt!.toIso8601String(),
              origin: FieldOrigin.decoded,
            ),
      ScanField(
        id: 'interpreter',
        label: 'Interpreter',
        value: found?.interpreterId ?? 'none',
        origin: FieldOrigin.calculated,
      ),
      if (errors.isEmpty)
        const ScanField.notPresent('Interpreter errors', id: 'errors')
      else
        ScanField(
          id: 'errors',
          label: 'Interpreter errors',
          value: errors.join('; '),
          origin: FieldOrigin.calculated,
          validation: FieldValidation.invalid,
        ),
    ],
  );
}