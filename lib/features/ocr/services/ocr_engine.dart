import '../models/ocr_result.dart';

/// Contract for an offline text-recognition engine.
///
/// Live camera OCR will add a `recognizeFrame(AnalysisFrame)` method here
/// later and run as a FrameAnalyzer on the scanner's frame pipeline.
abstract class OcrEngine {
  /// Human-readable engine name, shown in the analysis tab.
  String get name;

  /// Script this engine is configured for, for example "Latin".
  String get script;

  /// Reads text from an image file. Never throws: errors come back in
  /// [OcrResult.error].
  Future<OcrResult> recognizeFile(String imagePath);

  Future<void> dispose();
}
