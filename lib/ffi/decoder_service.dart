import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:ui' show Offset;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'decode_result.dart';
import 'decode_worker.dart';
import 'exalted_bindings.dart';

/// Owns the native library handle and the native-side buffers.
///
/// The Y plane is copied into native memory on every call, so the camera
/// plugin's shared buffer is never referenced after a call returns.
class DecoderService {
  static const int _textCapacity = 8192;

  ExaltedBindings? _bindings;
  bool _loadAttempted = false;
  bool _disposed = false;

  Pointer<Uint8> _buffer = nullptr;
  int _bufferCapacity = 0;
  Pointer<Int32> _out = nullptr;
  Pointer<Int32> _info = nullptr;
  Pointer<Uint8> _text = nullptr;

  DecodeWorker? _worker;
  bool _fallbackLogged = false;

  /// The in-flight [decodeAsync] call while the worker owns the buffer.
  Future<List<Object?>?>? _pendingDecode;

  /// Why loading failed, if it did.
  String? loadError;

  /// Native status code of the most recent [decode] call (0 = none found).
  int lastDecodeStatus = 0;

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
      if (version != ExaltedBindings.expectedApiVersion) {
        throw StateError(
          'native api v$version, app expects '
          'v${ExaltedBindings.expectedApiVersion}',
        );
      }
      _bindings = bindings;
      debugPrint(
        '[EXALTED][FFI] loaded ${ExaltedBindings.libraryName}, api v$version',
      );
    } catch (e) {
      loadError = '$e';
      debugPrint('[EXALTED][FFI] LOAD FAILED: $e');
    }
  }

  void _ensureCapacity(int lumaLength) {
    if (lumaLength > _bufferCapacity) {
      if (_buffer != nullptr) calloc.free(_buffer);
      _buffer = calloc<Uint8>(lumaLength);
      _bufferCapacity = lumaLength;
    }
    if (_out == nullptr) _out = calloc<Int32>(9);
    if (_info == nullptr) {
      _info = calloc<Int32>(ExaltedBindings.decodeInfoLen);
    }
    if (_text == nullptr) _text = calloc<Uint8>(_textCapacity);
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

    _ensureCapacity(luma.length);
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

  /// Decodes one barcode from a luminance frame.
  ///
  /// Returns null if nothing was found or the native library is unavailable;
  /// [lastDecodeStatus] tells those cases (and native errors) apart.
  DecodedBarcode? decode({
    required Uint8List luma,
    required int width,
    required int height,
    required int rowStride,
    int formatsMask = 0,
    bool tryHarder = false,
  }) {
    if (_disposed) return null;
    _ensureLoaded();
    final bindings = _bindings;
    if (bindings == null) return null;

    _ensureCapacity(luma.length);
    _buffer.asTypedList(luma.length).setAll(0, luma);

    final status = bindings.decode(
      _buffer,
      luma.length,
      width,
      height,
      rowStride,
      formatsMask,
      tryHarder ? 1 : 0,
      _info,
      ExaltedBindings.decodeInfoLen,
      _text,
      _textCapacity,
    );
    lastDecodeStatus = status;
    if (status != 1) return null;

    final i = _info.asTypedList(ExaltedBindings.decodeInfoLen);
    final text = utf8.decode(_text.asTypedList(i[1]), allowMalformed: true);
    return DecodedBarcode(
      text: text,
      kind: BarcodeKind.fromFlag(i[0]),
      corners: [
        Offset(i[2].toDouble(), i[3].toDouble()),
        Offset(i[4].toDouble(), i[5].toDouble()),
        Offset(i[6].toDouble(), i[7].toDouble()),
        Offset(i[8].toDouble(), i[9].toDouble()),
      ],
      decodeMicros: i[11],
      frameWidth: width,
      frameHeight: height,
    );
  }

  /// Like [decode], but the native call runs on a background isolate, so it
  /// never blocks the UI isolate. One call at a time: a call made while
  /// another is running returns null. If the worker cannot be used this falls
  /// back to the synchronous [decode].
  Future<DecodedBarcode?> decodeAsync({
    required Uint8List luma,
    required int width,
    required int height,
    required int rowStride,
    int formatsMask = 0,
    bool tryHarder = false,
    int flags = 0,
  }) async {
    if (_disposed) return null;
    _ensureLoaded();
    if (_bindings == null) return null;
    if (_pendingDecode != null) return null;

    _ensureCapacity(luma.length);
    _buffer.asTypedList(luma.length).setAll(0, luma);

    final worker = _worker ??= DecodeWorker();
    final call = worker.decode(
      address: _buffer.address,
      length: luma.length,
      width: width,
      height: height,
      rowStride: rowStride,
      formatsMask: formatsMask,
      tryHarder: tryHarder,
      flags: flags,
    );
    _pendingDecode = call;
    List<Object?>? reply;
    try {
      reply = await call;
    } finally {
      _pendingDecode = null;
    }
    if (_disposed) return null;

    if (reply == null || reply[0] == DecodeWorker.unavailableStatus) {
      if (!_fallbackLogged) {
        _fallbackLogged = true;
        debugPrint('[EXALTED][WORKER] unavailable, decoding on the UI isolate');
      }
      return decode(
        luma: luma,
        width: width,
        height: height,
        rowStride: rowStride,
        formatsMask: formatsMask,
        tryHarder: tryHarder,
      );
    }

    final status = reply[0] as int;
    lastDecodeStatus = status;
    if (status != 1) return null;

    final i = (reply[1] as List<Object?>).cast<int>();
    final text = reply[2] as String;
    return DecodedBarcode(
      text: text,
      kind: BarcodeKind.fromFlag(i[0]),
      corners: [
        Offset(i[2].toDouble(), i[3].toDouble()),
        Offset(i[4].toDouble(), i[5].toDouble()),
        Offset(i[6].toDouble(), i[7].toDouble()),
        Offset(i[8].toDouble(), i[9].toDouble()),
      ],
      decodeMicros: i[11],
      frameWidth: width,
      frameHeight: height,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _worker?.dispose();
    final pending = _pendingDecode;
    if (pending == null) {
      _freeBuffers();
    } else {
      // The worker may still be reading the shared buffer; free it afterwards.
      unawaited(pending.catchError((_) => null).whenComplete(_freeBuffers));
    }
  }

  void _freeBuffers() {
    if (_buffer != nullptr) calloc.free(_buffer);
    if (_out != nullptr) calloc.free(_out);
    if (_info != nullptr) calloc.free(_info);
    if (_text != nullptr) calloc.free(_text);
    _buffer = nullptr;
    _out = nullptr;
    _info = nullptr;
    _text = nullptr;
    _bufferCapacity = 0;
  }
}
