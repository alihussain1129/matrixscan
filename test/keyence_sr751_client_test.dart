import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';

void main() {
  late ServerSocket mockSr751Server;
  late KeyenceSr751Client client;

  setUp(() async {
    mockSr751Server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    client = KeyenceSr751Client(
      defaultHost: mockSr751Server.address.address,
      defaultPort: mockSr751Server.port,
    );
  });

  tearDown(() async {
    await client.disconnect();
    await mockSr751Server.close();
  });

  test('KeyenceSr751Client connects, sends LON, receives barcode, and parses result', () async {
    final serverReceived = Completer<String>();

    mockSr751Server.listen((socket) {
      socket.listen((data) {
        final cmd = utf8.decode(data);
        if (!serverReceived.isCompleted) {
          serverReceived.complete(cmd);
        }
        if (cmd.startsWith('LON')) {
          // Simulate SR-751 replying with decoded barcode
          socket.write('EXALTED-DM-99420\r');
        }
      });
    });

    final connected = await client.connect(
      targetHost: mockSr751Server.address.address,
      targetPort: mockSr751Server.port,
    );
    expect(connected, isTrue);
    expect(client.status, equals(KeyenceConnectionStatus.connected));

    // Listen for scan event
    final scanEventFuture = client.scanStream.first;

    // Send LON
    final sent = await client.triggerRead();
    expect(sent, isTrue);

    final receivedCmd = await serverReceived.future.timeout(const Duration(seconds: 2));
    expect(receivedCmd, equals('LON\r'));

    final scanResult = await scanEventFuture.timeout(const Duration(seconds: 2));
    expect(scanResult.data, equals('EXALTED-DM-99420'));
    expect(scanResult.isError, isFalse);
  });

  test('KeyenceSr751Client parses ERROR responses accurately', () async {
    mockSr751Server.listen((socket) {
      socket.listen((data) {
        final cmd = utf8.decode(data);
        if (cmd.startsWith('T1')) {
          socket.write('ERROR,71\r');
        }
      });
    });

    await client.connect(
      targetHost: mockSr751Server.address.address,
      targetPort: mockSr751Server.port,
    );

    final scanEventFuture = client.scanStream.first;
    await client.triggerT1();

    final result = await scanEventFuture.timeout(const Duration(seconds: 2));
    expect(result.isError, isTrue);
    expect(result.errorMessage, equals('ERROR,71'));
  });
}
