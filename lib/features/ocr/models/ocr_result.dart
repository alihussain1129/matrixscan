import 'dart:ui';

import 'package:flutter/foundation.dart';

enum OcrErrorType {
  noTextFound,
  unsupportedImage,
  corruptImage,
  engineUnavailable,
  failed,
}

/// A user-friendly OCR error. [technical] is for logs only, never shown.
@immutable
class OcrError {
  const OcrError({
    required this.type,
    required this.message,
    required this.hint,
    this.technical,
  });

  factory OcrError.of(OcrErrorType type, {String? technical}) {
    switch (type) {
      case OcrErrorType.noTextFound:
        return OcrError(
          type: type,
          message: 'No readable text found.',
          hint: 'Try a clearer image with better lighting and larger text.',
          technical: technical,
        );
      case OcrErrorType.unsupportedImage:
        return OcrError(
          type: type,
          message: "Couldn't process this image.",
          hint: 'Pick a JPG, PNG or WebP photo or screenshot.',
          technical: technical,
        );
      case OcrErrorType.corruptImage:
        return OcrError(
          type: type,
          message: 'This image looks damaged.',
          hint: 'Try saving it again, or pick another image.',
          technical: technical,
        );
      case OcrErrorType.engineUnavailable:
        return OcrError(
          type: type,
          message: "Text recognition isn't available.",
          hint: 'Restart Exalted. If it keeps happening, reinstall the app.',
          technical: technical,
        );
      case OcrErrorType.failed:
        return OcrError(
          type: type,
          message: 'Something went wrong while reading the image.',
          hint: 'Try again, or pick a smaller image.',
          technical: technical,
        );
    }
  }

  final OcrErrorType type;
  final String message;
  final String hint;
  final String? technical;
}

class OcrException implements Exception {
  const OcrException(this.error);

  final OcrError error;

  @override
  String toString() =>
      'OcrException(${error.type.name}: ${error.technical ?? error.message})';
}

@immutable
class OcrWord {
  const OcrWord({required this.text, required this.boundingBox});

  final String text;
  final Rect boundingBox;
}

@immutable
class OcrLine {
  const OcrLine({
    required this.text,
    required this.words,
    required this.boundingBox,
    required this.languages,
    this.confidence,
  });

  final String text;
  final List<OcrWord> words;
  final Rect boundingBox;
  final List<String> languages;

  /// 0..1, or null when the engine did not provide one.
  final double? confidence;
}

@immutable
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.lines,
    required this.boundingBox,
    required this.languages,
  });

  final String text;
  final List<OcrLine> lines;
  final Rect boundingBox;
  final List<String> languages;
}

@immutable
class OcrResult {
  const OcrResult({
    required this.success,
    this.fullText = '',
    this.blocks = const [],
    this.prepTime = Duration.zero,
    this.recognitionTime = Duration.zero,
    this.imageWidth,
    this.imageHeight,
    this.analyzedWidth,
    this.analyzedHeight,
    this.engine = '',
    this.script = '',
    this.error,
  });

  factory OcrResult.failure(
    OcrError error, {
    Duration prepTime = Duration.zero,
    Duration recognitionTime = Duration.zero,
    int? imageWidth,
    int? imageHeight,
    int? analyzedWidth,
    int? analyzedHeight,
    String engine = '',
    String script = '',
  }) {
    return OcrResult(
      success: false,
      error: error,
      prepTime: prepTime,
      recognitionTime: recognitionTime,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      analyzedWidth: analyzedWidth,
      analyzedHeight: analyzedHeight,
      engine: engine,
      script: script,
    );
  }

  final bool success;
  final String fullText;
  final List<OcrBlock> blocks;
  final Duration prepTime;
  final Duration recognitionTime;

  /// Size of the original image.
  final int? imageWidth;
  final int? imageHeight;

  /// Size actually given to the engine (smaller when the image was resized).
  final int? analyzedWidth;
  final int? analyzedHeight;

  final String engine;
  final String script;
  final OcrError? error;

  Duration get processingTime => prepTime + recognitionTime;

  bool get resized =>
      imageWidth != null &&
      analyzedWidth != null &&
      (imageWidth != analyzedWidth || imageHeight != analyzedHeight);

  List<OcrLine> get lines => [for (final b in blocks) ...b.lines];

  List<OcrWord> get words => [for (final l in lines) ...l.words];

  /// Language codes reported by the engine. Empty when not available.
  List<String> get languages {
    final set = <String>{};
    for (final b in blocks) {
      set.addAll(b.languages);
    }
    return set.toList()..sort();
  }

  String get language => languages.join(', ');

  /// Average of the line confidences the engine provided, or null.
  double? get confidence {
    final values = <double>[
      for (final l in lines)
        if (l.confidence != null) l.confidence!,
    ];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
