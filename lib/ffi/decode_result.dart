import 'dart:ui' show Offset;

/// What the native probe reported about one luminance frame.
class NativeProbe {
  const NativeProbe({
    required this.status,
    required this.apiVersion,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.rotationDegrees,
    required this.meanLuma,
    required this.minLuma,
    required this.maxLuma,
    required this.callCount,
  });

  /// 0 = ok, -1 null/outLen, -2 bad dimensions, -3 buffer too short.
  final int status;
  final int apiVersion;
  final int width;
  final int height;
  final int rowStride;
  final int rotationDegrees;
  final int meanLuma;
  final int minLuma;
  final int maxLuma;
  final int callCount;

  bool get ok => status == 0;

  @override
  String toString() =>
      'status=$status api=$apiVersion ${width}x$height stride=$rowStride '
      'rot=$rotationDegrees luma(mean=$meanLuma min=$minLuma max=$maxLuma) '
      'nativeCalls=$callCount';
}

/// Barcode symbologies the native decoder can report.
/// [flag] equals the EXALTED_FMT_* value in cpp/include/exalted/ffi_api.h.
enum BarcodeKind {
  aztec(1 << 0, 'Aztec'),
  codabar(1 << 1, 'Codabar'),
  code39(1 << 2, 'Code 39'),
  code93(1 << 3, 'Code 93'),
  code128(1 << 4, 'Code 128'),
  dataBar(1 << 5, 'GS1 DataBar'),
  dataBarExpanded(1 << 6, 'GS1 DataBar Expanded'),
  dataMatrix(1 << 7, 'Data Matrix'),
  ean8(1 << 8, 'EAN-8'),
  ean13(1 << 9, 'EAN-13'),
  itf(1 << 10, 'ITF'),
  maxiCode(1 << 11, 'MaxiCode'),
  pdf417(1 << 12, 'PDF417'),
  qrCode(1 << 13, 'QR Code'),
  upcA(1 << 14, 'UPC-A'),
  upcE(1 << 15, 'UPC-E'),
  microQr(1 << 16, 'Micro QR'),
  unknown(0, 'Unknown');

  const BarcodeKind(this.flag, this.label);

  final int flag;
  final String label;

  static BarcodeKind fromFlag(int flag) {
    for (final kind in BarcodeKind.values) {
      if (kind.flag == flag && flag != 0) return kind;
    }
    return BarcodeKind.unknown;
  }
}

/// One barcode decoded by the native core.
class DecodedBarcode {
  const DecodedBarcode({
    required this.text,
    required this.kind,
    required this.corners,
    required this.decodeMicros,
    required this.frameWidth,
    required this.frameHeight,
  });

  final String text;
  final BarcodeKind kind;

  /// Corners in camera-image pixels: top-left, top-right, bottom-right,
  /// bottom-left (before any display rotation).
  final List<Offset> corners;

  final int decodeMicros;
  final int frameWidth;
  final int frameHeight;

  @override
  String toString() =>
      '${kind.label} "$text" (${(decodeMicros / 1000).toStringAsFixed(1)} ms)';
}
