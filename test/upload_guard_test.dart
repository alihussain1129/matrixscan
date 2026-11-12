import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/core/upload_guard.dart';

void main() {
  group('safeUploadExtension', () {
    test('accepts allowed extensions case-insensitively', () {
      expect(safeUploadExtension('a.jpg'), 'jpg');
      expect(safeUploadExtension('IMG_001.PNG'), 'png');
    });

    test('ignores directory parts in the name', () {
      expect(safeUploadExtension(r'..\..\evil\x.jpg'), 'jpg');
      expect(safeUploadExtension('../../x.bmp'), 'bmp');
    });

    test('rejects traversal hidden in the extension', () {
      expect(safeUploadExtension('a./../../etc/x'), isNull);
    });

    test('rejects unknown, missing or empty extensions', () {
      expect(safeUploadExtension('x.exe'), isNull);
      expect(safeUploadExtension('noext'), isNull);
      expect(safeUploadExtension('trailing.'), isNull);
      expect(safeUploadExtension(''), isNull);
    });
  });
}
