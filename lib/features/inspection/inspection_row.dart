import 'gs1_fields.dart';

enum RowStatus { pass, fail, review }

/// One inspection event as one related data row: the decoded fields, the
/// checks that ran on them, and the outcome.
class InspectionRow {
  const InspectionRow({
    required this.id,
    required this.createdAt,
    required this.source,
    required this.symbology,
    required this.raw,
    required this.fields,
    required this.status,
    this.reasons = const [],
    this.decodeMs,
    this.ocrText,
    this.ocrMs,
    this.duplicateOf,
  });

  final String id;
  final DateTime createdAt;
  final String source;
  final String symbology;
  final String raw;

  /// GS1 element values by application identifier, in print order.
  final Map<String, String> fields;
  final RowStatus status;

  /// Why the row is FAIL or REVIEW. Empty for PASS.
  final List<String> reasons;
  final double? decodeMs;

  /// Text OCR read for this event; null when OCR did not run.
  final String? ocrText;
  final double? ocrMs;
  final String? duplicateOf;

  String? get gtin => fields['01'];
  String? get lot => fields['10'];
  String? get serial => fields['21'];
  String? get expiryDisplay => fields['17'] == null
      ? null
      : Gs1Fields.formatDate(fields['17']!) ?? fields['17'];

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'source': source,
    'symbology': symbology,
    'raw': raw,
    'fields': fields,
    'status': status.name,
    'reasons': reasons,
    'decodeMs': decodeMs,
    'ocrText': ocrText,
    'ocrMs': ocrMs,
    'duplicateOf': duplicateOf,
  };

  static InspectionRow? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final created = json['createdAt'];
    final raw = json['raw'];
    final source = json['source'];
    final symbology = json['symbology'];
    if (id is! String ||
        created is! String ||
        raw is! String ||
        source is! String ||
        symbology is! String) {
      return null;
    }
    final date = DateTime.tryParse(created);
    final status = RowStatus.values.asNameMap()[json['status']];
    if (date == null || status == null) return null;
    final fields = <String, String>{};
    final f = json['fields'];
    if (f is Map) {
      f.forEach((k, v) {
        if (k is String && v is String) fields[k] = v;
      });
    }
    final reasons = json['reasons'];
    return InspectionRow(
      id: id,
      createdAt: date,
      source: source,
      symbology: symbology,
      raw: raw,
      fields: fields,
      status: status,
      reasons: reasons is List ? [for (final r in reasons) '$r'] : const [],
      decodeMs: (json['decodeMs'] as num?)?.toDouble(),
      ocrText: json['ocrText'] as String?,
      ocrMs: (json['ocrMs'] as num?)?.toDouble(),
      duplicateOf: json['duplicateOf'] as String?,
    );
  }
}
