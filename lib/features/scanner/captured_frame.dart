import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' show CameraImage, ImageFormatGroup;

/// A copy of one camera frame that stays valid after the camera reuses its
/// buffers. Either BGRA (desktop) or a gray/luma plane (phones).
class CapturedFrame {
  const CapturedFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.stride,
    required this.isBgra,
    required this.rotationDegrees,
  });

  factory CapturedFrame.fromCameraImage(
    CameraImage image,
    int rotationDegrees,
  ) {
    final plane = image.planes.first;
    return CapturedFrame(
      bytes: Uint8List.fromList(plane.bytes),
      width: image.width,
      height: image.height,
      stride: plane.bytesPerRow,
      isBgra: image.format.group == ImageFormatGroup.bgra8888,
      rotationDegrees: rotationDegrees,
    );
  }

  final Uint8List bytes;
  final int width;
  final int height;
  final int stride;
  final bool isBgra;

  /// Clockwise rotation that makes the image upright.
  final int rotationDegrees;
}

/// Upright RGBA pixels.
class FrameRgba {
  const FrameRgba(this.pixels, this.width, this.height);

  final Uint8List pixels;
  final int width;
  final int height;
}

/// Rotates the frame upright and crops it to the normalized region
/// ([left], [top], [right], [bottom] as 0..1 of the upright image).
FrameRgba convertFrame(
  CapturedFrame f, {
  double left = 0,
  double top = 0,
  double right = 1,
  double bottom = 1,
}) {
  final rot = f.rotationDegrees % 360;
  final swap = rot == 90 || rot == 270;
  final outW = swap ? f.height : f.width;
  final outH = swap ? f.width : f.height;
  final x0 = (left.clamp(0.0, 1.0) * outW).floor().clamp(0, outW - 1).toInt();
  final y0 = (top.clamp(0.0, 1.0) * outH).floor().clamp(0, outH - 1).toInt();
  final x1 = (right.clamp(0.0, 1.0) * outW).ceil().clamp(x0 + 1, outW).toInt();
  final y1 = (bottom.clamp(0.0, 1.0) * outH).ceil().clamp(y0 + 1, outH).toInt();
  final cw = x1 - x0;
  final ch = y1 - y0;
  final out = Uint8List(cw * ch * 4);
  final src = f.bytes;
  var o = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      int sx;
      int sy;
      if (rot == 90) {
        sx = y;
        sy = f.height - 1 - x;
      } else if (rot == 180) {
        sx = f.width - 1 - x;
        sy = f.height - 1 - y;
      } else if (rot == 270) {
        sx = f.width - 1 - y;
        sy = x;
      } else {
        sx = x;
        sy = y;
      }
      if (f.isBgra) {
        final i = sy * f.stride + sx * 4;
        out[o] = src[i + 2];
        out[o + 1] = src[i + 1];
        out[o + 2] = src[i];
      } else {
        final v = src[sy * f.stride + sx];
        out[o] = v;
        out[o + 1] = v;
        out[o + 2] = v;
      }
      out[o + 3] = 255;
      o += 4;
    }
  }
  return FrameRgba(out, cw, ch);
}

class EncodedFrame {
  const EncodedFrame(this.png, this.width, this.height);

  final Uint8List png;
  final int width;
  final int height;
}

/// Converts on a background isolate, then encodes a PNG. Null on failure.
Future<EncodedFrame?> encodeFrame(
  CapturedFrame f, {
  double left = 0,
  double top = 0,
  double right = 1,
  double bottom = 1,
}) async {
  try {
    final rgba = await Isolate.run(
      () => convertFrame(f, left: left, top: top, right: right, bottom: bottom),
    );
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba.pixels,
      rgba.width,
      rgba.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    final image = await done.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    return EncodedFrame(
      Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
      rgba.width,
      rgba.height,
    );
  } catch (_) {
    return null;
  }
}
