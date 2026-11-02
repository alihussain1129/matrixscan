import 'dart:convert';

/// An immutable inspection and recognition record created by the OCR Workspace.
///
/// Holds the recognized text, verification state, engine metadata, and a permanent
/// reference to the immutable stored image.
class OcrRecord {
  const OcrRecord({
    required this.id,
    required this.imagePath,
    required this.text,
    required this.rawText,
    required this.createdAt,
    this.language = 'eng',
    this.engine = 'Tesseract',
    this.confidence = 0.0,
    this.processingDurationMs = 0,
    this.blockCount = 0,
    this.lineCount = 0,
    this.wordCount = 0,
    this.ocvPattern,
    this.ocvPassed,
    this.pinned = false,
    this.metadata = const {},
  });

  final String id;
  final String imagePath;
  final String text;
  final String rawText;
  final DateTime createdAt;
  final String language;
  final String engine;
  final double confidence;
  final int processingDurationMs;
  final int blockCount;
  final int lineCount;
  final int wordCount;
  final String? ocvPattern;
  final bool? ocvPassed;
  final bool pinned;
  final Map<String, dynamic> metadata;

  OcrRecord copyWith({
    String? text,
    bool? pinned,
    String? ocvPattern,
    bool? ocvPassed,
    Map<String, dynamic>? metadata,
  }) {
    return OcrRecord(
      id: id,
      imagePath: imagePath,
      text: text ?? this.text,
      rawText: rawText,
      createdAt: createdAt,
      language: language,
      engine: engine,
      confidence: confidence,
      processingDurationMs: processingDurationMs,
      blockCount: blockCount,
      lineCount: lineCount,
      wordCount: wordCount,
      ocvPattern: ocvPattern ?? this.ocvPattern,
      ocvPassed: ocvPassed ?? this.ocvPassed,
      pinned: pinned ?? this.pinned,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'text': text,
        'rawText': rawText,
        'createdAt': createdAt.toIso8601String(),
        'language': language,
        'engine': engine,
        'confidence': confidence,
        'processingDurationMs': processingDurationMs,
        'blockCount': blockCount,
        'lineCount': lineCount,
        'wordCount': wordCount,
        'ocvPattern': ocvPattern,
        'ocvPassed': ocvPassed,
        'pinned': pinned,
        'metadata': metadata,
      };

  static OcrRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final imagePath = json['imagePath'];
    final text = json['text'];
    final created = json['createdAt'];

    if (id is! String ||
        imagePath is! String ||
        text is! String ||
        created is! String) {
      return null;
    }

    final date = DateTime.tryParse(created);
    if (date == null) return null;

    final rawText = json['rawText'] is String ? json['rawText'] as String : text;
    final language = json['language'] is String ? json['language'] as String : 'eng';
    final engine = json['engine'] is String ? json['engine'] as String : 'Tesseract';
    final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
    final duration = (json['processingDurationMs'] as num?)?.toInt() ?? 0;
    final blockCount = (json['blockCount'] as num?)?.toInt() ?? 0;
    final lineCount = (json['lineCount'] as num?)?.toInt() ?? 0;
    final wordCount = (json['wordCount'] as num?)?.toInt() ?? 0;
    final ocvPattern = json['ocvPattern'] as String?;
    final ocvPassed = json['ocvPassed'] as bool?;
    final pinned = json['pinned'] == true;
    final metadata = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : <String, dynamic>{};

    return OcrRecord(
      id: id,
      imagePath: imagePath,
      text: text,
      rawText: rawText,
      createdAt: date,
      language: language,
      engine: engine,
      confidence: confidence,
      processingDurationMs: duration,
      blockCount: blockCount,
      lineCount: lineCount,
      wordCount: wordCount,
      ocvPattern: ocvPattern,
      ocvPassed: ocvPassed,
      pinned: pinned,
      metadata: metadata,
    );
  }
}
