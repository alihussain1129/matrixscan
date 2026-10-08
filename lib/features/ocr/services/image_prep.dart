import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../models/ocr_result.dart';

/// An image ready for the OCR engine. If [tempDir] is set the image was
/// resized into a temporary file that [cleanup] deletes.
class PreparedImage {
  const PreparedImage({
    required this.path,
    required this.originalWidth,
    required this.originalHeight,
    required this.width,
    required this.height,
    this.tempDir,
  });

  final String path;
  final int originalWidth;
  final int originalHeight;
  final int width;
  final int height;
  final Directory? tempDir;

  Future<void> cleanup() async {
    final dir = tempDir;
    if (dir == null) return;
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

class ImagePrep {
  const ImagePrep._();

  /// Checks the image size without a full decode. Only when the longest side
  /// is above [maxSide] is the image decoded again at a smaller size.
  static Future<PreparedImage> prepare(
    String path, {
    required int maxSide,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw OcrException(
        OcrError.of(OcrErrorType.unsupportedImage, technical: 'File not found'),
      );
    }

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw OcrException(
          OcrError.of(OcrErrorType.corruptImage, technical: 'Empty file'),
        );
      }
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
      } catch (e) {
        throw OcrException(
          OcrError.of(OcrErrorType.corruptImage, technical: '$e'),
        );
      }

      final w = descriptor.width;
      final h = descriptor.height;
      if (w <= 0 || h <= 0) {
        throw OcrException(
          OcrError.of(OcrErrorType.corruptImage, technical: 'Zero size'),
        );
      }

      final longest = math.max(w, h);
      if (longest <= maxSide) {
        return PreparedImage(
          path: path,
          originalWidth: w,
          originalHeight: h,
          width: w,
          height: h,
        );
      }

      // Too large: decode again at a smaller size and use a temp file.
      final scale = maxSide / longest;
      final tw = math.max(1, (w * scale).round());
      final th = math.max(1, (h * scale).round());

      ui.Codec? codec;
      ui.Image? image;
      Directory? dir;
      try {
        codec = await descriptor.instantiateCodec(
          targetWidth: tw,
          targetHeight: th,
        );
        final frame = await codec.getNextFrame();
        image = frame.image;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw OcrException(
            OcrError.of(OcrErrorType.failed, technical: 'PNG encode failed'),
          );
        }
        dir = await Directory.systemTemp.createTemp('exalted_ocr_');
        final out = File('${dir.path}${Platform.pathSeparator}prepared.png');
        await out.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        return PreparedImage(
          path: out.path,
          originalWidth: w,
          originalHeight: h,
          width: tw,
          height: th,
          tempDir: dir,
        );
      } catch (e) {
        if (dir != null) {
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
        if (e is OcrException) rethrow;
        throw OcrException(OcrError.of(OcrErrorType.failed, technical: '$e'));
      } finally {
        image?.dispose();
        codec?.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
