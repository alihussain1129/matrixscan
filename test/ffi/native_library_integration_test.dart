// Real-native tests: these load the actual libexalted_ffi.so / exalted_ffi.dll
// and call the same C functions the app uses. No mocks are involved.
//
// They run only when the library can be found, either through
// EXALTED_FFI_PATH or a development build bundle. Otherwise they are SKIPPED
// with an explicit reason; a skipped test here means "real native decoding was
// not exercised", never "it passed".
//
//   EXALTED_FFI_PATH=/path/to/build flutter test test/ffi
import 'dart:ffi';

import 'package:exalted/ffi/exalted_bindings.dart';
import 'package:exalted/ffi/native_library_loader.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

String? _probeNativeLibrary() {
  try {
    return NativeLibraryLoader.open().path;
  } on NativeLibraryException {
    return null;
  }
}

void main() {
  final found = _probeNativeLibrary();
  final skipReason = found == null
      ? 'native library not found (set EXALTED_FFI_PATH); real native '
            'decoding was NOT exercised'
      : null;

  group('real native library', () {
    test('loads and reports the API version the app expects', () {
      final bindings = ExaltedBindings.open();
      expect(bindings.apiVersion(), ExaltedBindings.expectedApiVersion);
      expect(bindings.loadedFrom, isNotEmpty);
    }, skip: skipReason);

    test('blank frame decodes to "no barcode", bad buffer is rejected', () {
      final bindings = ExaltedBindings.open();
      const side = 64;
      final luma = calloc<Uint8>(side * side);
      final info = calloc<Int32>(ExaltedBindings.decodeInfoLen);
      final text = calloc<Uint8>(64);
      try {
        for (var i = 0; i < side * side; i++) {
          luma[i] = 200;
        }
        // formatsMask 0 means "all supported formats" (see ffi_api.cpp).
        final none = bindings.decode(
          luma,
          side * side,
          side,
          side,
          side,
          0,
          0,
          info,
          ExaltedBindings.decodeInfoLen,
          text,
          64,
        );
        expect(none, 0);

        // Buffer shorter than height * stride implies: status -3.
        final tooShort = bindings.decode(
          luma,
          10,
          side,
          side,
          side,
          0,
          0,
          info,
          ExaltedBindings.decodeInfoLen,
          text,
          64,
        );
        expect(tooShort, -3);
      } finally {
        calloc.free(luma);
        calloc.free(info);
        calloc.free(text);
      }
    }, skip: skipReason);
  });
}
