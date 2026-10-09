import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'exalted_bindings.dart';

const int _textCapacity = 8192;

/// A background isolate that runs the native decoder, so the UI isolate is
/// never blocked by it.
///
/// The caller owns the luminance buffer in native memory and passes only its
/// address. The caller must not free or overwrite that buffer until [decode]
/// completes, and must make one call at a time.
class DecodeWorker {
  /// Reply status when the worker could not load the native library.
  static const int unavailableStatus = -98;

  Isolate? _isolate;
  SendPort? _commands;
  Future<SendPort?>? _starting;
  bool _closed = false;

  Future<SendPort?> _start() => _starting ??= _spawn();

  Future<SendPort?> _spawn() async {
    final ready = ReceivePort();
    try {
      _isolate = await Isolate.spawn(_workerMain, ready.sendPort);
      final first = await ready.first.timeout(const Duration(seconds: 5));
      final port = first as SendPort;
      if (_closed) {
        port.send(null);
        return null;
      }
      _commands = port;
      debugPrint('[EXALTED][WORKER] decode isolate started');
      return port;
    } catch (_) {
      ready.close();
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _closed = true;
      return null;
    }
  }

  /// Starts the isolate now so the first decode does not pay for the spawn.
  Future<void> warmUp() async {
    if (_closed) return;
    await _start();
  }

  /// Returns `[status, info, text]`, or null when the worker is unusable.
  Future<List<Object?>?> decode({
    required int address,
    required int length,
    required int width,
    required int height,
    required int rowStride,
    required int formatsMask,
    required bool tryHarder,
    int flags = 0,
  }) async {
    if (_closed) return null;
    final commands = await _start();
    if (commands == null || _closed) return null;

    final reply = ReceivePort();
    commands.send(<Object?>[
      reply.sendPort,
      address,
      length,
      width,
      height,
      rowStride,
      formatsMask,
      (tryHarder ? 1 : 0) | flags | 512, // 512: low-priority decode thread
    ]);
    try {
      final result = await reply.first.timeout(const Duration(seconds: 5));
      return (result as List).cast<Object?>();
    } on TimeoutException {
      _closed = true;
      commands.send(null);
      return null;
    } finally {
      reply.close();
    }
  }

  /// Asks the worker to finish its current decode and exit.
  void dispose() {
    _closed = true;
    _commands?.send(null);
    _commands = null;
  }
}

void _workerMain(SendPort mainPort) {
  final commands = ReceivePort();
  mainPort.send(commands.sendPort);

  ExaltedBindings? bindings;
  try {
    bindings = ExaltedBindings.open();
  } catch (_) {
    bindings = null;
  }

  final info = calloc<Int32>(ExaltedBindings.decodeInfoLen);
  final text = calloc<Uint8>(_textCapacity);

  commands.listen((Object? message) {
    if (message is! List) {
      calloc.free(info);
      calloc.free(text);
      commands.close();
      return;
    }
    final reply = message[0] as SendPort;
    final native = bindings;
    if (native == null) {
      reply.send(<Object?>[DecodeWorker.unavailableStatus, null, null]);
      return;
    }
    final status = native.decode(
      Pointer<Uint8>.fromAddress(message[1] as int),
      message[2] as int,
      message[3] as int,
      message[4] as int,
      message[5] as int,
      message[6] as int,
      message[7] as int,
      info,
      ExaltedBindings.decodeInfoLen,
      text,
      _textCapacity,
    );
    if (status != 1) {
      reply.send(<Object?>[status, null, null]);
      return;
    }
    final values = info.asTypedList(ExaltedBindings.decodeInfoLen).toList();
    final size = math.min(math.max(values[1], 0), _textCapacity);
    final decoded = utf8.decode(text.asTypedList(size), allowMalformed: true);
    reply.send(<Object?>[status, values, decoded]);
  });
}
