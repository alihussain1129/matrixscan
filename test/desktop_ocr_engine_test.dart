import 'dart:ui';

import 'package:exalted/features/ocr/models/ocr_result.dart';
import 'package:exalted/features/ocr/services/desktop_ocr_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopOcrEngine', () {
    test('reports correct name and Latin script', () {
      final engine = DesktopOcrEngine();
      expect(engine.name, 'Tesseract OCR (offline)');
      expect(engine.script, 'Latin');
    });

    test('parseTesseractTsv handles empty or header-only TSV', () {
      expect(DesktopOcrEngine.parseTesseractTsv(''), isEmpty);
      expect(
        DesktopOcrEngine.parseTesseractTsv(
          'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext',
        ),
        isEmpty,
      );
    });

    test('parseTesseractTsv correctly extracts words, lines, and blocks with bounding boxes', () {
      const sampleTsv = '''
level	page_num	block_num	par_num	line_num	word_num	left	top	width	height	conf	text
1	1	0	0	0	0	0	0	1000	800	-1	
2	1	1	0	0	0	10	20	300	100	-1	
3	1	1	1	0	0	10	20	300	100	-1	
4	1	1	1	1	0	10	20	200	40	-1	
5	1	1	1	1	1	10	20	90	40	95.0	HELLO
5	1	1	1	1	2	110	20	100	40	85.0	WORLD
4	1	1	1	2	0	10	70	150	40	-1	
5	1	1	1	2	1	10	70	150	40	90.0	EXALTED
''';

      final blocks = DesktopOcrEngine.parseTesseractTsv(sampleTsv);
      expect(blocks.length, 1);

      final block = blocks.first;
      expect(block.lines.length, 2);
      expect(block.text, 'HELLO WORLD\nEXALTED');

      // First line checks
      final line1 = block.lines[0];
      expect(line1.text, 'HELLO WORLD');
      expect(line1.words.length, 2);
      expect(line1.words[0].text, 'HELLO');
      expect(line1.words[0].boundingBox, const Rect.fromLTWH(10, 20, 90, 40));
      expect(line1.words[1].text, 'WORLD');
      expect(line1.words[1].boundingBox, const Rect.fromLTWH(110, 20, 100, 40));
      // Confidence average: (0.95 + 0.85) / 2 = 0.90
      expect(line1.confidence, closeTo(0.90, 0.001));
      // Line bounding box encompasses both words: left=10, top=20, right=210, bottom=60
      expect(line1.boundingBox.left, 10);
      expect(line1.boundingBox.top, 20);
      expect(line1.boundingBox.right, 210);
      expect(line1.boundingBox.bottom, 60);

      // Second line checks
      final line2 = block.lines[1];
      expect(line2.text, 'EXALTED');
      expect(line2.words.length, 1);
      expect(line2.confidence, closeTo(0.90, 0.001));

      // Block bounding box
      expect(block.boundingBox.left, 10);
      expect(block.boundingBox.top, 20);
      expect(block.boundingBox.right, 210);
      expect(block.boundingBox.bottom, 110);
    });

    test('recognizeFile returns unsupportedImage on missing file', () async {
      final engine = DesktopOcrEngine();
      final res = await engine.recognizeFile('/non_existent_image_12345.png');
      expect(res.success, isFalse);
      expect(res.error, isNotNull);
      expect(res.error!.type, OcrErrorType.unsupportedImage);
    });
  });
}
