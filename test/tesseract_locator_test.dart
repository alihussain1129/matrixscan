import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/ocr/services/tesseract_locator.dart';

void main() {
  group('TesseractLocator', () {
    test('parses language codes and ignores the Tesseract heading', () {
      final languages = TesseractLocator.parseLanguages(
        'List of available languages in "C:/Tesseract/tessdata/" (3):\r\n'
        'eng\r\n deu \r\nosd\r\n',
      );
      expect(languages, {'eng', 'deu', 'osd'});
    });

    test('installation reports requested language availability', () {
      const installation = TesseractInstallation(
        executable: r'C:\Exalted\tesseract\tesseract.exe',
        languages: {'eng', 'osd'},
      );
      expect(installation.supportsLanguage('eng'), isTrue);
      expect(installation.supportsLanguage('deu'), isFalse);
      expect(installation.displayLanguages, ['eng']);
    });

    test('builds Windows bundled and standard installation paths on Linux', () {
      final candidates = TesseractLocator.buildCandidates(
        appDirectory: r'C:\Program Files\Exalted',
        isWindows: true,
        isLinux: false,
        isMacOS: false,
        pathSeparator: '\\',
        environment: {
          'ProgramFiles': r'D:\Apps',
          'ProgramFiles(x86)': r'E:\Apps32',
        },
      );

      expect(
        candidates,
        contains(r'C:\Program Files\Exalted\tesseract\tesseract.exe'),
      );
      expect(candidates, contains(r'C:\Program Files\Exalted\tesseract.exe'));
      expect(
        candidates,
        contains(r'C:\Program Files\Tesseract-OCR\tesseract.exe'),
      );
      expect(candidates, contains(r'D:\Apps\Tesseract-OCR\tesseract.exe'));
      expect(candidates, contains(r'E:\Apps32\Tesseract-OCR\tesseract.exe'));
      expect(candidates, isNot(contains('/usr/bin/tesseract')));
    });

    test('Windows candidate de-duplication ignores path letter case', () {
      final candidates = TesseractLocator.buildCandidates(
        customExecutablePath: r'C:\EXALTED\TESSERACT.EXE',
        appDirectory: r'C:\EXALTED',
        isWindows: true,
        isLinux: false,
        isMacOS: false,
        pathSeparator: '\\',
      );
      expect(
        candidates
            .where(
              (path) =>
                  path.toLowerCase() ==
                  r'C:\exalted\tesseract.exe'.toLowerCase(),
            )
            .length,
        1,
      );
    });

    test('builds Linux candidates independently', () {
      final candidates = TesseractLocator.buildCandidates(
        appDirectory: '/opt/exalted',
        isWindows: false,
        isLinux: true,
        isMacOS: false,
        pathSeparator: '/',
      );
      expect(candidates, contains('/opt/exalted/tesseract/tesseract'));
      expect(candidates, contains('/usr/bin/tesseract'));
      expect(
        candidates,
        isNot(contains(r'C:\Program Files\Tesseract-OCR\tesseract.exe')),
      );
    });

    test('constructs Windows TESSDATA_PREFIX from a backslash path', () {
      final environment = TesseractLocator.environmentForExecutable(
        r'C:\Exalted\tesseract\tesseract.exe',
        pathSeparator: '\\',
        directoryExists: (path) => path == r'C:\Exalted\tesseract\tessdata',
      );
      expect(environment, {
        'TESSDATA_PREFIX': r'C:\Exalted\tesseract\tessdata',
      });
    });

    test('does not set TESSDATA_PREFIX when sibling data is missing', () {
      final environment = TesseractLocator.environmentForExecutable(
        r'C:\Exalted\tesseract.exe',
        pathSeparator: '\\',
        directoryExists: (_) => false,
      );
      expect(environment, isNull);
    });

    test('uses a real sibling tessdata directory on the host', () {
      final root = Directory.systemTemp.createTempSync('tesseract_locator_');
      addTearDown(() => root.deleteSync(recursive: true));
      final executable = File(
        '${root.path}${Platform.pathSeparator}tesseract.exe',
      )..createSync();
      Directory('${root.path}${Platform.pathSeparator}tessdata').createSync();
      final environment = TesseractLocator.environmentForExecutable(
        executable.path,
      );
      expect(environment, isNotNull);
      expect(
        environment!['TESSDATA_PREFIX'],
        '${root.path}${Platform.pathSeparator}tessdata',
      );
    });
  });
}
