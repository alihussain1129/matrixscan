import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';
import 'package:exalted/features/devices/keyence/sr751_message_classifier.dart';

import 'support/keyence_sr751_simulator.dart';

Future<void> _until(
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
  group('KEYENCE SR-751 Protocol & Simulator Tests', () {
    late KeyenceSr751Simulator simulator;
    late KeyenceSr751Client client;

    setUp(() async {
      simulator = await KeyenceSr751Simulator.start();
      client = KeyenceSr751Client(
        defaultHost: simulator.address.address,
        defaultPort: simulator.port,
        reconnectBaseDelay: const Duration(milliseconds: 50),
        reconnectMaxDelay: const Duration(milliseconds: 200),
      );
    });

    tearDown(() async {
      await client.disconnect();
      client.dispose();
      await simulator.close();
    });

    test('fast-path connectAndVerify completes handshake and measures timings (< 3-4s)', () async {
      final sw = Stopwatch()..start();
      final handshake = await client.connectAndVerify(
        targetHost: simulator.address.address,
        targetPort: simulator.port,
        timeout: const Duration(seconds: 3),
      );
      final elapsedMs = sw.elapsedMilliseconds;

      expect(handshake.success, isTrue);
      expect(handshake.model, equals('SR-751'));
      expect(handshake.firmwareVersion, equals('V2.30'));
      expect(handshake.serialNumber, equals('12345678'));
      expect(client.status, equals(KeyenceConnectionStatus.connected));

      // Fast connection requirement: under 3-4 seconds (local simulation takes < 150 ms)
      expect(elapsedMs, lessThan(3500));
      expect(client.lastConnectTimeMs, greaterThanOrEqualTo(0));
      expect(client.lastHandshakeTimeMs, greaterThanOrEqualTo(0));
      expect(client.lastTotalConnectionTimeMs, greaterThanOrEqualTo(0));
    });

    test('handshake queryDeviceInfo accurately parses comma-separated firmware & serial', () async {
      simulator.model = 'SR-750';
      simulator.firmware = 'V1.40';
      simulator.serial = 'SN998877';

      await client.connect(
        targetHost: simulator.address.address,
        targetPort: simulator.port,
      );

      final info = await client.queryDeviceInfo();
      expect(info.success, isTrue);
      expect(info.model, equals('SR-750'));
      expect(info.firmwareVersion, equals('V1.40'));
      expect(info.serialNumber, equals('SN998877'));
    });

    test('rejects non-Keyence TCP server that does not respond with Keyence signature', () async {
      // Create a dummy TCP server that responds with generic HTTP or text
      final dummyServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      dummyServer.listen((socket) {
        socket.listen((data) {
          socket.write('GENERIC_TCP_SERVER_OK\r');
        });
      });
      addTearDown(dummyServer.close);

      final handshake = await client.connectAndVerify(
        targetHost: dummyServer.address.address,
        targetPort: dummyServer.port,
        timeout: const Duration(seconds: 1),
      );

      expect(handshake.success, isFalse);
      expect(handshake.errorMessage, contains('Unexpected device signature'));
      expect(client.status, equals(KeyenceConnectionStatus.error));
    });

    test(
      'reconnect backoff recovers after simulator drops connection',
      () async {
        await client.connect(
          targetHost: simulator.address.address,
          targetPort: simulator.port,
        );
        expect(client.status, equals(KeyenceConnectionStatus.connected));

        // Drop client connection on the simulator side
        simulator.disconnectClients();

        // Client should detect socket loss
        await _until(() => client.status != KeyenceConnectionStatus.connected);

        // Automatic reconnection should restore communication
        await _until(
          () => client.status == KeyenceConnectionStatus.connected,
          timeout: const Duration(seconds: 4),
        );
        expect(client.status, equals(KeyenceConnectionStatus.connected));
      },
    );

    test(
      'handles partial TCP packets and reassembles fragmented barcode messages',
      () async {
        await client.connect(
          targetHost: simulator.address.address,
          targetPort: simulator.port,
        );

        final scanCompleter = Completer<KeyenceScanResult>();
        final sub = client.scanStream.listen((scan) {
          if (!scanCompleter.isCompleted) scanCompleter.complete(scan);
        });
        addTearDown(sub.cancel);

        // Simulate split transmission: first part without delimiter, second part with delimiter
        simulator.sendRaw('PARTIAL-PAY');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        simulator.sendRaw('LOAD-DATA\r');

        final result = await scanCompleter.future.timeout(
          const Duration(seconds: 2),
        );
        expect(result.data, equals('PARTIAL-PAYLOAD-DATA'));
        expect(result.isError, isFalse);
      },
    );

    test(
      'handles multiple barcode messages packed into a single TCP write',
      () async {
        await client.connect(
          targetHost: simulator.address.address,
          targetPort: simulator.port,
        );

        final received = <String>[];
        final sub = client.scanStream.listen((scan) {
          received.add(scan.data);
        });
        addTearDown(sub.cancel);

        // Batch two barcode reads into one TCP write
        simulator.sendBatchedBarcodes(['DM_CODE_BATCH_1', 'DM_CODE_BATCH_2']);

        await _until(() => received.length == 2);
        expect(received, equals(['DM_CODE_BATCH_1', 'DM_CODE_BATCH_2']));
      },
    );

    test(
      'production message classifier separates OK, STAT, and barcodes',
      () async {
        final classifier = Sr751MessageClassifier(
          profile: const Sr751ReplyProfile.production(),
        );

        // 1. Barcode reading
        final barcodeClass = classifier.classify('4006381333931');
        expect(barcodeClass.kind, equals(Sr751MessageKind.barcode));
        expect(barcodeClass.payload, equals('4006381333931'));

        // 2. Command acknowledgement (OK)
        classifier.noteCommandSent('LOFF');
        final okClass = classifier.classify('OK');
        expect(okClass.kind, equals(Sr751MessageKind.commandResponse));
        expect(okClass.command, equals('LOFF'));

        // 3. STAT reply
        final statClass = classifier.classify('00');
        // 00 is in acknowledgements
        expect(statClass.kind, isNot(equals(Sr751MessageKind.barcode)));

        // 4. Reader Error
        final errClass = classifier.classify('ERROR,01');
        expect(errClass.kind, equals(Sr751MessageKind.readFailure));

        // 5. Read NG
        final ngClass = classifier.classify('NG');
        expect(ngClass.kind, equals(Sr751MessageKind.readFailure));
      },
    );
  });
}
