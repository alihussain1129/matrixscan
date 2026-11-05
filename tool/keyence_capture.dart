// Read-only capture of what a TCP device sends. Connects, sends NOTHING,
// logs timestamped bytes (hex and escaped text), then disconnects.
//
// Usage: dart run tool/keyence_capture.dart --host H --port P
//          [--seconds 60] [--out capture.log]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

String _escape(List<int> bytes) {
  final b = StringBuffer();
  for (final c in bytes) {
    if (c == 0x0D) {
      b.write('\\r');
    } else if (c == 0x0A) {
      b.write('\\n');
    } else if (c >= 0x20 && c < 0x7F) {
      b.writeCharCode(c);
    } else {
      b.write('\\x${c.toRadixString(16).padLeft(2, '0')}');
    }
  }
  return b.toString();
}

String _hex(List<int> bytes) =>
    bytes.map((c) => c.toRadixString(16).padLeft(2, '0')).join(' ');

Future<void> main(List<String> args) async {
  String? host;
  int? port;
  var seconds = 60;
  String? outPath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--host':
        host = args[++i];
      case '--port':
        port = int.tryParse(args[++i]);
      case '--seconds':
        seconds = int.tryParse(args[++i]) ?? seconds;
      case '--out':
        outPath = args[++i];
    }
  }
  if (host == null || port == null) {
    stderr.writeln('Required: --host <address> --port <number>');
    exitCode = 64;
    return;
  }
  final sink = outPath == null
      ? null
      : File(outPath).openWrite(mode: FileMode.append);
  void log(String line) {
    final text = '${DateTime.now().toUtc().toIso8601String()} $line';
    stdout.writeln(text);
    sink?.writeln(text);
  }

  log('connecting to $host:$port (receive only, nothing will be sent)');
  Socket socket;
  try {
    socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
  } catch (e) {
    log('connect failed: $e');
    await sink?.close();
    exitCode = 1;
    return;
  }
  log('connected; listening for $seconds s');
  final done = Completer<void>();
  socket.listen(
    (data) =>
        log('RX ${data.length}B hex[${_hex(data)}] text[${_escape(data)}]'),
    onError: (Object e) {
      log('socket error: $e');
      if (!done.isCompleted) done.complete();
    },
    onDone: () {
      log('closed by remote');
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );
  await Future.any([
    done.future,
    Future<void>.delayed(Duration(seconds: seconds)),
  ]);
  socket.destroy();
  log('finished');
  await sink?.close();
  // Silence unused import warning on some SDKs.
  utf8.encode('');
}
