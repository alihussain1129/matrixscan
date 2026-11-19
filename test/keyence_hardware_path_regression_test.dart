import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';

/// Regression tests for the connection lifecycle defects found while
/// reviewing the real-hardware failure (connect timeout, no ARP entry).
///
/// These use loopback servers and prove software behavior only. They are not
/// evidence that a physical SR-751 communicates.

Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('describeKeyenceLocalSubnetMismatch', () {
    Future<List<LocalIpv4Address>> lister(List<LocalIpv4Address> a) async => a;

    test('explains a PC with no address in the reader /24', () async {
      final msg = await describeKeyenceLocalSubnetMismatch(
        '192.168.100.100',
        listAddresses: () => lister(const [
          LocalIpv4Address('wlp2s0', '192.168.1.20'),
          LocalIpv4Address('enp3s0', '10.0.0.5'),
        ]),
      );
      expect(msg, isNotNull);
      expect(msg, contains('192.168.100.0/24'));
      expect(msg, contains('wlp2s0 192.168.1.20'));
      expect(msg, contains('enp3s0 10.0.0.5'));
      expect(msg, contains('255.255.255.0'));
    });

    test('returns null when a local address shares the /24', () async {
      final msg = await describeKeyenceLocalSubnetMismatch(
        '192.168.100.100',
        listAddresses: () =>
            lister(const [LocalIpv4Address('enp3s0', '192.168.100.10')]),
      );
      expect(msg, isNull);
    });

    test('says so when no IPv4 interface is up', () async {
      final msg = await describeKeyenceLocalSubnetMismatch(
        '192.168.100.100',
        listAddresses: () => lister(const []),
      );
      expect(msg, contains('no active IPv4 interface'));
    });

    test('ignores hostnames and a failing interface listing', () async {
      expect(
        await describeKeyenceLocalSubnetMismatch(
          'scanner.local',
          listAddresses: () => lister(const []),
        ),
        isNull,
      );
      expect(
        await describeKeyenceLocalSubnetMismatch(
          '192.168.100.100',
          listAddresses: () => throw const SocketException('no interfaces'),
        ),
        isNull,
      );
    });
  });

  group('isKeyenceReachabilityFailure', () {
    test('timeouts and unreachable errors count, refusal does not', () {
      expect(isKeyenceReachabilityFailure(TimeoutException('t')), isTrue);
      for (final code in [110, 60, 10060, 113, 65, 10065, 101, 51, 10051]) {
        expect(
          isKeyenceReachabilityFailure(
            SocketException('x', osError: OSError('e', code)),
          ),
          isTrue,
          reason: 'errno $code',
        );
      }
      for (final code in [111, 61, 10061, 104]) {
        expect(
          isKeyenceReachabilityFailure(
            SocketException('x', osError: OSError('e', code)),
          ),
          isFalse,
          reason: 'errno $code',
        );
      }
    });
  });

  group('connect timeout diagnostics', () {
    test('timeout message carries the local-subnet explanation', () async {
      final client = KeyenceSr751Client(
        socketFactory: (host, port, timeout) => Future<Socket>.error(
          const SocketException(
            'Connection timed out',
            osError: OSError('Connection timed out', 110),
          ),
        ),
        localAddressLister: () async => const [
          LocalIpv4Address('wlp2s0', '192.168.1.20'),
        ],
      )..autoReconnect = false;
      addTearDown(() async {
        await client.disconnect();
        client.dispose();
      });

      final result = await client.connectAndVerify(
        timeout: const Duration(milliseconds: 200),
      );

      expect(result.success, isFalse);
      expect(client.status, KeyenceConnectionStatus.error);
      expect(result.errorMessage, contains('timed out'));
      expect(result.errorMessage, contains('192.168.100.0/24'));
      expect(result.errorMessage, contains('wlp2s0 192.168.1.20'));
    });

    test('refusal does not blame the local subnet', () async {
      final client = KeyenceSr751Client(
        socketFactory: (host, port, timeout) => Future<Socket>.error(
          const SocketException(
            'refused',
            osError: OSError('Connection refused', 111),
          ),
        ),
        localAddressLister: () async => const [
          LocalIpv4Address('wlp2s0', '192.168.1.20'),
        ],
      )..autoReconnect = false;
      addTearDown(() async {
        await client.disconnect();
        client.dispose();
      });

      final result = await client.connectAndVerify(
        timeout: const Duration(milliseconds: 200),
      );

      expect(result.errorMessage, contains('refused'));
      expect(result.errorMessage, isNot(contains('no IPv4 address')));
    });
  });

  group('handshake failure lifecycle', () {
    late ServerSocket server;
    final accepted = <Socket>[];
    var respond = false;

    setUp(() async {
      accepted.clear();
      respond = false;
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {
        accepted.add(socket);
        socket.listen((bytes) {
          if (respond &&
              utf8.decode(bytes, allowMalformed: true) == 'KEYENCE\r') {
            socket.add(utf8.encode('OK, KEYENCE, SR-751, V2.30\r'));
          }
        }, onError: (_) {});
      });
    });

    tearDown(() async {
      for (final s in accepted) {
        s.destroy();
      }
      await server.close();
    });

    test('a failed handshake is retried and can recover', () async {
      final client = KeyenceSr751Client(
        reconnectBaseDelay: const Duration(milliseconds: 20),
        reconnectMaxDelay: const Duration(milliseconds: 60),
      );
      addTearDown(() async {
        await client.disconnect();
        client.dispose();
      });

      final seen = <KeyenceConnectionStatus>[];
      final sub = client.statusStream.listen(seen.add);
      addTearDown(sub.cancel);

      // Reader accepts TCP but is not answering yet (for example booting).
      final first = await client.connectAndVerify(
        targetHost: '127.0.0.1',
        targetPort: server.port,
        timeout: const Duration(seconds: 1),
        handshakeTimeout: const Duration(milliseconds: 100),
      );
      expect(first.success, isFalse);
      expect(client.status, KeyenceConnectionStatus.error);
      expect(seen, isNot(contains(KeyenceConnectionStatus.connected)));

      // The reader starts answering. The client must find it again without
      // the user pressing Connect.
      respond = true;
      await until(() => client.status == KeyenceConnectionStatus.connected);

      expect(client.detectedModel, 'SR-751');
      expect(accepted.length, greaterThanOrEqualTo(2));
    });

    test(
      'disconnect during the handshake ends disconnected, not error',
      () async {
        final client = KeyenceSr751Client(
          reconnectBaseDelay: const Duration(milliseconds: 20),
          reconnectMaxDelay: const Duration(milliseconds: 60),
        );
        addTearDown(() async {
          await client.disconnect();
          client.dispose();
        });

        final pending = client.connectAndVerify(
          targetHost: '127.0.0.1',
          targetPort: server.port,
          timeout: const Duration(seconds: 1),
          handshakeTimeout: const Duration(seconds: 2),
        );
        await until(() => accepted.isNotEmpty);
        await client.disconnect();
        final result = await pending;

        expect(result.success, isFalse);
        expect(client.status, KeyenceConnectionStatus.disconnected);

        // A user disconnect must not leave a reconnect running.
        final attempts = accepted.length;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(accepted.length, attempts);
        expect(client.status, KeyenceConnectionStatus.disconnected);
      },
    );
  });
}
