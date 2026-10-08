import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../ffi/decode_result.dart';
import '../../ffi/decoder_service.dart';
import 'frame_pipeline.dart';

/// Diagnostic summary of frames processed by [ScannerAnalyzer].
@immutable
class ScannerAnalyzerStats {
  const ScannerAnalyzerStats({
    this.analyzedFrames = 0,
    this.lastFrameWidth = 0,
    this.lastFrameHeight = 0,
    this.lastRotationDegrees = 0,
  });

  final int analyzedFrames;
  final int lastFrameWidth;
  final int lastFrameHeight;
  final int lastRotationDegrees;

  static const ScannerAnalyzerStats zero = ScannerAnalyzerStats();
}

/// Pipeline analyzer for scanner camera frames.
///
/// Hands every accepted frame's luminance plane to the native C++ core
/// (zxing-cpp behind libexalted_ffi.so) and reports each decoded barcode
/// through [onDecoded]. Contains temporary live-scan diagnostics.
class ScannerAnalyzer implements FrameAnalyzer {
  ScannerAnalyzer({DecoderService? decoder})
    : _decoder = decoder ?? DecoderService(),
      _ownsDecoder = decoder == null;

  final DecoderService _decoder;
  final bool _ownsDecoder;

  void Function(DecodedBarcode barcode)? onDecoded;

  @override
  String get name => 'scanner';

  int _analyzedFrames = 0;
  int _decodedFrames = 0;
  int _attempts = 0;
  int _lastWidth = 0;
  int _lastHeight = 0;
  int _lastRotation = 0;
  bool _disposed = false;
  bool _geometryLogged = false;

  int _windowFrames = 0;
  int _windowMicros = 0;
  int _lastLogMs = 0;
  final Map<int, int> _rcWindow = {};
  final Stopwatch _clock = Stopwatch()..start();

  static const Set<int> _dumpAt = {45, 150, 400};

  int get analyzedFrames => _analyzedFrames;
  int get decodedFrames => _decodedFrames;
  int get lastFrameWidth => _lastWidth;
  int get lastFrameHeight => _lastHeight;
  int get lastRotationDegrees => _lastRotation;
  bool get isDisposed => _disposed;

  ScannerAnalyzerStats get stats => ScannerAnalyzerStats(
    analyzedFrames: _analyzedFrames,
    lastFrameWidth: _lastWidth,
    lastFrameHeight: _lastHeight,
    lastRotationDegrees: _lastRotation,
  );

  @override
  Future<void> analyze(AnalysisFrame frame) async {
    if (_disposed) return;
    _analyzedFrames++;
    _lastWidth = frame.width;
    _lastHeight = frame.height;
    _lastRotation = frame.rotationDegrees;

    if (!_geometryLogged) {
      _geometryLogged = true;
      debugPrint(
        '[EXALTED][GEOMETRY] ${frame.width}x${frame.height} '
        'stride=${frame.yRowStride} yLen=${frame.yPlane.length} '
        'expectedMin=${(frame.height - 1) * frame.yRowStride + frame.width} '
        'width==stride:${frame.width == frame.yRowStride} '
        'rot=${frame.rotationDegrees}',
      );
    }

    // Dump raw frames if nothing has decoded yet (debug only).
    if (!kReleaseMode &&
        _decodedFrames == 0 &&
        _dumpAt.contains(_analyzedFrames)) {
      _dumpFrame(frame, 'f$_analyzedFrames');
    }

    final watch = Stopwatch()..start();
    _attempts++;
    final barcode = await _decoder.decodeAsync(
      luma: frame.yPlane,
      width: frame.width,
      height: frame.height,
      rowStride: frame.yRowStride,
    );
    _windowFrames++;
    _windowMicros += watch.elapsedMicroseconds;
    final rc = _decoder.isAvailable ? _decoder.lastDecodeStatus : -99;
    _rcWindow[rc] = (_rcWindow[rc] ?? 0) + 1;

    if (barcode != null) {
      _decodedFrames++;
      debugPrint('[EXALTED][RESULT] $barcode');
      onDecoded?.call(barcode);
    }

    final nowMs = _clock.elapsedMilliseconds;
    if (_analyzedFrames == 1 || nowMs - _lastLogMs >= 1000) {
      _lastLogMs = nowMs;
      final avgMs = _windowFrames == 0
          ? 0.0
          : _windowMicros / _windowFrames / 1000;
      debugPrint(
        '[EXALTED][ANALYZER] analyzed=$_analyzedFrames attempts=$_attempts '
        'decoded=$_decodedFrames rc=$_rcWindow '
        'avgDecode=${avgMs.toStringAsFixed(1)}ms',
      );
      if (!_decoder.isAvailable) {
        debugPrint('[EXALTED][NATIVE] unavailable: ${_decoder.loadError}');
      } else {
        final probe = _decoder.probe(
          luma: frame.yPlane,
          width: frame.width,
          height: frame.height,
          rowStride: frame.yRowStride,
          rotationDegrees: frame.rotationDegrees,
        );
        debugPrint('[EXALTED][NATIVE] $probe');
      }
      _windowFrames = 0;
      _windowMicros = 0;
      _rcWindow.clear();
    }
  }

  /// Saves the raw Y plane (no rotation) as an 8-bit grayscale BMP so it can
  /// be pulled off the phone and looked at.
  void _dumpFrame(AnalysisFrame f, String tag) {
    final w = f.width;
    final h = f.height;
    final stride = f.yRowStride;
    final y = f.yPlane;
    final rowBytes = (w + 3) & ~3;
    final dataSize = rowBytes * h;
    const headerSize = 54 + 1024;
    final bytes = Uint8List(headerSize + dataSize);
    final bd = ByteData.sublistView(bytes);
    bytes[0] = 0x42;
    bytes[1] = 0x4D;
    bd.setUint32(2, bytes.length, Endian.little);
    bd.setUint32(10, headerSize, Endian.little);
    bd.setUint32(14, 40, Endian.little);
    bd.setInt32(18, w, Endian.little);
    bd.setInt32(22, h, Endian.little);
    bd.setUint16(26, 1, Endian.little);
    bd.setUint16(28, 8, Endian.little);
    bd.setUint32(34, dataSize, Endian.little);
    bd.setUint32(46, 256, Endian.little);
    for (var i = 0; i < 256; i++) {
      final o = 54 + i * 4;
      bytes[o] = i;
      bytes[o + 1] = i;
      bytes[o + 2] = i;
    }
    for (var row = 0; row < h; row++) {
      final src = row * stride;
      if (src + w > y.length) break;
      final dst = headerSize + (h - 1 - row) * rowBytes; // BMP is bottom-up
      bytes.setRange(dst, dst + w, y, src);
    }
    _writeBmp(bytes, tag, w, h);
  }

  Future<void> _writeBmp(Uint8List bytes, String tag, int w, int h) async {
    try {
      final dir =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/exalted_frame_$tag.bmp');
      await file.writeAsBytes(bytes, flush: true);
      debugPrint('[EXALTED][DUMP] ${w}x$h -> ${file.path}');
    } catch (e) {
      debugPrint('[EXALTED][DUMP] failed: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    onDecoded = null;
    if (_ownsDecoder) _decoder.dispose();
  }
}

/// Provides the singleton [ScannerAnalyzer] for the scanner pipeline.
final scannerAnalyzerProvider = Provider<ScannerAnalyzer>((ref) {
  final analyzer = ScannerAnalyzer();
  ref.onDispose(analyzer.dispose);
  return analyzer;
});
