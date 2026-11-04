import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'frame_pipeline.dart';

/// Live OCR on the camera stream, on every platform.
///
/// Android: ML Kit reads NV21 built from the grayscale plane.
/// Linux/Windows: the grayscale frame is written as a PGM file and read by
/// the Tesseract command-line tool. In both cases analyze() returns at once,
/// so the barcode decoder is never held up. One read at a time.
class LiveOcrAnalyzer implements FrameAnalyzer {
  LiveOcrAnalyzer({int? minIntervalMs})
    : minIntervalMs = minIntervalMs ?? (Platform.isAndroid ? 400 : 700);

  final int minIntervalMs;

  /// Latest recognized text (empty when nothing was read).
  final ValueNotifier<String> text = ValueNotifier<String>('');

  /// Duration of the last read, in milliseconds.
  final ValueNotifier<int> lastMs = ValueNotifier<int>(0);

  TextRecognizer? _recognizer;
  Directory? _tmp;
  String? _tesseract;
  bool _tesseractChecked = false;
  bool _busy = false;
  bool _disposed = false;
  int _lastStartMs = -1000000;
  final Stopwatch _clock = Stopwatch()..start();

  @override
  String get name => 'live_ocr';

  @override
  Future<void> analyze(AnalysisFrame frame) async {
    if (_disposed || _busy) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastStartMs < minIntervalMs) return;
    _busy = true;
    _lastStartMs = now;
    try {
      // Copied synchronously: yPlane is shared with the camera plugin.
      if (Platform.isAndroid) {
        unawaited(_recognizeAndroid(_toNv21(frame), frame));
      } else {
        unawaited(
          _recognizeDesktop(_toGray(frame), frame.width, frame.height),
        );
      }
    } catch (e) {
      _busy = false;
      debugPrint('[EXALTED][LIVE_OCR] error: $e');
    }
  }

  void _publish(String t, int ms) {
    if (_disposed) return;
    lastMs.value = ms;
    if (t != text.value) {
      text.value = t;
      debugPrint(
        '[EXALTED][LIVE_OCR] ${ms}ms "${t.replaceAll('\n', ' | ')}"',
      );
    }
  }

  // ---- Android: ML Kit ----------------------------------------------------

  Future<void> _recognizeAndroid(Uint8List nv21, AnalysisFrame frame) async {
    try {
      final rotation = InputImageRotation.values.firstWhere(
        (r) => r.rawValue == frame.rotationDegrees,
        orElse: () => InputImageRotation.rotation0deg,
      );
      final input = InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: frame.width,
        ),
      );
      final recognizer =
          _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final sw = Stopwatch()..start();
      final result = await recognizer.processImage(input);
      _publish(result.text.trim(), sw.elapsedMilliseconds);
    } catch (e) {
      debugPrint('[EXALTED][LIVE_OCR] error: $e');
    } finally {
      _busy = false;
    }
  }

  // ---- Linux / Windows: Tesseract -----------------------------------------

  Future<String?> _findTesseract() async {
    if (_tesseractChecked) return _tesseract;
    _tesseractChecked = true;
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'tesseract',
      ]);
      if (r.exitCode == 0) {
        final first = r.stdout.toString().split('\n').first.trim();
        if (first.isNotEmpty) return _tesseract = first;
      }
    } catch (_) {}
    if (Platform.isWindows) {
      const p = r'C:\Program Files\Tesseract-OCR\tesseract.exe';
      if (File(p).existsSync()) return _tesseract = p;
    }
    debugPrint(
      '[EXALTED][LIVE_OCR] tesseract not found. '
      'Install it and put it on PATH for live OCR on this OS.',
    );
    return null;
  }

  Future<void> _recognizeDesktop(Uint8List gray, int w, int h) async {
    try {
      final exe = await _findTesseract();
      if (exe == null || _disposed) return;
      final dir = _tmp ??= await Directory.systemTemp.createTemp(
        'exalted_live_ocr_',
      );
      final file = File('${dir.path}${Platform.pathSeparator}live.pgm');
      final header = Uint8List.fromList('P5\n$w $h\n255\n'.codeUnits);
      final out = Uint8List(header.length + gray.length)
        ..setRange(0, header.length, header)
        ..setRange(header.length, header.length + gray.length, gray);
      await file.writeAsBytes(out, flush: true);
      final sw = Stopwatch()..start();
      final r = await Process.run(exe, [
        file.path,
        'stdout',
        '--psm',
        '6',
        '-l',
        'eng',
      ]);
      _publish(r.stdout.toString().trim(), sw.elapsedMilliseconds);
    } catch (e) {
      debugPrint('[EXALTED][LIVE_OCR] error: $e');
    } finally {
      _busy = false;
    }
  }

  // ---- Frame conversion ---------------------------------------------------

  static Uint8List _toGray(AnalysisFrame f) {
    final w = f.width;
    final h = f.height;
    if (f.yRowStride == w) {
      return Uint8List.fromList(
        Uint8List.sublistView(f.yPlane, 0, w * h),
      );
    }
    final out = Uint8List(w * h);
    for (var row = 0; row < h; row++) {
      out.setRange(row * w, row * w + w, f.yPlane, row * f.yRowStride);
    }
    return out;
  }

  static Uint8List _toNv21(AnalysisFrame f) {
    final w = f.width;
    final h = f.height;
    final ySize = w * h;
    final uvSize = w * ((h + 1) ~/ 2);
    final out = Uint8List(ySize + uvSize);
    out.setRange(0, ySize, _toGray(f));
    out.fillRange(ySize, ySize + uvSize, 128);
    return out;
  }

  @override
  void dispose() {
    _disposed = true;
    final r = _recognizer;
    _recognizer = null;
    r?.close();
    final d = _tmp;
    _tmp = null;
    if (d != null) {
      d.delete(recursive: true).catchError((_) => d);
    }
  }
}

final liveOcrAnalyzerProvider = Provider<LiveOcrAnalyzer>((ref) {
  // The pipeline disposes its analyzers, so no onDispose here.
  return LiveOcrAnalyzer();
});
