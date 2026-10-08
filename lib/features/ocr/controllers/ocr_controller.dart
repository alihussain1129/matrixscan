import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ocr_result.dart';
import '../services/mlkit_ocr_engine.dart';
import '../services/ocr_engine.dart';

enum OcrStatus { idle, running, done, failed }

class OcrState {
  const OcrState({this.status = OcrStatus.idle, this.imagePath, this.result});

  final OcrStatus status;
  final String? imagePath;
  final OcrResult? result;
}

/// The engine in use. Override this in tests, or swap the engine here later.
final ocrEngineProvider = Provider<OcrEngine>((ref) {
  final engine = MlKitOcrEngine();
  ref.onDispose(() {
    engine.dispose();
  });
  return engine;
});

class OcrController extends Notifier<OcrState> {
  int _runId = 0;

  @override
  OcrState build() => const OcrState();

  /// Runs OCR on [imagePath]. A newer call replaces an older one.
  Future<void> run(String imagePath) async {
    final id = ++_runId;
    state = OcrState(status: OcrStatus.running, imagePath: imagePath);
    final result = await ref.read(ocrEngineProvider).recognizeFile(imagePath);
    if (id != _runId) return;
    state = OcrState(
      status: result.success ? OcrStatus.done : OcrStatus.failed,
      imagePath: imagePath,
      result: result,
    );
  }

  /// Forgets the last result (and its text) once the screen is closed.
  void reset() {
    _runId++;
    state = const OcrState();
  }
}

final ocrControllerProvider = NotifierProvider<OcrController, OcrState>(
  OcrController.new,
);
