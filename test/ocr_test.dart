import 'package:exalted/features/ocr/controllers/ocr_controller.dart';
import 'package:exalted/features/ocr/models/ocr_result.dart';
import 'package:exalted/features/ocr/views/ocr_result_screen.dart';
import 'package:exalted/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_ocr_engine.dart';

OcrLine _line(String text, {double? confidence, List<String>? languages}) {
  return OcrLine(
    text: text,
    words: [OcrWord(text: text, boundingBox: Rect.zero)],
    boundingBox: Rect.zero,
    languages: languages ?? const ['en'],
    confidence: confidence,
  );
}

OcrResult _okResult(List<OcrLine> lines) {
  return OcrResult(
    success: true,
    fullText: 'Hello Exalted',
    blocks: [
      OcrBlock(
        text: 'Hello Exalted',
        lines: lines,
        boundingBox: Rect.zero,
        languages: const ['en'],
      ),
    ],
    imageWidth: 1000,
    imageHeight: 800,
    analyzedWidth: 1000,
    analyzedHeight: 800,
    engine: 'fake',
    script: 'Latin',
  );
}

void main() {
  group('OcrResult', () {
    test('confidence is unavailable when the engine gives none', () {
      final r = _okResult([_line('a'), _line('b')]);
      expect(r.confidence, isNull);
    });

    test('confidence averages only lines that have one', () {
      final r = _okResult([
        _line('a', confidence: 0.8),
        _line('b'),
        _line('c', confidence: 1.0),
      ]);
      expect(r.confidence, closeTo(0.9, 0.0001));
    });

    test('lines, words and language are derived from the blocks', () {
      final r = _okResult([_line('a'), _line('b')]);
      expect(r.lines.length, 2);
      expect(r.words.length, 2);
      expect(r.language, 'en');
      expect(r.resized, isFalse);
    });

    test('failure results carry a friendly message', () {
      final r = OcrResult.failure(OcrError.of(OcrErrorType.noTextFound));
      expect(r.success, isFalse);
      expect(r.error!.message, 'No readable text found.');
    });
  });

  group('OcrController', () {
    test('run() ends in done with the engine result', () async {
      final c = ProviderContainer(
        overrides: [
          ocrEngineProvider.overrideWithValue(
            FakeOcrEngine(_okResult([_line('a')])),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c.read(ocrControllerProvider.notifier).run('/x.png');
      final s = c.read(ocrControllerProvider);
      expect(s.status, OcrStatus.done);
      expect(s.result!.fullText, 'Hello Exalted');
    });

    test('run() ends in failed when the engine fails', () async {
      final c = ProviderContainer(
        overrides: [
          ocrEngineProvider.overrideWithValue(
            FakeOcrEngine(
              OcrResult.failure(OcrError.of(OcrErrorType.noTextFound)),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c.read(ocrControllerProvider.notifier).run('/x.png');
      expect(c.read(ocrControllerProvider).status, OcrStatus.failed);
    });

    test('reset() clears the result', () async {
      final c = ProviderContainer(
        overrides: [
          ocrEngineProvider.overrideWithValue(
            FakeOcrEngine(_okResult([_line('a')])),
          ),
        ],
      );
      addTearDown(c.dispose);

      final notifier = c.read(ocrControllerProvider.notifier);
      await notifier.run('/x.png');
      notifier.reset();
      expect(c.read(ocrControllerProvider).status, OcrStatus.idle);
      expect(c.read(ocrControllerProvider).result, isNull);
    });
  });

  testWidgets('result screen shows the text and the action buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ocrEngineProvider.overrideWithValue(
            FakeOcrEngine(_okResult([_line('a')])),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: AppColors.lightScheme,
            extensions: const [AppColors.lightExtra],
          ),
          home: const OcrResultScreen(imagePath: '/missing.png'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Hello Exalted'), findsOneWidget);
    expect(find.text('COPY'), findsOneWidget);
    expect(find.text('SHARE'), findsOneWidget);
    expect(find.text('SAVE'), findsOneWidget);
  });
}
