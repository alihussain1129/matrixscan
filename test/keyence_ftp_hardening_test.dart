import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/storage/image_storage_service.dart';
import 'package:exalted/features/devices/keyence/keyence_ftp_receiver.dart';

/// Minimal line-based FTP control client for tests.
class _FtpClient {
  _FtpClient(this.socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: (Object _) {});
  }

  final Socket socket;
  final List<String> _buffered = [];
  final List<Completer<String>> _waiters = [];

  static Future<_FtpClient> connect(int port) async =>
      _FtpClient(await Socket.connect(InternetAddress.loopbackIPv4, port));

  void _onLine(String line) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(line);
    } else {
      _buffered.add(line);
    }
  }

  Future<String> next() {
    if (_buffered.isNotEmpty) return Future.value(_buffered.removeAt(0));
    final c = Completer<String>();
    _waiters.add(c);
    return c.future.timeout(const Duration(seconds: 4));
  }

  Future<String> send(String command) {
    socket.write('$command\r\n');
    return next();
  }
}

Future<Socket> _openPassive(_FtpClient c) async {
  final reply = await c.send('PASV');
  expect(reply, startsWith('227'));
  final m = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)')
      .firstMatch(reply)!;
  final port = (int.parse(m.group(5)!) << 8) | int.parse(m.group(6)!);
  return Socket.connect(
    '${m.group(1)}.${m.group(2)}.${m.group(3)}.${m.group(4)}',
    port,
  );
}

Future<void> _sendAndClose(Socket data, List<int> bytes) async {
  try {
    data.add(bytes);
    await data.flush();
    await data.close();
  } catch (_) {}
}

void main() {
  late Directory tempDir;
  KeyenceFtpReceiver? receiver;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ftp_hardening_');
  });

  tearDown(() async {
    await receiver?.stop();
    receiver = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<_FtpClient> startAndConnect({
    String? username,
    String? password,
    int? maxUploadBytes,
  }) async {
    receiver = KeyenceFtpReceiver(
      port: 0,
      imageStorage: ImageStorageService(directoryProvider: () async => tempDir),
      username: username ?? 'tester',
      password: password ?? 'secret',
      maxUploadBytes: maxUploadBytes ?? 20 * 1024 * 1024,
    );
    await receiver!.start();
    final c = await _FtpClient.connect(receiver!.boundPort);
    expect(await c.next(), startsWith('220'));
    return c;
  }

  Future<void> anonymousLogin(_FtpClient c) async {
    expect(await c.send('USER tester'), startsWith('331'));
    expect(await c.send('PASS secret'), startsWith('230'));
    expect(await c.send('TYPE I'), startsWith('200'));
  }

  List<FileSystemEntity> storedFiles() {
    final dir = Directory('${tempDir.path}/exalted_media');
    return dir.existsSync() ? dir.listSync() : <FileSystemEntity>[];
  }

  test('rejects wrong password and blocks commands until login', () async {
    final c = await startAndConnect(username: 'line', password: 'secret');
    expect(await c.send('USER line'), startsWith('331'));
    expect(await c.send('PASS wrong'), startsWith('530'));
    expect(await c.send('PASV'), startsWith('530'));
    expect(await c.send('USER line'), startsWith('331'));
    expect(await c.send('PASS secret'), startsWith('230'));
    expect(await c.send('PASV'), startsWith('227'));
    c.socket.destroy();
  });

  test('rejects a file name with a disallowed extension', () async {
    final c = await startAndConnect();
    await anonymousLogin(c);
    final data = await _openPassive(c);
    expect(await c.send('STOR evil.exe'), startsWith('553'));
    data.destroy();
    c.socket.destroy();
    expect(storedFiles(), isEmpty);
  });

  test('rejects an upload larger than the limit', () async {
    final c = await startAndConnect(maxUploadBytes: 8);
    await anonymousLogin(c);
    final data = await _openPassive(c);
    expect(await c.send('STOR big.jpg'), startsWith('150'));
    await _sendAndClose(data, Uint8List(100));
    expect(await c.next(), startsWith('552'));
    c.socket.destroy();
    expect(storedFiles(), isEmpty);
  });

  test(
    'stores a traversal-style name inside the media directory only',
    () async {
      final c = await startAndConnect();
      await anonymousLogin(c);
      final data = await _openPassive(c);
      expect(await c.send('STOR ../../x.jpg'), startsWith('150'));
      await _sendAndClose(data, [0xFF, 0xD8, 0xFF, 0xD9]);
      expect(await c.next(), startsWith('226'));
      c.socket.destroy();

      final files = storedFiles();
      expect(files, hasLength(1));
      expect(files.single.path, startsWith('${tempDir.path}/exalted_media/'));
      expect(files.single.path.split('/').last, startsWith('keyence_cmos_'));
    },
  );

  test('closes the connection on an over-long command line', () async {
    final c = await startAndConnect();
    c.socket.write('A' * 5000);
    expect(await c.next(), startsWith('500'));
    c.socket.destroy();
  });
}
