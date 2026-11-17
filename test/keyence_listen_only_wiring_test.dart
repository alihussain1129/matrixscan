import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/devices/keyence/keyence_commissioning_service.dart';
import 'package:exalted/features/devices/keyence/keyence_scanner_coordinator.dart';
import 'package:exalted/features/devices/keyence/keyence_scanner_discovery_service.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';

void main() {
  late ServerSocket server;
  late List<int> received;
  late int connections;

  setUp(() async {
    received = <int>[];
    connections = 0;
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) {
      connections++;
      s.listen(received.addAll, onError: (_) {});
    });
  });

  tearDown(() async {
    await server.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  test('canHandshake follows the allow-list', () {
    bool can(Set<String>? a) {
      final c = KeyenceSr751Client(allowedCommands: a);
      addTearDown(c.dispose);
      return c.canHandshake;
    }

    expect(can(null), isTrue);
    expect(can(<String>{}), isFalse);
    expect(can(<String>{'LON'}), isFalse);
    expect(can(<String>{'KEYENCE'}), isTrue);
  });

  test('the app default allows only documented safe commands', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final client = c.read(keyenceSr751ClientProvider);
    expect(client.allowedCommands, containsAll(['KEYENCE', 'ERRSTAT', 'LON', 'LOFF']));
    expect(client.allowedCommands, isNot(contains('RESET')));
    expect(client.allowedCommands, isNot(contains('DFLT')));
    expect(client.canHandshake, isTrue);
    expect(c.read(keyenceScannerDiscoveryServiceProvider).probeEnabled, isTrue);
  });

  test(
    'listen-only discovery opens TCP but sends no application bytes',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final service = KeyenceScannerDiscoveryService(probeEnabled: false);
      addTearDown(service.dispose);
      expect(service.probeEnabled, isFalse);
      final found = await service.verifyEndpoint('127.0.0.1', server.port);
      await settle();
      expect(found, isNotNull);
      expect(found!.identity.manufacturer, 'Unverified');
      expect(found.identity.model, contains('unverified'));
      expect(connections, 1);
      expect(received, isEmpty);
    },
  );

  test('documented discovery probe sends KEYENCE with CRLF', () async {
    final service = KeyenceScannerDiscoveryService();
    addTearDown(service.dispose);
    try {
      await service.verifyEndpoint('127.0.0.1', server.port);
    } catch (_) {}
    await settle();
    expect(utf8.decode(received), 'KEYENCE\r\n');
  });

  test('commissioning without commands sends nothing', () async {
    await const KeyenceCommissioningService().runReadinessAssessment(
      host: '127.0.0.1',
      port: server.port,
      sendCommands: false,
      allowedCommands: <String>{},
    );
    await settle();
    expect(received, isEmpty);
  });
}
