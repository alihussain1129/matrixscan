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

typedef DecodeNative = Int32 Function(
  Pointer<Uint8> luma,
  Int32 lumaLen,
  Int32 width,
  Int32 height,
  Int32 rowStride,
  Int32 formatsMask,
  Int32 tryHarder,
  Pointer<Int32> info,
  Int32 infoLen,
  Pointer<Uint8> textOut,
  Int32 textCap,
);
typedef DecodeFn = int Function(
  Pointer<Uint8> luma,
  int lumaLen,
  int width,
  int height,
  int rowStride,
  int formatsMask,
  int tryHarder,
  Pointer<Int32> info,
  int infoLen,
  Pointer<Uint8> textOut,
  int textCap,
);

/// Typed handles to the C functions exported by libexalted_ffi.so.
class ExaltedBindings {
  ExaltedBindings._(DynamicLibrary lib)
    : apiVersion = lib.lookupFunction<VersionNative, VersionFn>(
        'exalted_api_version',
      ),
      probe = lib.lookupFunction<ProbeNative, ProbeFn>('exalted_probe'),
      decode = lib.lookupFunction<DecodeNative, DecodeFn>('exalted_decode');

  static const String libraryName = 'libexalted_ffi.so';

  /// Must match exalted_api_version() in cpp/src/ffi_api.cpp.
  static const int expectedApiVersion = 2;

  /// Slots written by exalted_decode (EXALTED_DECODE_INFO_LEN).
  static const int decodeInfoLen = 12;

  final VersionFn apiVersion;
  final ProbeFn probe;
  final DecodeFn decode;

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
