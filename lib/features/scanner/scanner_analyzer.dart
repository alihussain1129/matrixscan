import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// through [onDecoded]. When it owns its decoder it runs two decoders in
/// parallel, so decoding keeps up with the camera.
class ScannerAnalyzer implements FrameAnalyzer {
  ScannerAnalyzer({DecoderService? decoder}) : _ownsDecoder = decoder == null {
    _slots.add(_Slot(decoder ?? DecoderService(), owned: decoder == null));
    if (_ownsDecoder) {
      // One decoder only: a second did not raise throughput on this phone.
    }
  }

  /// Time since the scanner was first opened (startup diagnostics).
  static final Stopwatch startup = Stopwatch()..start();

  static void startupLog(String what) {
    debugPrint('[EXALTED][START] +${startup.elapsedMilliseconds}ms $what');
  }

  final bool _ownsDecoder;
  final List<_Slot> _slots = [];

  void Function(DecodedBarcode barcode)? onDecoded;

  /// Scan window as fractions (0..1) of the upright preview image. Set by the
  /// scanner screen; null until the camera is showing.
  Rect? scanWindow;

  @override
  String get name => 'scanner';

  /// Loads the native library and starts the decode isolates ahead of the
  /// first camera frame.
  Future<void> prewarm() async {
    await Future.wait(_slots.map((s) => s.decoder.prewarm()));
  }

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
  int _lastHitMs = -1;
  final Map<int, int> _rcWindow = {};

  // Decode passes, one per analyzed frame. Native option flags: 2 = invert,
  // 4 = no rotate, 8 = no downscale, 16 = global histogram, 32 = harder (more
  // scan lines for 1D codes). Every pass reads every symbology.
  // crop = decode only a band around the on-screen scan window.
  static const double _bandMargin = 0.35;
  static const List<_Pass> _passCycle = [
    _Pass(8, true),
    _Pass(24, true),
    _Pass(56, true),
    _Pass(26, true),
    _Pass(24, false),
    _Pass(48, false),
  ];

  // Dot-peen fallback passes. Native flags: 8 = no downscale, 16 = global
  // histogram, bits 10-12 = dark-dot grow radius in px (1..7), 256 = grow
  // light dots instead (must be combined with 2 = invert). The radius has to
  // scale with the dot spacing, so the ladder covers several radii. Only used
  // after a run of misses, so normal scanning is barely affected.
  static const List<_Pass> _dotPasses = [
    _Pass(3096, true), // dark dots, global histogram, radius 3
    _Pass(4104, true), // dark, local binarizer, radius 4
    _Pass(4120, true), // dark, global, radius 4
    _Pass(5144, true), // dark, global, radius 5
    _Pass(2056, true), // dark, local, radius 2
    _Pass(1032, true), // dark, local, radius 1
    _Pass(3354, true), // light dots, global, radius 3
    _Pass(4362, true), // light, local, radius 4
    _Pass(4378, true), // light, global, radius 4
    _Pass(2314, true), // light, local, radius 2
  ];
  static const int _dotAfterMisses = 12;
  static const int _dotEvery = 3;
  int _dotCursor = 0;
  int _missStreak = 0;  int _lightCursor = 0;

  final Map<String, int> _passN = {};
  final Map<String, int> _passUs = {};
  final Map<String, int> _passHits = {};
  String _lastCropLog = '';

  // UI frame timing (temporary diagnostic), reset every second.
  bool _timingsHooked = false;
  int _uiFrames = 0;
  int _uiJank = 0;
  int _uiBuildMaxUs = 0;
  int _uiRasterMaxUs = 0;

  void _hookTimings() {
    if (_timingsHooked) return;
    _timingsHooked = true;
    try {
      SchedulerBinding.instance.addTimingsCallback((timings) {
        if (_disposed) return;
        for (final t in timings) {
          _uiFrames++;
          final build = t.buildDuration.inMicroseconds;
          final raster = t.rasterDuration.inMicroseconds;
          if (build > _uiBuildMaxUs) _uiBuildMaxUs = build;
          if (raster > _uiRasterMaxUs) _uiRasterMaxUs = raster;
          if (t.totalSpan.inMicroseconds > 16667) _uiJank++;
        }
      });
    } catch (_) {}
  }

  final Stopwatch _clock = Stopwatch()..start();

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

  /// Region of [frame], in buffer pixels: the full width of the upright image
  /// and a band of it around the on-screen scan window, so wide 1D codes are
  /// never cut sideways. Null when the window is unknown.
  _Crop? _cropFor(AnalysisFrame frame) {
    final win = scanWindow;
    if (win == null) return null;

    final margin = win.height * _bandMargin;
    final t = (win.top - margin).clamp(0.0, 1.0).toDouble();
    final b = (win.bottom + margin).clamp(0.0, 1.0).toDouble();

    var left = 0;
    var right = frame.width;
    var top = 0;
    var bottom = frame.height;
    final rot = frame.rotationDegrees % 360;
    if (rot == 90) {
      left = (t * frame.width).floor();
      right = (b * frame.width).ceil();
    } else if (rot == 270) {
      left = ((1 - b) * frame.width).floor();
      right = ((1 - t) * frame.width).ceil();
    } else if (rot == 0) {
      top = (t * frame.height).floor();
      bottom = (b * frame.height).ceil();
    } else if (rot == 180) {
      top = ((1 - b) * frame.height).floor();
      bottom = ((1 - t) * frame.height).ceil();
    } else {
      return null;
    }

    left = left.clamp(0, frame.width - 1).toInt();
    top = top.clamp(0, frame.height - 1).toInt();
    right = right.clamp(left + 1, frame.width).toInt();
    bottom = bottom.clamp(top + 1, frame.height).toInt();
    final w = right - left;
    final h = bottom - top;
    if (w < 64 || h < 64) return null;
    return _Crop(left, top, w, h);
  }

  _Slot? _freeSlot() {
    for (final s in _slots) {
      if (!s.busy) return s;
    }
    return null;
  }

  @override
  Future<void> analyze(AnalysisFrame frame) async {
    if (_disposed) return;
    _hookTimings();

    final slot = _freeSlot();
    if (slot == null) return; // every decoder is busy: skip this frame

    _analyzedFrames++;
    _lastWidth = frame.width;
    _lastHeight = frame.height;
    _lastRotation = frame.rotationDegrees;

    if (_analyzedFrames == 1) {
      startupLog('first camera frame reached the analyzer');
    }

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

    final watch = Stopwatch()..start();
    _attempts++;
    final useDot = _missStreak >= _dotAfterMisses && _attempts % _dotEvery == 0;
    final pass = useDot
        ? _dotPasses[_dotCursor++ % _dotPasses.length]
        : _passCycle[_lightCursor++ % _passCycle.length];
    _missStreak++;
    final crop = pass.crop ? _cropFor(frame) : null;
    if (pass.crop) {
      final cropLog = crop == null
          ? 'none (scan window unknown)'
          : '${crop.left},${crop.top} ${crop.width}x${crop.height} '
                'of ${frame.width}x${frame.height} rot=${frame.rotationDegrees}';
      if (cropLog != _lastCropLog) {
        _lastCropLog = cropLog;
        debugPrint('[EXALTED][CROP] $cropLog');
      }
    }

    slot.busy = true;
    final startMs = _clock.elapsedMilliseconds;
    // decodeAsync copies the luminance plane into native memory before its
    // first await, so the camera buffer is free once this call returns.
    final call = slot.decoder.decodeAsync(
      luma: frame.yPlane,
      width: frame.width,
      height: frame.height,
      rowStride: frame.yRowStride,
      flags: pass.flags,
      cropLeft: crop?.left ?? 0,
      cropTop: crop?.top ?? 0,
      cropWidth: crop?.width ?? 0,
      cropHeight: crop?.height ?? 0,
    );
    final done = _finish(slot, call, pass, startMs, watch);
    if (_ownsDecoder) {
      unawaited(done);
    } else {
      await done;
    }
  }

  Future<void> _finish(
    _Slot slot,
    Future<DecodedBarcode?> call,
    _Pass pass,
    int startMs,
    Stopwatch watch,
  ) async {
    DecodedBarcode? barcode;
    try {
      barcode = await call;
    } catch (e) {
      debugPrint('[EXALTED][ANALYZER] decode failed: $e');
    } finally {
      slot.busy = false;
    }
    if (_disposed) return;

    if (_analyzedFrames <= 2) {
      startupLog('first decode finished (decoder ready)');
    }
    final label = pass.label;
    _passN[label] = (_passN[label] ?? 0) + 1;
    _passUs[label] = (_passUs[label] ?? 0) + watch.elapsedMicroseconds;
    _windowFrames++;
    _windowMicros += watch.elapsedMicroseconds;
    final rc = slot.decoder.isAvailable ? slot.decoder.lastDecodeStatus : -99;
    _rcWindow[rc] = (_rcWindow[rc] ?? 0) + 1;

    // Ignore a result from a frame captured before the last accepted hit.
    if (barcode != null && startMs >= _lastHitMs) {
      _lastHitMs = _clock.elapsedMilliseconds;
      _passHits[label] = (_passHits[label] ?? 0) + 1;
      _decodedFrames++;
      _missStreak = 0;
      debugPrint('[EXALTED][RESULT] $barcode');
      debugPrint('[EXALTED][PASS] hit flags=${pass.flags} pass=$label');
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
      if (!slot.decoder.isAvailable) {
        debugPrint('[EXALTED][NATIVE] unavailable: ${slot.decoder.loadError}');
      }
      _windowFrames = 0;
      _windowMicros = 0;
      debugPrint(
        '[EXALTED][UI] frames=$_uiFrames jank=$_uiJank '
        'buildMax=${(_uiBuildMaxUs / 1000).toStringAsFixed(1)}ms '
        'rasterMax=${(_uiRasterMaxUs / 1000).toStringAsFixed(1)}ms',
      );
      _uiFrames = 0;
      _uiJank = 0;
      _uiBuildMaxUs = 0;
      _uiRasterMaxUs = 0;
      final passLog = StringBuffer();
      for (final f in _passN.keys) {
        final n = _passN[f]!;
        final avg = (_passUs[f]! / n / 1000).toStringAsFixed(1);
        passLog.write(' $f:n=$n avg=${avg}ms hit=${_passHits[f] ?? 0}');
      }
      debugPrint('[EXALTED][PASS]$passLog');
      _rcWindow.clear();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    onDecoded = null;
    for (final s in _slots) {
      if (s.owned) s.decoder.dispose();
    }
  }
}

/// One decoder and whether it is currently decoding a frame.
class _Slot {
  _Slot(this.decoder, {required this.owned});

  final DecoderService decoder;
  final bool owned;
  bool busy = false;
}

/// One decode pass: native option flags and whether to decode only the band
/// around the scan window.
class _Pass {
  const _Pass(this.flags, this.crop);

  final int flags;
  final bool crop;

  String get label => 'f${flags}_${crop ? 'c' : 'F'}';
}

class _Crop {
  const _Crop(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;
}

/// Provides the singleton [ScannerAnalyzer] for the scanner pipeline.
final scannerAnalyzerProvider = Provider<ScannerAnalyzer>((ref) {
  final analyzer = ScannerAnalyzer();
  ref.onDispose(analyzer.dispose);
  return analyzer;
});
