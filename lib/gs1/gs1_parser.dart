import 'gtin.dart';

/// ASCII group separator (FNC1 in a decoded element string).
const String gs1GroupSeparator = '\x1D';

enum Gs1ValueType { numeric, alphanumeric, date, gtin }

/// Length and character rules for one Application Identifier.
class Gs1AiSpec {
  const Gs1AiSpec(this.ai, this.name, this.minLength, this.maxLength, this.type);

  final String ai;
  final String name;
  final int minLength;
  final int maxLength;
  final Gs1ValueType type;

  bool get isFixed => minLength == maxLength;
}

/// Supported AIs. Anything else is kept as an unknown field.
const Map<String, Gs1AiSpec> gs1AiTable = {
  '00': Gs1AiSpec('00', 'SSCC', 18, 18, Gs1ValueType.numeric),
  '01': Gs1AiSpec('01', 'GTIN', 14, 14, Gs1ValueType.gtin),
  '02': Gs1AiSpec('02', 'GTIN of contained items', 14, 14, Gs1ValueType.gtin),
  '10': Gs1AiSpec('10', 'Batch/Lot number', 1, 20, Gs1ValueType.alphanumeric),
  '11': Gs1AiSpec('11', 'Production date', 6, 6, Gs1ValueType.date),
  '13': Gs1AiSpec('13', 'Packaging date', 6, 6, Gs1ValueType.date),
  '15': Gs1AiSpec('15', 'Best before date', 6, 6, Gs1ValueType.date),
  '17': Gs1AiSpec('17', 'Expiration date', 6, 6, Gs1ValueType.date),
  '20': Gs1AiSpec('20', 'Internal product variant', 2, 2, Gs1ValueType.numeric),
  '21': Gs1AiSpec('21', 'Serial number', 1, 20, Gs1ValueType.alphanumeric),
  '30': Gs1AiSpec('30', 'Variable count', 1, 8, Gs1ValueType.numeric),
  '37': Gs1AiSpec('37', 'Count of trade items', 1, 8, Gs1ValueType.numeric),
  '240': Gs1AiSpec('240', 'Additional product ID', 1, 30, Gs1ValueType.alphanumeric),
  '250': Gs1AiSpec('250', 'Secondary serial number', 1, 30, Gs1ValueType.alphanumeric),
};

/// A GS1 date (YYMMDD). [day] 0 means "day not specified".
class Gs1Date {
  const Gs1Date({
    required this.raw,
    required this.year,
    required this.month,
    required this.day,
  });

  final String raw;
  final int year;
  final int month;
  final int day;

  bool get dayUnspecified => day == 0;

  /// The date; for an unspecified day, the last day of the month.
  DateTime get date =>
      DateTime(year, month, dayUnspecified ? _daysIn(year, month) : day);

  String get display {
    final d = date;
    final text =
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return dayUnspecified ? '$text (day not specified; end of month)' : text;
  }
}

int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

/// Parses YYMMDD. Returns null when it is not a real date.
///
/// UNVERIFIED against the GS1 General Specifications (written from memory):
/// day 00 = end of month, and the century is chosen so the year lies within
/// 50 years back or 49 years ahead of [now].
Gs1Date? parseGs1Date(String yymmdd, {DateTime? now}) {
  if (yymmdd.length != 6 || !RegExp(r'^[0-9]{6}$').hasMatch(yymmdd)) {
    return null;
  }
  final today = now ?? DateTime.now();
  final yy = int.parse(yymmdd.substring(0, 2));
  final month = int.parse(yymmdd.substring(2, 4));
  final day = int.parse(yymmdd.substring(4, 6));

  var year = today.year ~/ 100 * 100 + yy;
  if (year - today.year > 49) {
    year -= 100;
  } else if (today.year - year > 50) {
    year += 100;
  }

  if (month < 1 || month > 12) return null;
  if (day < 0 || day > _daysIn(year, month)) return null;
  return Gs1Date(raw: yymmdd, year: year, month: month, day: day);
}

enum Gs1FieldStatus { valid, invalid, unknownAi }

class Gs1Field {
  const Gs1Field({
    required this.ai,
    required this.name,
    required this.value,
    required this.display,
    required this.status,
    this.error,
  });

  final String ai;
  final String name;

  /// Exactly as encoded.
  final String value;

  /// Human-readable form (for dates, an ISO date).
  final String display;
  final Gs1FieldStatus status;
  final String? error;

  bool get isValid => status == Gs1FieldStatus.valid;
}

enum Gs1Form { parenthesized, elementString }

class Gs1ParseResult {
  const Gs1ParseResult({
    required this.original,
    required this.form,
    required this.fields,
    this.symbologyPrefix,
    this.unparsed = '',
  });

  /// The text that was parsed, unchanged.
  final String original;
  final Gs1Form form;
  final List<Gs1Field> fields;

  /// For example "]d2", when the input started with one.
  final String? symbologyPrefix;

  /// Trailing text that could not be split into fields.
  final String unparsed;

  bool get hasErrors => unparsed.isNotEmpty || fields.any((f) => !f.isValid);

  Gs1Field? field(String ai) {
    for (final f in fields) {
      if (f.ai == ai) return f;
    }
    return null;
  }
}

final RegExp _digits = RegExp(r'^[0-9]+$');
final RegExp _printable = RegExp(r'^[\x21-\x7E]+$');
final RegExp _aiMarker = RegExp(r'\((\d{2,4})\)');
final RegExp _symbologyPrefix = RegExp(r'^\](d2|C1|e0|Q3)');

String? _validate(Gs1AiSpec spec, String v, DateTime? now) {
  if (v.length < spec.minLength || v.length > spec.maxLength) {
    return spec.isFixed
        ? 'must be exactly ${spec.maxLength} characters, got ${v.length}'
        : 'length ${v.length} is outside ${spec.minLength}-${spec.maxLength}';
  }
  switch (spec.type) {
    case Gs1ValueType.numeric:
      if (!_digits.hasMatch(v)) return 'must contain digits only';
    case Gs1ValueType.alphanumeric:
      if (!_printable.hasMatch(v)) return 'contains unsupported characters';
    case Gs1ValueType.date:
      if (parseGs1Date(v, now: now) == null) {
        return 'not a valid date (YYMMDD)';
      }
    case Gs1ValueType.gtin:
      final r = validateGtin(v);
      if (!r.isValid) return r.label;
  }
  return null;
}

Gs1Field _makeField(String ai, String value, DateTime? now) {
  final spec = gs1AiTable[ai];
  if (spec == null) {
    return Gs1Field(
      ai: ai,
      name: 'Unknown AI',
      value: value,
      display: value,
      status: Gs1FieldStatus.unknownAi,
    );
  }
  final error = _validate(spec, value, now);
  var display = value;
  if (error == null && spec.type == Gs1ValueType.date) {
    display = parseGs1Date(value, now: now)!.display;
  }
  return Gs1Field(
    ai: ai,
    name: spec.name,
    value: value,
    display: display,
    status: error == null ? Gs1FieldStatus.valid : Gs1FieldStatus.invalid,
    error: error,
  );
}

/// Parses GS1 data. Returns null when [text] does not look like GS1.
///
/// Handles "(01)...(17)..." text and raw element strings (separated by
/// [gs1GroupSeparator]). A raw string is only attempted when it starts with a
/// symbology prefix such as "]d2", contains a group separator, or
/// [assumeGs1] is true, so ordinary numeric text is not misread.
///
/// This works on text only. It cannot confirm that the symbol itself was
/// encoded as GS1; that needs the symbology identifier from the native core.
Gs1ParseResult? parseGs1(
  String text, {
  bool assumeGs1 = false,
  DateTime? now,
}) {
  if (text.startsWith('(')) {
    return _parseParenthesized(text, now);
  }
  final prefix = _symbologyPrefix.firstMatch(text)?.group(0);
  if (prefix != null || assumeGs1 || text.contains(gs1GroupSeparator)) {
    return _parseElementString(text, prefix, now);
  }
  return null;
}

Gs1ParseResult? _parseParenthesized(String text, DateTime? now) {
  final matches = _aiMarker.allMatches(text).toList();
  if (matches.isEmpty || matches.first.start != 0) return null;
  final fields = <Gs1Field>[];
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    final value = text.substring(m.end, end).replaceAll(gs1GroupSeparator, '');
    fields.add(_makeField(m.group(1)!, value, now));
  }
  return Gs1ParseResult(
    original: text,
    form: Gs1Form.parenthesized,
    fields: List.unmodifiable(fields),
  );
}

Gs1AiSpec? _specAt(String s, int i) {
  for (var n = 2; n <= 4 && i + n <= s.length; n++) {
    final spec = gs1AiTable[s.substring(i, i + n)];
    if (spec != null) return spec;
  }
  return null;
}

Gs1ParseResult? _parseElementString(String text, String? prefix, DateTime? now) {
  var i = prefix?.length ?? 0;
  final fields = <Gs1Field>[];
  var unparsed = '';
  while (i < text.length) {
    if (text[i] == gs1GroupSeparator) {
      i++;
      continue;
    }
    final spec = _specAt(text, i);
    if (spec == null) {
      unparsed = text.substring(i);
      break;
    }
    i += spec.ai.length;
    var sep = text.indexOf(gs1GroupSeparator, i);
    if (sep < 0) sep = text.length;
    final end = spec.isFixed ? (i + spec.maxLength).clamp(i, sep) : sep;
    fields.add(_makeField(spec.ai, text.substring(i, end), now));
    i = end;
  }
  if (fields.isEmpty) return null;
  return Gs1ParseResult(
    original: text,
    form: Gs1Form.elementString,
    fields: List.unmodifiable(fields),
    symbologyPrefix: prefix,
    unparsed: unparsed,
  );
}