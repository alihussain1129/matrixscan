import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';

Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Condition not met within 3 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> pause([int ms = 50]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late ServerSocket server;
  final accepted = <Socket>[];
  KeyenceSr751Client? client;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    accepted.clear();
  });

  tearDown(() async {
    await client?.disconnect();
    client?.dispose();
    client = null;
    for (final s in accepted) {
      s.destroy();
    }
    await server.close();
  });

  KeyenceSr751Client makeClient() => client = KeyenceSr751Client(
    defaultHost: '127.0.0.1',
    defaultPort: server.port,
    reconnectBaseDelay: const Duration(milliseconds: 50),
    reconnectMaxDelay: const Duration(milliseconds: 200),
  );

  Future<Socket> connectAndAccept(KeyenceSr751Client c) async {
    expect(await c.connect(), isTrue);
    await until(() => accepted.isNotEmpty);
    return accepted.first;
  }

  test('reassembles a message split across chunks', () async {
    server.listen(accepted.add);
    final c = makeClient();
    final results = <String>[];
    c.scanStream.listen((r) => results.add(r.data));
    final s = await connectAndAccept(c);

    s.add(utf8.encode('ABC'));
    await s.flush();
    await pause();
    s.add(utf8.encode('DEF\rGH'));
    await s.flush();
    await pause();
    s.add(utf8.encode('I\r'));
    await s.flush();

    await until(() => results.length == 2);
    expect(results, ['ABCDEF', 'GHI']);
  });

  test('keeps a multi-byte character split across chunks intact', () async {
    server.listen(accepted.add);
    final c = makeClient();
    final results = <String>[];
    c.scanStream.listen((r) => results.add(r.data));
    final s = await connectAndAccept(c);

    s.add([0x61, 0xC3]);
    await s.flush();
    await pause();
    s.add([0xA9, 0x0D]);
    await s.flush();

    await until(() => results.isNotEmpty);
    expect(results, ['a\u00e9']);
  });

  test('accepts CRLF and LF line endings by default', () async {
    server.listen(accepted.add);
    final c = makeClient();
    final results = <String>[];
    c.scanStream.listen((r) => results.add(r.data));
    final s = await connectAndAccept(c);

    s.add(utf8.encode('A\r\nB\nC\r'));
    await s.flush();

    await until(() => results.length == 3);
    expect(results, ['A', 'B', 'C']);
  });

  test(
    'reconnects exactly once after the reader drops the connection',
    () async {
      server.listen((s) {
        accepted.add(s);
        if (accepted.length == 1) s.destroy();
      });
      final c = makeClient();
      expect(await c.connect(), isTrue);

      await until(() => accepted.length >= 2);
      await pause(400);

      expect(accepted.length, 2);
      expect(c.status, KeyenceConnectionStatus.connected);
      expect(c.reconnectAttempts, 0);
    },
  );

  test(
    'keeps retrying beyond ten attempts while the reader is unreachable',
    () async {
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = tmp.port;
      await tmp.close();

      final c = client = KeyenceSr751Client(
        defaultHost: '127.0.0.1',
        defaultPort: closedPort,
        reconnectBaseDelay: const Duration(milliseconds: 1),
        reconnectMaxDelay: const Duration(milliseconds: 5),
      );
      expect(await c.connect(), isFalse);
      await until(
        () => c.reconnectAttempts > 10,
        timeout: const Duration(seconds: 5),
      );
      await c.disconnect();
      final attempts = c.reconnectAttempts;
      await pause(100);
      expect(c.reconnectAttempts, attempts);
    },
  );

  test(
    'barcode arriving during identity query does not consume the handshake',
    () async {
      server.listen((socket) {
        accepted.add(socket);
        socket.listen((bytes) {
          final command = utf8.decode(bytes, allowMalformed: true);
          if (command == 'KEYENCE\r') {
            socket.add(
              utf8.encode('INTERLEAVED-BARCODE\rOK, KEYENCE, SR-751, V2.30\r'),
            );
          }
        });
      });
      final c = makeClient();
      final scans = <String>[];
      c.scanStream.listen((scan) => scans.add(scan.data));

      final result = await c.connectAndVerify(
        timeout: const Duration(seconds: 1),
        handshakeTimeout: const Duration(milliseconds: 300),
      );

      expect(result.success, isTrue);
      expect(result.model, 'SR-751');
      await until(() => scans.contains('INTERLEAVED-BARCODE'));
    },
  );

  test('identity reply with extra fields is rejected', () async {
    server.listen((socket) {
      accepted.add(socket);
      socket.listen((bytes) {
        if (utf8.decode(bytes, allowMalformed: true) == 'KEYENCE\r') {
          socket.add(utf8.encode('OK, KEYENCE, SR-751, V2.30, EXTRA\r'));
        }
      });
    });
    final c = makeClient();

    final result = await c.connectAndVerify(
      timeout: const Duration(seconds: 1),
      handshakeTimeout: const Duration(milliseconds: 80),
    );

    expect(result.success, isFalse);
    expect(result.errorMessage, contains('Unexpected device signature'));
  });

  test('dispose while connected does not throw', () async {
    server.listen(accepted.add);
    final c = makeClient();
    await connectAndAccept(c);

    c.dispose();
    c.dispose();
    await pause(200);
    await c.disconnect();
  });
}
