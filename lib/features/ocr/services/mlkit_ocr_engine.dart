import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/ocr_result.dart';
import 'image_prep.dart';
import 'ocr_engine.dart';

/// Offline OCR using Google ML Kit's bundled Latin model.
/// All recognition runs on the device. Nothing is sent anywhere.
class MlKitOcrEngine implements OcrEngine {
  MlKitOcrEngine({this.maxSide = 3200});

  /// Images with a longer side than this are resized before recognition.
  final int maxSide;

  TextRecognizer? _recognizer;

  @override
  String get name => 'Google ML Kit (on-device)';

  @override
  String get script => 'Latin';

  @override
  Future<OcrResult> recognizeFile(String imagePath) async {
    final total = Stopwatch()..start();
    PreparedImage? prepared;
    var prep = Duration.zero;

    OcrResult fail(OcrError error, {Duration? recognition}) {
      return OcrResult.failure(
        error,
        prepTime: prepared == null ? total.elapsed : prep,
        recognitionTime: recognition ?? Duration.zero,
        imageWidth: prepared?.originalWidth,
        imageHeight: prepared?.originalHeight,
        analyzedWidth: prepared?.width,
        analyzedHeight: prepared?.height,
        engine: name,
        script: script,
      );
    }

    try {
      prepared = await ImagePrep.prepare(imagePath, maxSide: maxSide);
      prep = total.elapsed;

      final recognizer = _recognizer ??= TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final sw = Stopwatch()..start();
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(prepared.path),
      );
      final recognition = sw.elapsed;

      if (recognized.text.trim().isEmpty) {
        return fail(
          OcrError.of(OcrErrorType.noTextFound),
          recognition: recognition,
        );
      }

      return OcrResult(
        success: true,
        fullText: recognized.text,
        blocks: [for (final b in recognized.blocks) _mapBlock(b)],
        prepTime: prep,
        recognitionTime: recognition,
        imageWidth: prepared.originalWidth,
        imageHeight: prepared.originalHeight,
        analyzedWidth: prepared.width,
        analyzedHeight: prepared.height,
        engine: name,
        script: script,
      );
    } on OcrException catch (e) {
      debugPrint('OCR failed: $e');
      return fail(e.error);
    } on FileSystemException catch (e) {
      return fail(OcrError.of(OcrErrorType.unsupportedImage, technical: '$e'));
    } on MissingPluginException catch (e) {
      return fail(OcrError.of(OcrErrorType.engineUnavailable, technical: '$e'));
    } on PlatformException catch (e) {
      debugPrint('OCR platform error: $e');
      return fail(OcrError.of(OcrErrorType.failed, technical: '$e'));
    } catch (e) {
      debugPrint('OCR error: $e');
      return fail(OcrError.of(OcrErrorType.failed, technical: '$e'));
    } finally {
      await prepared?.cleanup();
    }
  }

  OcrBlock _mapBlock(TextBlock b) {
    return OcrBlock(
      text: b.text,
      boundingBox: b.boundingBox,
      languages: List<String>.of(b.recognizedLanguages),
      lines: [
        for (final l in b.lines)
          OcrLine(
            text: l.text,
            boundingBox: l.boundingBox,
            languages: List<String>.of(l.recognizedLanguages),
            // Zero means "not provided", so it is treated as unavailable.
            confidence: (l.confidence == null || l.confidence! <= 0)
                ? null
                : l.confidence,
            words: [
              for (final e in l.elements)
                OcrWord(text: e.text, boundingBox: e.boundingBox),
            ],
          ),
      ],
    );
  }

  @override
  Future<void> dispose() async {
    final recognizer = _recognizer;
    _recognizer = null;
    await recognizer?.close();
  }
}
