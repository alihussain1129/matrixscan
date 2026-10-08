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
