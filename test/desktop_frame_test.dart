import 'dart:async';
import 'dart:typed_data';

import 'package:exalted/features/scanner/desktop_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bgraToGray converts BGRA pixels and ignores row padding', () {
    // 2x2 image. Row stride is 12 bytes: 8 bytes of pixels + 4 of padding.
    final bgra = Uint8List.fromList(<int>[
      255, 255, 255, 255, 0, 0, 0, 255, 9, 9, 9, 9, // white, black, padding
      0, 0, 255, 255, 0, 255, 0, 255, 9, 9, 9, 9, // red, green, padding
    ]);
    final gray = bgraToGray(bgra, 2, 2, 12);
    expect(gray.length, 4);
    expect(gray[0], 255);
    expect(gray[1], 0);
    expect(gray[2], (255 * 77) >> 8);
    expect(gray[3], (255 * 150) >> 8);
  });

  test('GrayConverter converts on a background isolate', () async {
    final converter = GrayConverter();
    final done = Completer<List<int>>();
    converter.onGray = (gray, width, height) {
      if (!done.isCompleted) done.complete(gray);
    };
    final frame = Uint8List.fromList(<int>[255, 255, 255, 255, 0, 0, 0, 255]);
    // The worker starts on the first call, so early frames may be skipped.
    var accepted = false;
    for (var i = 0; i < 100 && !accepted; i++) {
      accepted = converter.submit(frame, 2, 1, 8);
      if (!accepted) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    expect(accepted, isTrue);
    final gray = await done.future.timeout(const Duration(seconds: 5));
    expect(gray, <int>[255, 0]);
    converter.dispose();
  });
}
