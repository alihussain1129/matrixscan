import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';

void main() {
  late ServerSocket server;
  late List<int> received;

  setUp(() async {
    received = <int>[];
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) => s.listen(received.addAll, onError: (_) {}));
  });

  tearDown(() async {
    await server.close();
  });

  Future<KeyenceSr751Client> connected(Set<String>? allowed) async {
    final c = KeyenceSr751Client(allowedCommands: allowed);
    c.autoReconnect = false;
    addTearDown(c.dispose);
    final ok = await c.connect(
      targetHost: '127.0.0.1',
      targetPort: server.port,
    );
    expect(ok, isTrue);
    return c;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 250));

  test('empty allow-list sends nothing and records the refusal', () async {
    final c = await connected(<String>{});
    expect(await c.sendCommand('LON'), isFalse);
    await settle();
    expect(received, isEmpty);
    expect(c.blockedCommands, ['LON']);
  });

  test('named helpers are blocked too', () async {
    final c = await connected(<String>{});
    expect(await c.triggerRead(), isFalse);
    expect(await c.resetError(), isFalse);
    await settle();
    expect(received, isEmpty);
  });

  test('an allowed command is sent with a carriage return', () async {
    final c = await connected(<String>{'LON'});
    expect(await c.sendCommand('LON'), isTrue);
    await settle();
    expect(utf8.decode(received), 'LON\r');
  });

  test(
    'matching is by name: arguments and other commands stay blocked',
    () async {
      final c = await connected(<String>{'LON'});
      expect(await c.sendCommand('PRG,3'), isFalse);
      expect(await c.sendCommand('reset'), isFalse);
      await settle();
      expect(received, isEmpty);
      expect(c.blockedCommands, ['PRG', 'RESET']);
    },
  );

  test('no allow-list keeps today\'s behaviour', () async {
    final c = await connected(null);
    expect(await c.sendCommand('LON'), isTrue);
    await settle();
    expect(utf8.decode(received), 'LON\r');
  });
}
