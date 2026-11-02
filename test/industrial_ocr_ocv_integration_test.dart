import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/ocr/models/ocr_result.dart';
import 'package:exalted/features/ocr/services/desktop_ocr_engine.dart';
import 'package:exalted/features/ocv/models/ocv_evaluation_result.dart';
import 'package:exalted/features/ocv/models/ocv_rule.dart';
import 'package:exalted/features/ocv/services/ocv_engine.dart';

// Confidence scale in this app is 0..1 everywhere (OcrResult, OcvRule, OcvEngine).

const _tsvHeader =
    'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext';
const _pageRow = '1\t1\t0\t0\t0\t0\t0\t0\t1200\t800\t-1\t';

String _wordRow({
  required int block,
  int par = 1,
  required int line,
  required double conf,
  required String text,
  int left = 50,
  int top = 100,
}) =>
    ['5', '1', '$block', '$par', '$line', '1', '$left', '$top', '150', '50', '$conf', text]
        .join('\t');

String _tsv(List<String> rows) => [_tsvHeader, ...rows].join('\n');

OcrResult _ocrFromTsv(String tsv) {
  final blocks = DesktopOcrEngine.parseTesseractTsv(tsv);
  return OcrResult(
    success: true,
    fullText: blocks.map((b) => b.text).join('\n'),
    blocks: blocks,
    engine: 'Tesseract OCR 5.3',
  );
}

double _confidenceOf(OcrResult r) {
  final c = r.confidence;
  expect(c, isNotNull, reason: 'Tesseract TSV with conf values must give a confidence');
  return c!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedClock = DateTime(2026, 11, 2, 12, 0);
  final ocvEngine = OcvEngine(clock: () => fixedClock);

  group('Industrial OCR/OCV Integration & Verification Pipeline', () {
    test('End-to-End: Raw TSV extraction -> OcrResult -> OCV Rule Evaluation PASS', () {
      final ocrResult = _ocrFromTsv(_tsv([
        _pageRow,
        _wordRow(block: 1, line: 1, conf: 96.2, text: 'LOT-2026-X'),
        _wordRow(block: 1, line: 2, conf: 94.8, text: 'EXP:2028-12-31', top: 180),
      ]));

      expect(ocrResult.blocks.length, 1);
      expect(ocrResult.lines.length, 2);
      expect(ocrResult.fullText, contains('LOT-2026-X'));
      expect(ocrResult.fullText, contains('EXP:2028-12-31'));

      final conf = _confidenceOf(ocrResult);
      expect(conf, closeTo(0.955, 1e-9)); // average of 0.962 and 0.948

      const lotRule = OcvRule(
        id: 'r_lot',
        name: 'Lot Rule',
        type: OcvRuleType.lotCode,
        pattern: r'LOT-[0-9]{4}-[A-Z]',
        minConfidence: 0.70,
      );
      final lotEval = ocvEngine.evaluate(ocrResult.fullText, lotRule, confidence: conf);
      expect(lotEval.status, equals(OcvStatus.pass));
      expect(lotEval.isPass, isTrue);

      // Note: the expiry evaluator uses its own date regex; rule.pattern is not used for it.
      const expRule = OcvRule(
        id: 'r_exp',
        name: 'Expiry Rule',
        type: OcvRuleType.expiryDate,
        pattern: r'(\d{4}-\d{2}-\d{2})',
        minConfidence: 0.70,
      );
      final expEval = ocvEngine.evaluate(ocrResult.fullText, expRule, confidence: conf);
      expect(expEval.status, equals(OcvStatus.pass));
      expect(expEval.isPass, isTrue);
    });

    test('End-to-End: Expired date marking triggers OCV FAIL verdict', () {
      final ocrResult = _ocrFromTsv(_tsv([
        _pageRow,
        _wordRow(block: 1, line: 1, conf: 92.0, text: 'EXP:2024-05-01', left: 10, top: 10),
      ]));

      const expRule = OcvRule(
        id: 'r_exp',
        name: 'Expiry Rule',
        type: OcvRuleType.expiryDate,
        pattern: r'(\d{4}-\d{2}-\d{2})',
      );

      final expEval = ocvEngine.evaluate(
        ocrResult.fullText,
        expRule,
        confidence: _confidenceOf(ocrResult),
      );
      expect(expEval.status, equals(OcvStatus.fail));
      expect(expEval.isFail, isTrue);
      expect(expEval.explanation, contains('Expired'));
    });

    test('End-to-End: Damaged or low-contrast characters produce INCONCLUSIVE when below threshold', () {
      final ocrResult = _ocrFromTsv(_tsv([
        _pageRow,
        _wordRow(block: 1, line: 1, conf: 42.5, text: 'LOT-2026-X', left: 10, top: 10),
      ]));
      final conf = _confidenceOf(ocrResult);
      expect(conf, closeTo(0.425, 1e-9));

      const strictRule = OcvRule(
        id: 'r_strict',
        name: 'High Confidence Required',
        type: OcvRuleType.exactMatch,
        pattern: 'LOT-2026-X',
        minConfidence: 0.75, // image was 42.5%
      );

      final result = ocvEngine.evaluate(ocrResult.fullText, strictRule, confidence: conf);
      expect(result.status, equals(OcvStatus.inconclusive));
      expect(result.isInconclusive, isTrue);
      expect(result.explanation, contains('below the required industrial threshold'));
      expect(result.explanation, contains('42.5%'));
      expect(result.explanation, contains('75.0%'));
    });

    test('End-to-End: Character-level diff isolates mismatched characters with position', () {
      const rule = OcvRule(
        id: 'r_exact',
        name: 'Serial Number',
        type: OcvRuleType.exactMatch,
        pattern: 'SN-9048-A',
      );

      // Actual scanned text has 'B' instead of 'A'
      final result = ocvEngine.evaluate('SN-9048-B', rule, confidence: 0.95);
      expect(result.status, equals(OcvStatus.fail));
      expect(result.diffs.length, 1);
      final diff = result.diffs.first;
      expect(diff.position, equals(8));
      expect(diff.expectedChar, equals('A'));
      expect(diff.actualChar, equals('B'));
    });

    test('Pattern mismatch on a clean read produces FAIL (not INCONCLUSIVE)', () {
      final ocrResult = _ocrFromTsv(_tsv([
        _pageRow,
        _wordRow(block: 1, line: 1, conf: 95.0, text: 'LOT-ABCD-X'),
      ]));

      const lotRule = OcvRule(
        id: 'r_lot',
        name: 'Lot Rule',
        type: OcvRuleType.lotCode,
        pattern: r'LOT-[0-9]{4}-[A-Z]',
      );

      final result = ocvEngine.evaluate(
        ocrResult.fullText,
        lotRule,
        confidence: _confidenceOf(ocrResult),
      );
      expect(result.status, equals(OcvStatus.fail));
      expect(result.explanation, contains('does not match pattern'));
    });

    test('Empty and whitespace-only text produce noText verdict', () {
      const rule = OcvRule(
        id: 'r_any',
        name: 'Any',
        type: OcvRuleType.regex,
        pattern: r'.+',
      );

      final empty = ocvEngine.evaluate('', rule, confidence: 0.9);
      expect(empty.status, equals(OcvStatus.noText));
      expect(empty.isPass, isFalse);

      final spaces = ocvEngine.evaluate('   \n\t ', rule, confidence: 0.9);
      expect(spaces.status, equals(OcvStatus.noText));
      expect(spaces.explanation, contains('No text'));
    });

    test('Invalid rule regex produces FAIL with explanation instead of throwing', () {
      const badRule = OcvRule(
        id: 'r_bad',
        name: 'Bad Regex',
        type: OcvRuleType.regex,
        pattern: r'[unclosed',
      );

      final result = ocvEngine.evaluate('ANYTHING', badRule, confidence: 0.9);
      expect(result.status, equals(OcvStatus.fail));
      expect(result.explanation, contains('Invalid rule regex'));
    });

    test('Malformed or empty Tesseract TSV never crashes and gives no blocks', () {
      expect(DesktopOcrEngine.parseTesseractTsv(''), isEmpty);
      expect(DesktopOcrEngine.parseTesseractTsv(_tsvHeader), isEmpty);
      expect(DesktopOcrEngine.parseTesseractTsv('$_tsvHeader\n'), isEmpty);
      // Row with only 11 columns is skipped.
      expect(
        DesktopOcrEngine.parseTesseractTsv(
          _tsv(['5\t1\t1\t1\t1\t1\t0\t0\t10\t10\t90']),
        ),
        isEmpty,
      );
      // Windows-style CRLF line endings still parse.
      final crlf = _tsv([
        _pageRow,
        _wordRow(block: 1, line: 1, conf: 90.0, text: 'HELLO'),
      ]).replaceAll('\n', '\r\n');
      final blocks = DesktopOcrEngine.parseTesseractTsv(crlf);
      expect(blocks.length, 1);
      expect(blocks.first.text, 'HELLO');
    });

    test('Non-numeric confidence keeps the text but reports no confidence', () {
      final tsv = _tsv([
        ['5', '1', '1', '1', '1', '1', '0', '0', '10', '10', 'abc', 'HELLO'].join('\t'),
      ]);
      final ocrResult = _ocrFromTsv(tsv);
      expect(ocrResult.fullText, 'HELLO');
      expect(ocrResult.confidence, isNull);
    });
  });
}
