import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scanner_analyzer.dart';

/// One camera frame as seen by analyzers (luminance plane only).
///
/// [yPlane] is shared with the camera plugin: do not modify it. Copy it if
/// you need to keep it after [FrameAnalyzer.analyze] completes.
class AnalysisFrame {
  const AnalysisFrame({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.yPlane,
    required this.yRowStride,
  });

  final int width;
  final int height;

  /// Clockwise rotation needed to make the image upright.
  final int rotationDegrees;

  /// Grayscale (Y) plane. Barcode decoding only needs this plane.
  final Uint8List yPlane;

  final int yRowStride;
}

/// Anything that consumes camera frames.
abstract class FrameAnalyzer {
  String get name;

  Future<void> analyze(AnalysisFrame frame);

  void dispose() {}
}

/// Per-second numbers for the debug overlay.
@immutable
class PipelineStats {
  const PipelineStats({
    this.receivedFps = 0,
    this.analyzedFps = 0,
    this.skippedFps = 0,
    this.busySkippedFps = 0,
    this.throttleSkippedFps = 0,
    this.acceptedFps = 0,
    this.lastAnalyzeMs = 0,
    this.averageAnalyzeMs = 0,
    this.maxAnalyzeMs = 0,
    this.frameSize = '',
    this.busy = false,
  });

  final int receivedFps;
  final int analyzedFps;
  final int skippedFps;

  /// Frames rejected because an analyzer was already processing a frame.
  final int busySkippedFps;

  /// Frames rejected because the target analysis interval had not elapsed.
  final int throttleSkippedFps;

  /// Frames accepted for analyzer processing.
  final int acceptedFps;

  final int lastAnalyzeMs;
  final int averageAnalyzeMs;
  final int maxAnalyzeMs;
  final String frameSize;
  final bool busy;

  static const PipelineStats zero = PipelineStats();
}

/// Sits between the camera stream and the analyzers.
///
/// The preview is rendered by the camera plugin and never waits for this.
/// Frames are dropped when analysis is slower than the target rate, so a slow
/// decoder can never slow the preview down.
class FramePipeline {
  FramePipeline({
    this.targetFps = 30,
    int Function()? clockMs,
    List<FrameAnalyzer>? analyzers,
  }) : _clockMs = clockMs ?? _stopwatchClock() {
    if (targetFps <= 0) {
      throw ArgumentError.value(
        targetFps,
        'targetFps',
        'Target FPS must be greater than zero.',
      );
    }

    if (analyzers != null) {
      for (final analyzer in analyzers) {
        addAnalyzer(analyzer);
      }
    }
  }

  /// Maximum number of frames per second handed to analyzers.
  final int targetFps;

  final int Function() _clockMs;
  final List<FrameAnalyzer> _analyzers = [];

  final ValueNotifier<PipelineStats> stats = ValueNotifier<PipelineStats>(
    PipelineStats.zero,
  );

  Timer? _statsTimer;

  bool _active = true;
  bool _disposed = false;
  bool _busy = false;

  int _lastAcceptedMs = -1000000;
  int _lastAnalyzeMs = 0;

  int _frameW = 0;
  int _frameH = 0;

  int _received = 0;
  int _analyzed = 0;
  int _skipped = 0;
  int _busySkipped = 0;
  int _throttleSkipped = 0;
  int _accepted = 0;

  int _totalAnalyzeMs = 0;
  int _maxAnalyzeMs = 0;

  int _lastReceived = 0;
  int _lastAnalyzed = 0;
  int _lastSkipped = 0;
  int _lastBusySkipped = 0;
  int _lastThrottleSkipped = 0;
  int _lastAccepted = 0;
  int _lastAnalyzeTotalMs = 0;

  int get receivedTotal => _received;
  int get analyzedTotal => _analyzed;
  int get skippedTotal => _skipped;
  int get busySkippedTotal => _busySkipped;
  int get throttleSkippedTotal => _throttleSkipped;
  int get acceptedTotal => _accepted;

  bool get hasAnalyzers => _analyzers.isNotEmpty;

  int _dbgRecv = 0;
  int _dbgLogMs = 0;

  bool get isActive => _active && !_disposed;

  bool get isDisposed => _disposed;

  bool get isBusy => _busy;

  List<FrameAnalyzer> get analyzers =>
      List<FrameAnalyzer>.unmodifiable(_analyzers);

  static int Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMilliseconds;
  }

  int get _minIntervalMs => (1000 / targetFps).round();

  /// Registers an analyzer.
  ///
  /// Duplicate registrations of the same instance or an analyzer with an
  /// identical [name] are ignored.
  bool addAnalyzer(FrameAnalyzer analyzer) {
    if (_disposed) return false;

    if (_analyzers.any(
      (a) => identical(a, analyzer) || a.name == analyzer.name,
    )) {
      return false;
    }

    _analyzers.add(analyzer);
    return true;
  }

  bool removeAnalyzer(FrameAnalyzer analyzer) {
    return _analyzers.remove(analyzer);
  }

  void clearAnalyzers() {
    _analyzers.clear();
  }

  /// Starts the once-per-second stats timer.
  ///
  /// The timer is disabled in release builds so production scanning does not
  /// pay for debug statistics publication.
  void start() {
    if (_disposed) return;

    _active = true;

    _statsTimer?.cancel();
    _statsTimer = null;

    if (kReleaseMode) return;

    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _publish());
  }

  void stop() {
    _active = false;

    _statsTimer?.cancel();
    _statsTimer = null;

    _lastReceived = _received;
    _lastAnalyzed = _analyzed;
    _lastSkipped = _skipped;
    _lastBusySkipped = _busySkipped;
    _lastThrottleSkipped = _throttleSkipped;
    _lastAccepted = _accepted;
    _lastAnalyzeTotalMs = _totalAnalyzeMs;

    _busy = false;

    stats.value = PipelineStats.zero;
  }

  /// Called for every camera frame.
  ///
  /// This method must stay extremely cheap because it runs directly from the
  /// camera image stream callback.
  void submit({
    required int width,
    required int height,
    required int rotationDegrees,
    required Uint8List yPlane,
    required int yRowStride,
  }) {
    if (!_active || _disposed) return;

    _received++;
    _dbgRecv++;
    final dbgNow = _clockMs();
    if (dbgNow - _dbgLogMs >= 1000) {
      _dbgLogMs = dbgNow;
      debugPrint(
        '[EXALTED][FRAME] total=$_dbgRecv ${width}x$height stride=$yRowStride '
        'rot=$rotationDegrees analyzers=${_analyzers.length} busy=$_busy acc=$_accepted busySkip=$_busySkipped thrSkip=$_throttleSkipped',
      );
    }

    _frameW = width;
    _frameH = height;

    if (_analyzers.isEmpty) return;

    final now = _clockMs();

    if (_busy) {
      _skipped++;
      _busySkipped++;
      return;
    }

    if (now - _lastAcceptedMs < _minIntervalMs) {
      _skipped++;
      _throttleSkipped++;
      return;
    }

    _busy = true;
    _lastAcceptedMs = now;
    _accepted++;

    unawaited(
      _run(
        AnalysisFrame(
          width: width,
          height: height,
          rotationDegrees: rotationDegrees,
          yPlane: yPlane,
          yRowStride: yRowStride,
        ),
      ),
    );
  }

  Future<void> _run(AnalysisFrame frame) async {
    final sw = Stopwatch()..start();

    try {
      for (final analyzer in List<FrameAnalyzer>.of(_analyzers)) {
        if (!_active || _disposed) break;

        await analyzer.analyze(frame);
      }
    } catch (e) {
      debugPrint('Frame analyzer failed: $e');
    } finally {
      final elapsedMs = sw.elapsedMilliseconds;

      _lastAnalyzeMs = elapsedMs;
      _totalAnalyzeMs += elapsedMs;

      if (elapsedMs > _maxAnalyzeMs) {
        _maxAnalyzeMs = elapsedMs;
      }

      _analyzed++;
      _busy = false;
    }
  }

  void _publish() {
    final receivedDelta = _received - _lastReceived;
    final analyzedDelta = _analyzed - _lastAnalyzed;
    final skippedDelta = _skipped - _lastSkipped;
    final busySkippedDelta = _busySkipped - _lastBusySkipped;
    final throttleSkippedDelta = _throttleSkipped - _lastThrottleSkipped;
    final acceptedDelta = _accepted - _lastAccepted;
    final analyzeTotalDelta = _totalAnalyzeMs - _lastAnalyzeTotalMs;

    final averageAnalyzeMs = analyzedDelta > 0
        ? (analyzeTotalDelta / analyzedDelta).round()
        : 0;

    stats.value = PipelineStats(
      receivedFps: receivedDelta,
      analyzedFps: analyzedDelta,
      skippedFps: skippedDelta,
      busySkippedFps: busySkippedDelta,
      throttleSkippedFps: throttleSkippedDelta,
      acceptedFps: acceptedDelta,
      lastAnalyzeMs: _lastAnalyzeMs,
      averageAnalyzeMs: averageAnalyzeMs,
      maxAnalyzeMs: _maxAnalyzeMs,
      frameSize: '${_frameW}x$_frameH',
      busy: _busy,
    );

    _lastReceived = _received;
    _lastAnalyzed = _analyzed;
    _lastSkipped = _skipped;
    _lastBusySkipped = _busySkipped;
    _lastThrottleSkipped = _throttleSkipped;
    _lastAccepted = _accepted;
    _lastAnalyzeTotalMs = _totalAnalyzeMs;
  }

  void dispose() {
    if (_disposed) return;

    _disposed = true;
    _active = false;

    _statsTimer?.cancel();
    _statsTimer = null;

    stats.dispose();

    for (final analyzer in _analyzers) {
      try {
        analyzer.dispose();
      } catch (e) {
        debugPrint('Analyzer disposal failed: $e');
      }
    }

    _analyzers.clear();
  }
}

final framePipelineProvider = Provider<FramePipeline>((ref) {
  final analyzer = ref.watch(scannerAnalyzerProvider);

  final pipeline = FramePipeline(targetFps: 60);

  pipeline.addAnalyzer(analyzer);

  ref.onDispose(pipeline.dispose);

  return pipeline;
});
