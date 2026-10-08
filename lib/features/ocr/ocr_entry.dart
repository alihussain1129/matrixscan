import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controllers/ocr_controller.dart';
import 'views/ocr_result_screen.dart';

/// Single entry point into the OCR feature. The scanner only calls this;
/// it knows nothing about OCR screens or controllers.
Future<void> openOcr(
  BuildContext context,
  WidgetRef ref,
  String imagePath,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OcrResultScreen(imagePath: imagePath),
    ),
  );
  ref.read(ocrControllerProvider.notifier).reset();
}
