import 'dart:async';
import 'dart:typed_data';

import 'package:exalted/features/scanner/frame_pipeline.dart';
import 'package:exalted/features/scanner/scanner_analyzer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAnalyzer implements FrameAnalyzer {
  _FakeAnalyzer([this._name = 'fake']);

  final String _name;
  int calls = 0;
  bool disposed = false;
  Completer<void>? gate;
  AnalysisFrame? lastFrame;

  @override
  String get name => _name;

  @override
  Future<void> analyze(AnalysisFrame frame) async {
    calls++;
    lastFrame = frame;
    final g = gate;
    if (g != null) await g.future;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void _submit(
  FramePipeline p, {
  int width = 640,
  int height = 480,
  int rotationDegrees = 90,
}) => p.submit(
  width: width,
  height: height,
  rotationDegrees: rotationDegrees,
  yPlane: Uint8List(4),
  yRowStride: width,
);

void main() {
  test('without analyzers frames are counted but never analyzed', () {
    final p = FramePipeline();
    _submit(p);
    _submit(p);
    expect(p.receivedTotal, 2);
    expect(p.analyzedTotal, 0);
    expect(p.skippedTotal, 0);
  });

  test('frames faster than the target rate are skipped', () async {
    var now = 0;
    final a = _FakeAnalyzer();
    final p = FramePipeline(targetFps: 10, clockMs: () => now)..addAnalyzer(a);

    _submit(p); // t=0: accepted
    await pumpEventQueue();
    now = 40;
    _submit(p); // 40 ms later: too soon for 10 fps
    await pumpEventQueue();
    now = 150;
    _submit(p); // accepted
    await pumpEventQueue();

    expect(a.calls, 2);
    expect(p.analyzedTotal, 2);
    expect(p.skippedTotal, 1);
  });

  test('frames arriving while the analyzer is busy are skipped', () async {
    var now = 0;
    final a = _FakeAnalyzer()..gate = Completer<void>();
    final p = FramePipeline(targetFps: 10, clockMs: () => now)..addAnalyzer(a);

    _submit(p); // starts and blocks inside the analyzer
    await pumpEventQueue();
    now = 5000;
    _submit(p); // analyzer still busy: skipped
    expect(p.skippedTotal, 1);

    a.gate!.complete();
    await pumpEventQueue();
    a.gate = null;
    now = 10000;
    _submit(p); // accepted again
    await pumpEventQueue();

    expect(a.calls, 2);
    expect(p.analyzedTotal, 2);
  });

  // Phase 2: Architecture verification tests

  test('an analyzer can be registered and receives submitted frames', () async {
    final a = _FakeAnalyzer();
    final p = FramePipeline();
    expect(p.addAnalyzer(a), isTrue);
    expect(p.hasAnalyzers, isTrue);
    expect(p.analyzers, contains(a));

    _submit(p, width: 1280, height: 720, rotationDegrees: 90);
    await pumpEventQueue();

    expect(a.calls, 1);
    expect(a.lastFrame?.width, 1280);
    expect(a.lastFrame?.height, 720);
    expect(a.lastFrame?.rotationDegrees, 90);
    expect(p.analyzedTotal, 1);
  });

  test('duplicate analyzer registration is prevented', () {
    final p = FramePipeline();
    final a1 = _FakeAnalyzer('unique_a');
    final a2 = _FakeAnalyzer('unique_a'); // same name
    final a3 = _FakeAnalyzer('unique_b'); // different name

    expect(p.addAnalyzer(a1), isTrue);
    expect(p.addAnalyzer(a1), isFalse); // duplicate instance rejected
    expect(p.addAnalyzer(a2), isFalse); // duplicate name rejected
    expect(p.addAnalyzer(a3), isTrue); // unique analyzer accepted

    expect(p.analyzers.length, 2);
    expect(p.removeAnalyzer(a1), isTrue);
    expect(p.analyzers.length, 1);
  });

  test('stopped pipeline does not pass frames to analyzers and resumes when started', () async {
    final a = _FakeAnalyzer();
    final p = FramePipeline()..addAnalyzer(a);

    p.stop();
    expect(p.isActive, isFalse);
    _submit(p);
    await pumpEventQueue();
    expect(a.calls, 0);

    p.start();
    expect(p.isActive, isTrue);
    _submit(p);
    await pumpEventQueue();
    expect(a.calls, 1);
  });

  test(
    'disposed pipeline stops accepting frames and disposes its analyzers',
    () async {
      final a = _FakeAnalyzer();
      final p = FramePipeline()..addAnalyzer(a);

      expect(a.disposed, isFalse);
      p.dispose();
      expect(p.isDisposed, isTrue);
      expect(a.disposed, isTrue);

      // Frame submission after dispose is rejected
      _submit(p);
      await pumpEventQueue();
      expect(a.calls, 0);

      // Adding analyzer after dispose is rejected
      expect(p.addAnalyzer(_FakeAnalyzer('late')), isFalse);
    },
  );

  test(
    'ScannerAnalyzer records frame metrics safely without decoding',
    () async {
      final analyzer = ScannerAnalyzer();
      expect(analyzer.name, 'scanner');
      expect(analyzer.analyzedFrames, 0);
      expect(analyzer.isDisposed, isFalse);

      await analyzer.analyze(
        AnalysisFrame(
          width: 1920,
          height: 1080,
          rotationDegrees: 90,
          yPlane: Uint8List(4),
          yRowStride: 1920,
        ),
      );

      expect(analyzer.analyzedFrames, 1);
      expect(analyzer.lastFrameWidth, 1920);
      expect(analyzer.lastFrameHeight, 1080);
      expect(analyzer.lastRotationDegrees, 90);
      expect(analyzer.stats.analyzedFrames, 1);
      expect(analyzer.stats.lastFrameWidth, 1920);

      analyzer.dispose();
      expect(analyzer.isDisposed, isTrue);

      // After disposal, further calls are ignored
      await analyzer.analyze(
        AnalysisFrame(
          width: 640,
          height: 480,
          rotationDegrees: 0,
          yPlane: Uint8List(4),
          yRowStride: 640,
        ),
      );
      expect(analyzer.analyzedFrames, 1);
    },
  );

  test('Riverpod framePipelineProvider provides singleton pipeline with ScannerAnalyzer', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final pipeline = container.read(framePipelineProvider);
    expect(pipeline.hasAnalyzers, isTrue);
    expect(pipeline.analyzers.length, 1);
    expect(pipeline.analyzers.first, isA<ScannerAnalyzer>());

    // Repeated reads return the identical pipeline without re-registering
    final pipeline2 = container.read(framePipelineProvider);
    expect(identical(pipeline, pipeline2), isTrue);
    expect(pipeline2.analyzers.length, 1);

    final analyzer = container.read(scannerAnalyzerProvider);
    expect(identical(pipeline.analyzers.first, analyzer), isTrue);
  });
}
