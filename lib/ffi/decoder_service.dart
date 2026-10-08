import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'decode_result.dart';
import 'exalted_bindings.dart';

/// Owns the native library handle and the native-side frame buffer.
///
/// The Y plane is copied into native memory on every call, so the camera
/// plugin's shared buffer is never referenced after [probe] returns.
class DecoderService {
  ExaltedBindings? _bindings;
  bool _loadAttempted = false;
  bool _disposed = false;

  Pointer<Uint8> _buffer = nullptr;
  int _bufferCapacity = 0;
  Pointer<Int32> _out = nullptr;

  /// Why loading failed, if it did.
  String? loadError;

  bool get isAvailable {
    _ensureLoaded();
    return _bindings != null;
  }

  void _ensureLoaded() {
    if (_loadAttempted) return;
    _loadAttempted = true;
    try {
      final bindings = ExaltedBindings.open();
      final version = bindings.apiVersion();
      _bindings = bindings;
      debugPrint(
        '[EXALTED][FFI] loaded ${ExaltedBindings.libraryName}, api v$version',
      );
    } catch (e) {
      loadError = '$e';
      debugPrint('[EXALTED][FFI] LOAD FAILED: $e');
    }
  }

  /// Runs the native probe on a luminance frame. Returns null when the native
  /// library is unavailable.
  NativeProbe? probe({
    required Uint8List luma,
    required int width,
    required int height,
    required int rowStride,
    required int rotationDegrees,
  }) {
    if (_disposed) return null;
    _ensureLoaded();
    final bindings = _bindings;
    if (bindings == null) return null;

    if (luma.length > _bufferCapacity) {
      if (_buffer != nullptr) calloc.free(_buffer);
      _buffer = calloc<Uint8>(luma.length);
      _bufferCapacity = luma.length;
    }
    if (_out == nullptr) _out = calloc<Int32>(9);

    _buffer.asTypedList(luma.length).setAll(0, luma);
    final status = bindings.probe(
      _buffer,
      luma.length,
      width,
      height,
      rowStride,
      rotationDegrees,
      _out,
      9,
    );
    final o = _out.asTypedList(9);
    return NativeProbe(
      status: status,
      apiVersion: o[0],
      width: o[1],
      height: o[2],
      rowStride: o[3],
      rotationDegrees: o[4],
      meanLuma: o[5],
      minLuma: o[6],
      maxLuma: o[7],
      callCount: o[8],
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_buffer != nullptr) calloc.free(_buffer);
    if (_out != nullptr) calloc.free(_out);
    _buffer = nullptr;
    _out = nullptr;
    _bufferCapacity = 0;
  }
}
