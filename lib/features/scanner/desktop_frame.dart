import 'dart:typed_data';

/// Converts a BGRA camera frame (desktop cameras) into an 8-bit gray image
/// with no row padding, which is what the native decoder expects.
Uint8List bgraToGray(Uint8List bgra, int width, int height, int rowStride) {
  final gray = Uint8List(width * height);
  var o = 0;
  for (var y = 0; y < height; y++) {
    var i = y * rowStride;
    for (var x = 0; x < width; x++, i += 4, o++) {
      // Integer weights that add up to 256. Bytes are B, G, R, A.
      gray[o] = (bgra[i] * 29 + bgra[i + 1] * 150 + bgra[i + 2] * 77) >> 8;
    }
  }
  return gray;
}
