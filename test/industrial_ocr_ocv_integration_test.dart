import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/ocr/models/ocr_result.dart';
import 'package:exalted/features/ocr/services/desktop_ocr_engine.dart';
import 'package:exalted/features/ocv/models/ocv_evaluation_result.dart';
import 'package:exalted/features/ocv/models/ocv_rule.dart';
import 'package:exalted/features/ocv/services/ocv_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedClock = DateTime(2026, 11, 2, 12, 0);
  final ocvEngine = OcvEngine(clock: () => fixedClock);

  group('Industrial OCR/OCV Integration & Verification Pipeline', () {
    test('End-to-End: Raw TSV extraction -> OcrResult -> OCV Rule Evaluation PASS', () {
      // Simulate real industrial TSV output from Tesseract 5.3
      const industrialTsv = '''
level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
1\t1\t0\t0\t0\t0\t0\t0\t1200\t800\t-1\t
2\t1\t1\t0\t0\t0\t50\t100\t800\t200\t-1\t
3\t1\t1\t1\t0\t0\t50\t100\t800\t200\t-1\t
4\t1\t1\t1\t1\t0\t50\t100\t600\t50\t-1\t
5\t1\t1\t1\t1\t1\t50\t100\t150\t50\t96.2\tLOT-2026-X
4\t1\t1\t1\t2\t0\t50\t180\t600\t50\t-1\t
5\t1\t1\t1\t2\t1\t50\t180\t200\t50\t94.8\tEXP:2028-12-31
''';

      final blocks = DesktopOcrEngine.parseTesseractTsv(industrialTsv);
      expect(blocks.length, 1);
      final ocrResult = OcrResult(
        success: true,
        fullText: blocks.map((b) => b.text).join('\n'),
        blocks: blocks,
        engine: 'Tesseract OCR 5.3',
      );

      expect(ocrResult.fullText, contains('LOT-2026-X'));
      expect(ocrResult.fullText, contains('EXP:2028-12-31'));

      // 1. Validate LOT rule
      const lotRule = OcvRule(
        id: 'r_lot',
        name: 'Lot Rule',
        type: OcvRuleType.lotCode,
        pattern: r'LOT-[0-9]{4}-[A-Z]',
        minConfidence: 70.0,
      );

      final lotEval = ocvEngine.evaluate(ocrResult.fullText, lotRule, confidence: ocrResult.confidence);
      expect(lotEval.status, equals(OcvStatus.pass));
      expect(lotEval.isPass, isTrue);

      // 2. Validate EXP rule (future date -> pass)
      const expRule = OcvRule(
        id: 'r_exp',
        name: 'Expiry Rule',
        type: OcvRuleType.expiryDate,
        pattern: r'(\d{4}-\d{2}-\d{2})',
        minConfidence: 70.0,
      );

      final expEval = ocvEngine.evaluate(ocrResult.fullText, expRule, confidence: ocrResult.confidence);
      expect(expEval.status, equals(OcvStatus.pass));
      expect(expEval.isPass, isTrue);
    });

    test('End-to-End: Expired date marking triggers OCV FAIL verdict', () {
      const expiredTsv = '''
level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
1\t1\t0\t0\t0\t0\t0\t0\t600\t200\t-1\t
2\t1\t1\t0\t0\t0\t10\t10\t400\t60\t-1\t
3\t1\t1\t1\t0\t0\t10\t10\t400\t60\t-1\t
4\t1\t1\t1\t1\t0\t10\t10\t400\t60\t-1\t
5\t1\t1\t1\t1\t1\t10\t10\t200\t60\t92.0\tEXP:2024-05-01
''';

      final blocks = DesktopOcrEngine.parseTesseractTsv(expiredTsv);
      final ocrResult = OcrResult(
        success: true,
        fullText: blocks.map((b) => b.text).join('\n'),
        blocks: blocks,
        engine: 'Tesseract OCR 5.3',
      );

      const expRule = OcvRule(
        id: 'r_exp',
        name: 'Expiry Rule',
        type: OcvRuleType.expiryDate,
        pattern: r'(\d{4}-\d{2}-\d{2})',
      );

      final expEval = ocvEngine.evaluate(ocrResult.fullText, expRule, confidence: ocrResult.confidence);
      expect(expEval.status, equals(OcvStatus.fail));
      expect(expEval.isFail, isTrue);
      expect(expEval.explanation, contains('Expired'));
    });

    test('End-to-End: Damaged or low-contrast characters produce INCONCLUSIVE when below threshold', () {
      const noisyTsv = '''
level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
1\t1\t0\t0\t0\t0\t0\t0\t600\t200\t-1\t
2\t1\t1\t0\t0\t0\t10\t10\t400\t60\t-1\t
3\t1\t1\t1\t0\t0\t10\t10\t400\t60\t-1\t
4\t1\t1\t1\t1\t0\t10\t10\t400\t60\t-1\t
5\t1\t1\t1\t1\t1\t10\t10\t200\t60\t42.5\tLOT-2026-X
''';

      final blocks = DesktopOcrEngine.parseTesseractTsv(noisyTsv);
      final ocrResult = OcrResult(
        success: true,
        fullText: blocks.map((b) => b.text).join('\n'),
        blocks: blocks,
        engine: 'Tesseract OCR 5.3',
      );

      const strictRule = OcvRule(
        id: 'r_strict',
        name: 'High Confidence Required',
        type: OcvRuleType.exactMatch,
        pattern: 'LOT-2026-X',
        minConfidence: 75.0, // Image was 42.5%
      );

      final result = ocvEngine.evaluate(ocrResult.fullText, strictRule, confidence: ocrResult.confidence);
      expect(result.status, equals(OcvStatus.inconclusive));
      expect(result.isInconclusive, isTrue);
      expect(result.explanation, contains('below required threshold'));
    });

    test('End-to-End: Character-level diff isolates mismatched characters with position', () {
      const rule = OcvRule(
        id: 'r_exact',
        name: 'Serial Number',
        type: OcvRuleType.exactMatch,
        pattern: 'SN-9048-A',
      );

      // Actual scanned text has 'B' instead of 'A'
      final result = ocvEngine.evaluate('SN-9048-B', rule, confidence: 95.0);
      expect(result.status, equals(OcvStatus.fail));
      expect(result.diffs.length, 1);
      final diff = result.diffs.first;
      expect(diff.position, equals(8));
      expect(diff.expectedChar, equals('A'));
      expect(diff.actualChar, equals('B'));
    });
  });
}
