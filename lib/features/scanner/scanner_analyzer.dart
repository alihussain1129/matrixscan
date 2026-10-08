import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Production pipeline analyzer for scanner camera frames.
///
/// In Phase 2, this establishes the analyzer architecture: it receives
/// [AnalysisFrame] instances from [FramePipeline], tracks diagnostics,
/// and ensures safe lifecycle handling without executing decoding algorithms.
/// Real barcode/Data Matrix decoding will integrate here in future phases.
class ScannerAnalyzer implements FrameAnalyzer {
  ScannerAnalyzer();

  @override
  String get name => 'scanner';

  int _analyzedFrames = 0;
  int _lastWidth = 0;
  int _lastHeight = 0;
  int _lastRotation = 0;
  bool _disposed = false;

  int get analyzedFrames => _analyzedFrames;
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
  }

  @override
  void dispose() {
    _disposed = true;
  }
}

/// Provides the singleton [ScannerAnalyzer] for the scanner pipeline.
final scannerAnalyzerProvider = Provider<ScannerAnalyzer>((ref) {
  final analyzer = ScannerAnalyzer();
  ref.onDispose(analyzer.dispose);
  return analyzer;
});
