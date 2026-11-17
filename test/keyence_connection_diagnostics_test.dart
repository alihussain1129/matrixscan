import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';

import 'support/keyence_sr751_simulator.dart';

void main() {
  group('describeKeyenceConnectionError', () {
    test('names TCP/Ethernet, never a COM port', () {
      final msg = describeKeyenceConnectionError(
        const SocketException('x', osError: OSError('No route to host', 113)),
        '192.168.100.100',
        9004,
      );
      expect(msg, contains('No route to 192.168.100.100'));
      expect(msg.toUpperCase(), isNot(contains('COM')));
    });

    test('refused connection points at the port', () {
      final msg = describeKeyenceConnectionError(
        const SocketException('x', osError: OSError('refused', 111)),
        '10.0.0.5',
        9004,
      );
      expect(msg, contains('refused'));
      expect(msg, contains('port 9004'));
    });

    test('Windows error numbers are understood', () {
      final msg = describeKeyenceConnectionError(
        const SocketException('x', osError: OSError('timeout', 10060)),
        '10.0.0.5',
        9004,
      );
      expect(msg, contains('timed out'));
    });

    test('connect timeout is described', () {
      final msg = describeKeyenceConnectionError(
        TimeoutException('t'),
        '10.0.0.5',
        9004,
      );
      expect(msg, contains('timed out'));
      expect(msg, contains('Ethernet cable'));
    });
  });

  group('connection state', () {
    late KeyenceSr751Client client;

    setUp(() {
      client = KeyenceSr751Client()..autoReconnect = false;
    });

    tearDown(() async {
      await client.disconnect();
      client.dispose();
    });

    test('closed port reports error with a refused message', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();

      final result = await client.connectAndVerify(
        targetHost: '127.0.0.1',
        targetPort: port,
        timeout: const Duration(seconds: 1),
      );

      expect(result.success, isFalse);
      expect(client.status, KeyenceConnectionStatus.error);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage!.toUpperCase(), isNot(contains('COM ')));
    });

    test('status is never "connected" before the reader answers', () async {
      // Accepts the TCP connection but never replies.
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      silent.listen((socket) => socket.listen((_) {}));
      addTearDown(silent.close);

      final seen = <KeyenceConnectionStatus>[];
      final sub = client.statusStream.listen(seen.add);
      addTearDown(sub.cancel);

      final result = await client.connectAndVerify(
        targetHost: '127.0.0.1',
        targetPort: silent.port,
        timeout: const Duration(seconds: 1),
        handshakeTimeout: const Duration(milliseconds: 120),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('no reply'));
      expect(seen, isNot(contains(KeyenceConnectionStatus.connected)));
      expect(client.status, KeyenceConnectionStatus.error);
    });

    test('wrong server on the port is rejected and never "connected"',
        () async {
      final other = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      other.listen((socket) {
        socket.listen((_) => socket.write('HTTP/1.1 400 Bad Request\r'));
      });
      addTearDown(other.close);

      final seen = <KeyenceConnectionStatus>[];
      final sub = client.statusStream.listen(seen.add);
      addTearDown(sub.cancel);

      final result = await client.connectAndVerify(
        targetHost: '127.0.0.1',
        targetPort: other.port,
        timeout: const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Unexpected device signature'));
      expect(seen, isNot(contains(KeyenceConnectionStatus.connected)));
    });

    test('becomes connected only after a good handshake', () async {
      final sim = await KeyenceSr751Simulator.start();
      addTearDown(sim.close);

      final seen = <KeyenceConnectionStatus>[];
      final sub = client.statusStream.listen(seen.add);
      addTearDown(sub.cancel);

      final result = await client.connectAndVerify(
        targetHost: sim.address.address,
        targetPort: sim.port,
        timeout: const Duration(seconds: 2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result.success, isTrue);
      expect(client.status, KeyenceConnectionStatus.connected);
      expect(
        seen,
        containsAllInOrder([
          KeyenceConnectionStatus.connecting,
          KeyenceConnectionStatus.connected,
        ]),
      );
    });

    test('re-verifies the reader after an established socket drops', () async {
      final sim = await KeyenceSr751Simulator.start();
      addTearDown(sim.close);
      final reconnecting = KeyenceSr751Client(
        reconnectBaseDelay: const Duration(milliseconds: 20),
        reconnectMaxDelay: const Duration(milliseconds: 40),
      );
      addTearDown(reconnecting.dispose);

      final first = await reconnecting.connectAndVerify(
        targetHost: sim.address.address,
        targetPort: sim.port,
        timeout: const Duration(seconds: 1),
      );
      expect(first.success, isTrue);
      expect(sim.receivedCommands.where((c) => c == 'KEYENCE').length, 1);

      sim.disconnectClients();
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline) &&
          (sim.receivedCommands.where((c) => c == 'KEYENCE').length < 2 ||
              reconnecting.status != KeyenceConnectionStatus.connected)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(sim.receivedCommands.where((c) => c == 'KEYENCE').length, 2);
      expect(reconnecting.status, KeyenceConnectionStatus.connected);
      expect(reconnecting.detectedModel, 'SR-751');
    });

    test('an error reply is not a successful handshake', () async {
      final erroring = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      erroring.listen((socket) {
        socket.listen((_) => socket.write('ER,KEYENCE,00\r'));
      });
      addTearDown(erroring.close);

      final result = await client.connectAndVerify(
        targetHost: '127.0.0.1',
        targetPort: erroring.port,
        timeout: const Duration(seconds: 1),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('error reply'));
      expect(client.status, isNot(KeyenceConnectionStatus.connected));
    });
  });
}
