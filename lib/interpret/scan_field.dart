/// Where a value came from.
enum FieldOrigin { decoded, parsed, calculated, local, external }

/// Whether the value exists. "Not present" and "empty" are different things.
enum FieldPresence { present, empty, notPresent, unsupported, unavailable }

enum FieldValidation { notChecked, valid, invalid }

/// Set to [verified] only when a real check against a source supports it.
enum FieldVerification { notVerified, verified, mismatch }

/// One piece of information about a scanned code.
class ScanField {
  const ScanField({
    required this.label,
    this.id,
    this.value,
    this.original,
    this.standard,
    this.dataType,
    this.unit,
    this.origin = FieldOrigin.parsed,
    this.presence = FieldPresence.present,
    this.validation = FieldValidation.notChecked,
    this.verification = FieldVerification.notVerified,
    this.note,
    this.warning,
    this.sensitive = false,
    this.updatedAt,
  });

  /// A field the code does not contain.
  const ScanField.notPresent(this.label, {this.id, this.standard})
    : value = null,
      original = null,
      dataType = null,
      unit = null,
      origin = FieldOrigin.parsed,
      presence = FieldPresence.notPresent,
      validation = FieldValidation.notChecked,
      verification = FieldVerification.notVerified,
      note = null,
      warning = null,
      sensitive = false,
      updatedAt = null;

  final String label;

  /// Identifier such as a GS1 Application Identifier.
  final String? id;
  final String? value;

  /// The value exactly as encoded, when [value] was transformed.
  final String? original;
  final String? standard;
  final String? dataType;
  final String? unit;
  final FieldOrigin origin;
  final FieldPresence presence;
  final FieldValidation validation;
  final FieldVerification verification;
  final String? note;
  final String? warning;

  /// Mask by default and leave out of exports unless asked.
  final bool sensitive;
  final DateTime? updatedAt;

  Map<String, Object?> toJson({bool includeSensitive = false}) {
    final hide = sensitive && !includeSensitive;
    return {
      'label': label,
      'id': id,
      'value': hide && value != null ? '[hidden]' : value,
      'original': hide && original != null ? '[hidden]' : original,
      'standard': standard,
      'dataType': dataType,
      'unit': unit,
      'origin': origin.name,
      'presence': presence.name,
      'validation': validation.name,
      'verification': verification.name,
      'note': note,
      'warning': warning,
      'sensitive': sensitive,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

/// A titled group of fields; sections can nest.
class ScanSection {
  ScanSection({
    required this.id,
    required this.title,
    List<ScanField> fields = const [],
    List<ScanSection> sections = const [],
  }) : fields = List.unmodifiable(fields),
       sections = List.unmodifiable(sections);

  final String id;
  final String title;
  final List<ScanField> fields;
  final List<ScanSection> sections;

  /// Every field in this section and below.
  Iterable<ScanField> get allFields sync* {
    yield* fields;
    for (final s in sections) {
      yield* s.allFields;
    }
  }

  Map<String, Object?> toJson({bool includeSensitive = false}) => {
    'id': id,
    'title': title,
    'fields': [
      for (final f in fields) f.toJson(includeSensitive: includeSensitive),
    ],
    'sections': [
      for (final s in sections) s.toJson(includeSensitive: includeSensitive),
    ],
  };
}