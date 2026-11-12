import 'dart:typed_data';

/// Pixel layout of a [DeviceFrame]. The planes carry the real strides.
enum DevicePixelFormat {
  bgra8888,
  rgba8888,
  luma8,
  nv21,
  yuv420,
  other;

  /// Bytes per pixel for packed single-plane formats, else null.
  int? get bytesPerPixel => switch (this) {
    DevicePixelFormat.bgra8888 => 4,
    DevicePixelFormat.rgba8888 => 4,
    DevicePixelFormat.luma8 => 1,
    _ => null,
  };
}

/// One plane of image data with its exact row layout.
///
/// Row `r` starts at `r * rowStride`; pixel `c` of that row starts at
/// `c * pixelStride`. [rowStride] may exceed `width * pixelStride` (padding).
class DeviceImagePlane {
  DeviceImagePlane({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rowStride,
    this.pixelStride = 1,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Plane size must be positive ($width x $height)');
    }
    if (pixelStride <= 0) {
      throw ArgumentError('pixelStride must be positive');
    }
    if (rowStride < width * pixelStride) {
      throw ArgumentError(
        'rowStride $rowStride is smaller than width*pixelStride '
        '${width * pixelStride}',
      );
    }
    final needed = rowStride * (height - 1) + width * pixelStride;
    if (bytes.length < needed) {
      throw ArgumentError(
        'Plane has ${bytes.length} bytes but its layout needs $needed',
      );
    }
  }

  final Uint8List bytes;
  final int width;
  final int height;
  final int rowStride;
  final int pixelStride;

  bool get isTightlyPacked => rowStride == width * pixelStride;

  DeviceImagePlane copy() => DeviceImagePlane(
    bytes: Uint8List.fromList(bytes),
    width: width,
    height: height,
    rowStride: rowStride,
    pixelStride: pixelStride,
  );
}

/// Platform-independent image frame.
///
/// Ownership: whoever receives a frame from a stream or from capture owns it
/// and calls [release] exactly once when done (more calls are harmless).
/// [release] runs the producer's `onRelease` callback, which is where
/// native-backed buffers are freed. After release, [planes] throws.
/// Use [copy] to keep pixel data beyond the lifetime of the original.
class DeviceFrame {
  DeviceFrame({
    required this.width,
    required this.height,
    required this.format,
    required List<DeviceImagePlane> planes,
    required this.timestamp,
    int rotationDegrees = 0,
    this.mirrored = false,
    this.sequence = 0,
    void Function()? onRelease,
  }) : rotationDegrees = _normalizeRotation(rotationDegrees),
       _planes = List<DeviceImagePlane>.unmodifiable(planes),
       // ignore: prefer_initializing_formals
       _onRelease = onRelease {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Frame size must be positive ($width x $height)');
    }
    if (planes.isEmpty) throw ArgumentError('A frame needs at least one plane');
  }

  /// Packed single-plane frame (BGRA, RGBA, luma).
  factory DeviceFrame.single({
    required int width,
    required int height,
    required DevicePixelFormat format,
    required Uint8List bytes,
    required DateTime timestamp,
    int? rowStride,
    int? pixelStride,
    int rotationDegrees = 0,
    bool mirrored = false,
    int sequence = 0,
    void Function()? onRelease,
  }) {
    final pixel = pixelStride ?? format.bytesPerPixel ?? 1;
    return DeviceFrame(
      width: width,
      height: height,
      format: format,
      planes: [
        DeviceImagePlane(
          bytes: bytes,
          width: width,
          height: height,
          rowStride: rowStride ?? width * pixel,
          pixelStride: pixel,
        ),
      ],
      timestamp: timestamp,
      rotationDegrees: rotationDegrees,
      mirrored: mirrored,
      sequence: sequence,
      onRelease: onRelease,
    );
  }

  final int width;
  final int height;
  final DevicePixelFormat format;

  /// Clockwise rotation (0, 90, 180, 270) to apply for upright display.
  final int rotationDegrees;
  final bool mirrored;
  final DateTime timestamp;
  final int sequence;

  final List<DeviceImagePlane> _planes;
  final void Function()? _onRelease;
  bool _released = false;

  bool get isReleased => _released;

  List<DeviceImagePlane> get planes {
    if (_released) throw StateError('DeviceFrame used after release');
    return _planes;
  }

  void release() {
    if (_released) return;
    _released = true;
    _onRelease?.call();
  }

  /// Independent deep copy with identical metadata and no release callback.
  DeviceFrame copy() => DeviceFrame(
    width: width,
    height: height,
    format: format,
    planes: [for (final plane in planes) plane.copy()],
    timestamp: timestamp,
    rotationDegrees: rotationDegrees,
    mirrored: mirrored,
    sequence: sequence,
  );

  static int _normalizeRotation(int degrees) {
    if (degrees % 90 != 0) {
      throw ArgumentError('Rotation must be a multiple of 90, got $degrees');
    }
    return ((degrees % 360) + 360) % 360;
  }
}
