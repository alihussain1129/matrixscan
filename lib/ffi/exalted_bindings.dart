import 'dart:ffi';
import 'dart:io' show Platform;

typedef VersionNative = Int32 Function();
typedef VersionFn = int Function();

typedef ProbeNative = Int32 Function(
  Pointer<Uint8> luma,
  Int32 lumaLen,
  Int32 width,
  Int32 height,
  Int32 rowStride,
  Int32 rotationDegrees,
  Pointer<Int32> out,
  Int32 outLen,
);
typedef ProbeFn = int Function(
  Pointer<Uint8> luma,
  int lumaLen,
  int width,
  int height,
  int rowStride,
  int rotationDegrees,
  Pointer<Int32> out,
  int outLen,
);

/// Typed handles to the C functions exported by libexalted_ffi.so.
class ExaltedBindings {
  ExaltedBindings._(DynamicLibrary lib)
    : apiVersion = lib.lookupFunction<VersionNative, VersionFn>(
        'exalted_api_version',
      ),
      probe = lib.lookupFunction<ProbeNative, ProbeFn>('exalted_probe');

  static const String libraryName = 'libexalted_ffi.so';

  final VersionFn apiVersion;
  final ProbeFn probe;

  /// Opens the native library. Throws if it is missing or a symbol is absent.
  static ExaltedBindings open() {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'The native core is only loaded on Android '
        '(running on ${Platform.operatingSystem}).',
      );
    }
    return ExaltedBindings._(DynamicLibrary.open(libraryName));
  }
}
