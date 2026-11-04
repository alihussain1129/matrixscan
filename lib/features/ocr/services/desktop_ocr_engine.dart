import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/ocr_result.dart';
import 'image_prep.dart';
import 'ocr_engine.dart';
import 'tesseract_locator.dart';

/// Offline OCR engine for Linux and Windows desktop using Tesseract OCR.
class DesktopOcrEngine implements OcrEngine {
  DesktopOcrEngine({
    this.maxSide = 3200,
    this.customExecutablePath,
    this.language = 'eng',
  });

  final int maxSide;
  final String? customExecutablePath;
  final String language;

  @override
  String get name => 'Tesseract OCR (offline)';

  @override
  String get script => 'Latin';

  String? _resolvedExecutable;
  Map<String, String>? _resolvedEnvironment;
  Future<String?>? _discoveryFuture;

  /// Locates Tesseract and verifies that it can report its installed languages.
  Future<String?> findExecutable() {
    return _discoveryFuture ??= _discoverExecutable();
  }

  Future<String?> _discoverExecutable() async {
    final installation = await TesseractLocator.discover(
      customExecutablePath: customExecutablePath,
    );
    _resolvedExecutable = installation?.executable;
    _resolvedEnvironment = installation?.environment;
    return _resolvedExecutable;
  }

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

      final exe = await findExecutable();
      if (exe == null) {
        return fail(
          OcrError.of(
            OcrErrorType.engineUnavailable,
            technical: 'Tesseract OCR executable not found on desktop system.',
          ),
        );
      }

      final sw = Stopwatch()..start();
      final result = await Process.run(
        exe,
        [prepared.path, 'stdout', '--psm', '3', '-l', language, 'tsv'],
        environment: _resolvedEnvironment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final recognition = sw.elapsed;

      if (result.exitCode != 0) {
        final err = result.stderr.toString().trim();
        debugPrint('[EXALTED][OCR] Tesseract error: $err');
        return fail(
          OcrError.of(OcrErrorType.failed, technical: err),
          recognition: recognition,
        );
      }

      final tsvOutput = result.stdout.toString();
      final blocks = parseTesseractTsv(tsvOutput);

      final fullTextBuffer = StringBuffer();
      for (final b in blocks) {
        if (fullTextBuffer.isNotEmpty) fullTextBuffer.writeln();
        fullTextBuffer.write(b.text);
      }
      final fullText = fullTextBuffer.toString().trim();

      if (fullText.isEmpty) {
        return fail(
          OcrError.of(OcrErrorType.noTextFound),
          recognition: recognition,
        );
      }

      return OcrResult(
        success: true,
        fullText: fullText,
        blocks: blocks,
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
      debugPrint('[EXALTED][OCR] Prep failed: $e');
      return fail(e.error);
    } on FileSystemException catch (e) {
      return fail(OcrError.of(OcrErrorType.unsupportedImage, technical: '$e'));
    } catch (e) {
      debugPrint('[EXALTED][OCR] Desktop OCR error: $e');
      return fail(OcrError.of(OcrErrorType.failed, technical: '$e'));
    } finally {
      await prepared?.cleanup();
    }
  }

  /// Parses Tesseract TSV output into a hierarchy of [OcrBlock], [OcrLine], and [OcrWord].
  static List<OcrBlock> parseTesseractTsv(String tsv) {
    final lines = tsv.split('\n');
    if (lines.length <= 1) return const [];

    // Map: blockNum -> (Map: lineKey -> List<OcrWord>)
    final blockMap = <int, Map<String, List<OcrWord>>>{};
    final lineConfidenceMap = <String, List<double>>{};

    for (var i = 1; i < lines.length; i++) {
      final row = lines[i].trim();
      if (row.isEmpty) continue;
      final cols = row.split('\t');
      if (cols.length < 12) continue;

      final level = int.tryParse(cols[0]) ?? 0;
      if (level != 5) continue; // Level 5 is word

      final blockNum = int.tryParse(cols[2]) ?? 0;
      final parNum = int.tryParse(cols[3]) ?? 0;
      final lineNum = int.tryParse(cols[4]) ?? 0;
      final left = double.tryParse(cols[6]) ?? 0.0;
      final top = double.tryParse(cols[7]) ?? 0.0;
      final width = double.tryParse(cols[8]) ?? 0.0;
      final height = double.tryParse(cols[9]) ?? 0.0;
      final confVal = double.tryParse(cols[10]) ?? -1.0;
      final text = cols[11].trim();

      if (text.isEmpty) continue;

      final word = OcrWord(
        text: text,
        boundingBox: Rect.fromLTWH(left, top, width, height),
      );

      final lineKey = '$blockNum:$parNum:$lineNum';
      final lineWords = blockMap
          .putIfAbsent(blockNum, () => <String, List<OcrWord>>{})
          .putIfAbsent(lineKey, () => <OcrWord>[]);

      lineWords.add(word);

      if (confVal >= 0) {
        lineConfidenceMap
            .putIfAbsent(lineKey, () => <double>[])
            .add(confVal / 100.0);
      }
    }

    final resultBlocks = <OcrBlock>[];

    for (final entry in blockMap.entries) {
      final ocrLines = <OcrLine>[];
      final lineMap = entry.value;

      for (final lineEntry in lineMap.entries) {
        final words = lineEntry.value;
        if (words.isEmpty) continue;

        double minL = words.first.boundingBox.left;
        double minT = words.first.boundingBox.top;
        double maxR = words.first.boundingBox.right;
        double maxB = words.first.boundingBox.bottom;

        final lineTextBuf = StringBuffer();
        for (var w = 0; w < words.length; w++) {
          if (w > 0) lineTextBuf.write(' ');
          lineTextBuf.write(words[w].text);

          final box = words[w].boundingBox;
          minL = math.min(minL, box.left);
          minT = math.min(minT, box.top);
          maxR = math.max(maxR, box.right);
          maxB = math.max(maxB, box.bottom);
        }

        final confs = lineConfidenceMap[lineEntry.key];
        double? lineConf;
        if (confs != null && confs.isNotEmpty) {
          lineConf = confs.reduce((a, b) => a + b) / confs.length;
        }

        ocrLines.add(
          OcrLine(
            text: lineTextBuf.toString(),
            words: words,
            boundingBox: Rect.fromLTRB(minL, minT, maxR, maxB),
            languages: const ['en'],
            confidence: lineConf,
          ),
        );
      }

      if (ocrLines.isEmpty) continue;

      double bMinL = ocrLines.first.boundingBox.left;
      double bMinT = ocrLines.first.boundingBox.top;
      double bMaxR = ocrLines.first.boundingBox.right;
      double bMaxB = ocrLines.first.boundingBox.bottom;

      final blockTextBuf = StringBuffer();
      for (var l = 0; l < ocrLines.length; l++) {
        if (l > 0) blockTextBuf.writeln();
        blockTextBuf.write(ocrLines[l].text);

        final lBox = ocrLines[l].boundingBox;
        bMinL = math.min(bMinL, lBox.left);
        bMinT = math.min(bMinT, lBox.top);
        bMaxR = math.max(bMaxR, lBox.right);
        bMaxB = math.max(bMaxB, lBox.bottom);
      }

      resultBlocks.add(
        OcrBlock(
          text: blockTextBuf.toString(),
          lines: ocrLines,
          boundingBox: Rect.fromLTRB(bMinL, bMinT, bMaxR, bMaxB),
          languages: const ['en'],
        ),
      );
    }

    return resultBlocks;
  }

  @override
  Future<void> dispose() async {
    _resolvedExecutable = null;
    _resolvedEnvironment = null;
    _discoveryFuture = null;
  }
}
