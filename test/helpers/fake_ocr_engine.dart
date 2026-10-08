import 'package:exalted/features/ocr/models/ocr_result.dart';
import 'package:exalted/features/ocr/services/ocr_engine.dart';

/// Test double: returns a fixed result instantly.
class FakeOcrEngine implements OcrEngine {
  FakeOcrEngine(this.result);

  final OcrResult result;

  @override
  String get name => 'fake';

  @override
  String get script => 'Latin';

  @override
  Future<OcrResult> recognizeFile(String imagePath) async => result;

  @override
  Future<void> dispose() async {}
}
