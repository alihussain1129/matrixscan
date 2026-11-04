import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/ocr/services/tesseract_locator.dart';

void main() {
  test(
    'TESSDATA_PREFIX parent directory is used for a bundled Windows install',
    () {
      final environment = TesseractLocator.environmentForExecutable(
        r'C:\Exalted\tesseract\tesseract.exe',
        pathSeparator: '\\',
        directoryExists: (path) => path == r'C:\Exalted\tesseract\tessdata',
      );

      expect(environment, {'TESSDATA_PREFIX': r'C:\Exalted\tesseract'});
    },
  );
}
