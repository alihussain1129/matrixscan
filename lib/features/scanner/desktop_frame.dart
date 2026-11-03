import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

/// Converts a BGRA camera frame (desktop cameras) into an 8-bit gray image
/// with no row padding, which is what the native decoder expects.
Uint8List bgraToGray(Uint8List bgra, int width, int height, int rowStride) {
  final gray = Uint8List(width * height);
  var o = 0;
  for (var y = 0; y < height; y++) {
    var i = y * rowStride;
    for (var x = 0; x < width; x++, i += 4, o++) {
      // Integer weights that add up to 256. Bytes are B, G, R, A.
      gray[o] = (bgra[i] * 29 + bgra[i + 1] * 150 + bgra[i + 2] * 77) >> 8;
    }
  }
  return gray;
}

/// Runs [bgraToGray] on a background isolate so the UI isolate stays free.
///
/// One frame is converted at a time. While the worker is busy, new frames are
/// skipped, which is what a live scanner wants.
class GrayConverter {
  Isolate? _isolate;
  SendPort? _worker;
  ReceivePort? _replies;
  bool _starting = false;
  bool _busy = false;

  /// Called on the UI isolate with the gray image and its size.
  void Function(Uint8List gray, int width, int height)? onGray;

  /// Returns true when the frame was accepted for conversion.
  bool submit(Uint8List bgra, int width, int height, int rowStride) {
    final worker = _worker;
    if (worker == null) {
      unawaited(_start());
      return false;
    }
    if (_busy) return false;
    _busy = true;
    try {
      // fromList copies the bytes now, so the camera may reuse its buffer.
      worker.send(<Object>[
        TransferableTypedData.fromList(<TypedData>[bgra]),
        width,
        height,
        rowStride,
      ]);
      return true;
    } catch (_) {
      _busy = false;
      return false;
    }
  }

  Future<void> _start() async {
    if (_starting || _worker != null) return;
    _starting = true;
    try {
      final replies = ReceivePort();
      _replies = replies;
      replies.listen(_onReply);
      _isolate = await Isolate.spawn(_workerMain, replies.sendPort);
    } catch (_) {
      _starting = false;
    }
  }

  void _onReply(Object? message) {
    if (message is SendPort) {
      _worker = message;
      _starting = false;
      return;
    }
    if (message is List && message.length == 3) {
      _busy = false;
      final gray = (message[0] as TransferableTypedData)
          .materialize()
          .asUint8List();
      onGray?.call(gray, message[1] as int, message[2] as int);
    }
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _replies?.close();
    _replies = null;
    _worker = null;
    _starting = false;
    _busy = false;
    onGray = null;
  }
}

void _workerMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  commands.listen((Object? message) {
    if (message is! List) return;
    final bgra = (message[0] as TransferableTypedData)
        .materialize()
        .asUint8List();
    final width = message[1] as int;
    final height = message[2] as int;
    final stride = message[3] as int;
    final gray = bgraToGray(bgra, width, height, stride);
    replies.send(<Object>[
      TransferableTypedData.fromList(<TypedData>[gray]),
      width,
      height,
    ]);
  });
}
