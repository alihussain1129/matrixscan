import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/devices/keyence/keyence_scanner_discovery_service.dart';

import 'support/keyence_sr751_simulator.dart';

void main() {
  group('KeyenceScannerDiscoveryService Tests', () {
    late KeyenceSr751Simulator simulator;
    late KeyenceScannerDiscoveryService discoveryService;

    setUp(() async {
      simulator = await KeyenceSr751Simulator.start(
        model: 'SR-751',
        firmware: 'V2.30',
        serial: 'SN-001122',
      );
      discoveryService = KeyenceScannerDiscoveryService(
        defaultPort: simulator.port,
        initialCandidateHosts: ['127.0.0.1'],
      );
    });

    tearDown(() async {
      await discoveryService.dispose();
      await simulator.close();
    });

    test(
      'discovers active simulated SR-751 reader and verifies handshake',
      () async {
        final events = <ScannerDiscoveryEvent>[];
        final sub = discoveryService.eventsStream.listen(events.add);
        addTearDown(sub.cancel);

        final results = await discoveryService.scanForScanners(
          includeSubnetSweep: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(results, isNotEmpty);
        final found = results.firstWhere(
          (s) => s.identity.port == simulator.port,
        );
        expect(found.identity.manufacturer, equals('KEYENCE'));
        expect(found.identity.model, equals('SR-751'));
        expect(found.identity.firmwareVersion, equals('V2.30'));
        expect(found.identity.serialNumber, equals('SN-001122'));
        expect(found.identity.ipAddress, equals('127.0.0.1'));
        expect(found.responseTimeMs, greaterThanOrEqualTo(0));

        // Check discovery progress events
        expect(events.any((e) => e.phase == 'interfaces'), isTrue);
        expect(events.any((e) => e.phase == 'candidates'), isTrue);
        expect(events.any((e) => e.phase == 'found'), isTrue);
        expect(events.any((e) => e.phase == 'complete'), isTrue);
      },
    );

    test(
      'discovers multiple SR-751/SR-752 scanners and distinguishes them',
      () async {
        final simulator2 = await KeyenceSr751Simulator.start(
          model: 'SR-752',
          firmware: 'V2.35',
          serial: 'SN-003344',
        );
        addTearDown(simulator2.close);

        discoveryService.addCandidateHost('127.0.0.1');

        // Probe both ports
        final r1 = await discoveryService.verifyEndpoint(
          '127.0.0.1',
          simulator.port,
        );
        final r2 = await discoveryService.verifyEndpoint(
          '127.0.0.1',
          simulator2.port,
        );

        expect(r1, isNotNull);
        expect(r2, isNotNull);
        expect(r1!.identity.model, equals('SR-751'));
        expect(r2!.identity.model, equals('SR-752'));
        expect(r1.identity.id, isNot(equals(r2.identity.id)));
      },
    );

    test('deduplicates devices when discovered via multiple routes', () async {
      // Add duplicate candidate endpoints
      discoveryService.addCandidateHost('127.0.0.1');
      discoveryService.addCandidateHost('127.0.0.1');

      final results = await discoveryService.scanForScanners(
        includeSubnetSweep: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final simulatorMatches = results
          .where((s) => s.identity.port == simulator.port)
          .toList();

      expect(simulatorMatches.length, equals(1));
    });

    test(
      'verifyEndpoint validates manual IP entry in real-time (< 1s)',
      () async {
        final sw = Stopwatch()..start();
        final result = await discoveryService.verifyEndpoint(
          '127.0.0.1',
          simulator.port,
        );
        final elapsedMs = sw.elapsedMilliseconds;

        expect(result, isNotNull);
        expect(result!.identity.model, equals('SR-751'));
        expect(elapsedMs, lessThan(1000));
      },
    );

    test(
      'verifyEndpoint returns null for non-responding or invalid host',
      () async {
        // Connect to an unused port
        final result = await discoveryService.verifyEndpoint(
          '127.0.0.1',
          65432,
        );
        expect(result, isNull);
      },
    );
  });
}
