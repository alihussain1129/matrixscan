import '../../scanner/captured_frame.dart';
import '../core/device_frame.dart';

/// Maps the scanner's [CapturedFrame] onto the platform-independent
/// [DeviceFrame] without losing any image layout information.
///
/// * BGRA frames become a single `bgra8888` plane (pixel stride 4).
/// * Gray/luma frames (plane 0 of a YUV420 camera frame) become a single
///   `luma8` plane (pixel stride 1).
/// * `stride` becomes the plane's row stride, so row padding is preserved.
/// * `rotationDegrees` is carried over unchanged (clockwise, to upright).
///
/// A [CapturedFrame] is already an immutable copy that outlives the camera's
/// buffers, so the pixel bytes are shared, not copied, and no release
/// callback is needed. Call [DeviceFrame.copy] before mutating the bytes.
DeviceFrame deviceFrameFromCaptured(
  CapturedFrame frame, {
  required DateTime timestamp,
  int sequence = 0,
}) {
  return DeviceFrame.single(
    width: frame.width,
    height: frame.height,
    format: frame.isBgra ? DevicePixelFormat.bgra8888 : DevicePixelFormat.luma8,
    bytes: frame.bytes,
    rowStride: frame.stride,
    pixelStride: frame.isBgra ? 4 : 1,
    rotationDegrees: frame.rotationDegrees,
    timestamp: timestamp,
    sequence: sequence,
  );
}
