import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/features/devices/keyence/keyence_commissioning_service.dart';
import 'package:exalted/features/devices/keyence/keyence_scanner_coordinator.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/inspection/combined_inspector.dart';
import 'package:exalted/features/inspection/inspection_log.dart';
import 'package:exalted/features/scanner/scanner_controller.dart';
import 'package:exalted/ffi/decode_result.dart';

import 'support/keyence_sr751_simulator.dart';

Future<void> _until(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KEYENCE Coordinator & Exalted Core Integration Tests', () {
    late Directory tempDir;
    late HistoryRepository historyRepo;
    late InspectionLog inspectionLog;
    late KeyenceSr751Simulator simulator;
    late ProviderContainer container;

    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );

      tempDir = Directory.systemTemp.createTempSync('exalted_history_test');
      historyRepo = HistoryRepository(directory: () async => tempDir);
      inspectionLog = InspectionLog(directory: () async => tempDir);

      SharedPreferences.setMockInitialValues({});
      simulator = await KeyenceSr751Simulator.start(
        model: 'SR-751',
        firmware: 'V2.30',
        serial: 'SN-PROD-9988',
        defaultBarcode: '4006381333931',
      );

      container = ProviderContainer(
        overrides: [
          historyRepositoryProvider.overrideWithValue(historyRepo),
          inspectionLogProvider.overrideWithValue(inspectionLog),
          keyenceSr751ClientProvider.overrideWith((ref) {
            final client = KeyenceSr751Client(
              defaultHost: simulator.address.address,
              defaultPort: simulator.port,
              reconnectBaseDelay: const Duration(milliseconds: 40),
              reconnectMaxDelay: const Duration(milliseconds: 150),
            );
            ref.onDispose(client.dispose);
            return client;
          }),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await simulator.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'connects and handshakes in < 3-4s, updating coordinator state',
      () async {
        final coordinator = container.read(
          keyenceScannerCoordinatorProvider.notifier,
        );

        final connected = await coordinator.connect(
          targetHost: simulator.address.address,
          targetPort: simulator.port,
          timeout: const Duration(seconds: 3),
        );

        expect(connected, isTrue);
        final state = container.read(keyenceScannerCoordinatorProvider);
        expect(state.isConnected, isTrue);
        expect(state.status, equals(KeyenceConnectionStatus.connected));
        expect(state.model, equals('SR-751'));
        expect(state.firmware, equals('V2.30'));
        expect(state.serialNumber, equals('SN-PROD-9988'));
        expect(state.totalConnectionTimeMs, greaterThanOrEqualTo(0));
        expect(
          state.totalConnectionTimeMs,
          lessThan(3500),
        ); // Well under 3-4s target
      },
    );

    test(
      'hardware trigger commands execute reliably against simulator',
      () async {
        final coordinator = container.read(
          keyenceScannerCoordinatorProvider.notifier,
        );
        await coordinator.connect(
          targetHost: simulator.address.address,
          targetPort: simulator.port,
        );

        // LON
        final lonSent = await coordinator.triggerRead();
        expect(lonSent, isTrue);

        // LOFF
        final loffSent = await coordinator.stopRead();
        expect(loffSent, isTrue);

        // T1
        final t1Sent = await coordinator.triggerT1();
        expect(t1Sent, isTrue);

        // BEEP
        final beepSent = await coordinator.beep();
        expect(beepSent, isTrue);

        // Wait until simulator receives BEEP (last sent command)
        await _until(() => simulator.receivedCommands.contains('BEEP'));

        // Verify simulator received all commands
        expect(simulator.receivedCommands, contains('LON'));
        expect(simulator.receivedCommands, contains('LOFF'));
        expect(simulator.receivedCommands, contains('T1'));
        expect(simulator.receivedCommands, contains('BEEP'));
      },
    );

    test('incoming scanner barcode seamlessly feeds into ScannerController and Exalted Core', () async {
      final coordinator = container.read(
        keyenceScannerCoordinatorProvider.notifier,
      );
      await coordinator.connect(
        targetHost: simulator.address.address,
        targetPort: simulator.port,
      );

      // Trigger read from scanner simulator
      simulator.sendBarcode(']d2EXALTED-DPM-778899');

      // 1. Check coordinator state updated
      await _until(
        () => container.read(keyenceScannerCoordinatorProvider).scanCount == 1,
      );
      final coordState = container.read(keyenceScannerCoordinatorProvider);
      expect(coordState.lastScan, equals(']d2EXALTED-DPM-778899'));

      // 2. Check ScannerController state updated with DecodedBarcode
      final scannerState = container.read(scannerControllerProvider);
      expect(scannerState.result, isNotNull);
      expect(scannerState.result!.text, equals(']d2EXALTED-DPM-778899'));
      expect(scannerState.result!.kind, equals(BarcodeKind.dataMatrix));

      // 3. Check HistoryRepository received the scan
      await _until(
        () => container
            .read(historyRepositoryProvider)
            .loadAll()
            .then((list) => list.any((h) => h.text == ']d2EXALTED-DPM-778899'))
            .catchError((_) => false),
      );
      final history = container.read(historyRepositoryProvider);
      final historyEntries = await history.loadAll();
      expect(
        historyEntries.any((h) => h.text == ']d2EXALTED-DPM-778899'),
        isTrue,
      );

      // 4. Check CombinedInspector recorded the event
      await _until(() => container.read(combinedInspectorProvider).count > 0);
      final inspectorState = container.read(combinedInspectorProvider);
      expect(inspectorState.count, greaterThan(0));
      expect(inspectorState.latest?.raw, equals(']d2EXALTED-DPM-778899'));
    });

    test('runs automated commissioning readiness check and produces structured report', () async {
      final service = const KeyenceCommissioningService();
      final report = await service.runReadinessAssessment(
        host: simulator.address.address,
        port: simulator.port,
        timeout: const Duration(seconds: 2),
      );

      expect(report.overallReady, isTrue);
      expect(report.detectedModel, equals('SR-751'));
      expect(report.detectedFirmware, equals('V2.30'));
      expect(report.detectedSerial, equals('SN-PROD-9988'));
      expect(report.steps.length, greaterThanOrEqualTo(5));
      expect(
        report.steps.any(
          (s) => s.name == 'TCP Socket Availability' && s.passed,
        ),
        isTrue,
      );
      expect(
        report.steps.any(
          (s) => s.name == 'Command Channel Handshake' && s.passed,
        ),
        isTrue,
      );
    });

    test(
      'profile persistence restores settings and auto-connect on restart',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'exalted_keyence_last_host',
          simulator.address.address,
        );
        await prefs.setInt('exalted_keyence_last_port', simulator.port);
        await prefs.setString('exalted_keyence_last_model', 'SR-751');
        await prefs.setBool('exalted_keyence_auto_connect', true);

        final freshTempDir = Directory.systemTemp.createTempSync(
          'exalted_history_fresh',
        );
        final freshHistoryRepo = HistoryRepository(
          directory: () async => freshTempDir,
        );
        final freshInspectionLog = InspectionLog(
          directory: () async => freshTempDir,
        );

        // Spin up fresh container to simulate app launch
        final newContainer = ProviderContainer(
          overrides: [
            historyRepositoryProvider.overrideWithValue(freshHistoryRepo),
            inspectionLogProvider.overrideWithValue(freshInspectionLog),
            configProvider.overrideWithValue(
              AppConfig(
                scanner: ScannerConfig(
                  host: simulator.address.address,
                  port: simulator.port,
                  deviceLabel: 'SR-751',
                  autoConnect: true,
                  hostSaved: true,
                ),
              ),
            ),
            keyenceSr751ClientProvider.overrideWith((ref) {
              final client = KeyenceSr751Client(
                defaultHost: simulator.address.address,
                defaultPort: simulator.port,
              );
              ref.onDispose(client.dispose);
              return client;
            }),
          ],
        );
        addTearDown(() {
          newContainer.dispose();
          if (freshTempDir.existsSync()) {
            freshTempDir.deleteSync(recursive: true);
          }
        });

        // Reading coordinator provider triggers async restore & auto-connect
        newContainer.read(keyenceScannerCoordinatorProvider);

        await _until(
          () =>
              newContainer.read(keyenceScannerCoordinatorProvider).isConnected,
          timeout: const Duration(seconds: 4),
        );

        final restoredState = newContainer.read(
          keyenceScannerCoordinatorProvider,
        );
        expect(restoredState.isConnected, isTrue);
        expect(restoredState.host, equals(simulator.address.address));
        expect(restoredState.port, equals(simulator.port));
        expect(restoredState.model, equals('SR-751'));
      },
    );
  });
}
