import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../ffi/decode_result.dart';
import '../../ffi/decoder_service.dart';

/// Finds one barcode in an image file (a gallery photo or screenshot) with
/// the same native decoder the live scanner uses.
class ImageBarcodeDecoder {
  /// Long-side sizes tried in order; decoding stops at the first hit.
  static const List<int> _longSides = [2048, 1024];

  /// Returns null when the image holds no readable barcode.
  /// Throws [StateError] when the native decoder is unavailable or fails.
  Future<DecodedBarcode?> decodeFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoder = DecoderService();
    try {
      if (!decoder.isAvailable) {
        throw StateError(decoder.loadError ?? 'Native decoder unavailable');
      }
      for (final longSide in _longSides) {
        final gray = await _decodeToGray(bytes, longSide);
        final result = decoder.decode(
          luma: gray.pixels,
          width: gray.width,
          height: gray.height,
          rowStride: gray.width,
          tryHarder: true,
        );
        if (result != null) return result;
        if (decoder.lastDecodeStatus < 0) {
          throw StateError('Native decoder error ${decoder.lastDecodeStatus}');
        }
      }
      return null;
    } finally {
      decoder.dispose();
    }
  }
}

class _Gray {
  const _Gray(this.pixels, this.width, this.height);

  final Uint8List pixels;
  final int width;
  final int height;
}

/// Decodes [encoded] at no more than [longSide] pixels and converts it to an
/// 8-bit grayscale buffer (transparent areas count as white).
Future<_Gray> _decodeToGray(Uint8List encoded, int longSide) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.min(
      1.0,
      longSide / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Could not read the image pixels');
    final width = image.width;
    final height = image.height;
    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final pixels = await Isolate.run(() => _rgbaToGray(rgba, width, height));
    return _Gray(pixels, width, height);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Uint8List _rgbaToGray(Uint8List rgba, int width, int height) {
  final gray = Uint8List(width * height);
  var src = 0;
  for (var i = 0; i < gray.length; i++, src += 4) {
    final a = rgba[src + 3];
    var v = (rgba[src] * 77 + rgba[src + 1] * 150 + rgba[src + 2] * 29) >> 8;
    if (a != 255) {
      v = (v * a + 255 * (255 - a)) ~/ 255;
    }
    gray[i] = v;
  }
  return gray;
}
