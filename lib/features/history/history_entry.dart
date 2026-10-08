/// What a history entry holds.
enum HistoryKind { barcode, ocr }

/// How the entry reached the app.
enum HistorySource { live, gallery, ocr }

/// One saved scan or OCR text.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.kind,
    required this.source,
    required this.text,
    required this.createdAt,
    this.format,
    this.pinned = false,
  });

  final String id;
  final HistoryKind kind;
  final HistorySource source;
  final String text;
  final DateTime createdAt;

  /// Symbology label such as "QR Code"; null for OCR text.
  final String? format;
  final bool pinned;

  HistoryEntry copyWith({bool? pinned}) => HistoryEntry(
    id: id,
    kind: kind,
    source: source,
    text: text,
    createdAt: createdAt,
    format: format,
    pinned: pinned ?? this.pinned,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'source': source.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'format': format,
    'pinned': pinned,
  };

  static HistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final kind = json['kind'];
    final source = json['source'];
    final text = json['text'];
    final created = json['createdAt'];
    if (id is! String ||
        kind is! String ||
        source is! String ||
        text is! String ||
        created is! String) {
      return null;
    }
    final date = DateTime.tryParse(created);
    final kindValue = HistoryKind.values.asNameMap()[kind];
    final sourceValue = HistorySource.values.asNameMap()[source];
    if (date == null || kindValue == null || sourceValue == null) return null;
    final format = json['format'];
    return HistoryEntry(
      id: id,
      kind: kindValue,
      source: sourceValue,
      text: text,
      createdAt: date,
      format: format is String ? format : null,
      pinned: json['pinned'] == true,
    );
  }
}
