import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/core/config/legacy_settings.dart';
import 'package:exalted/core/config/migrate.dart';
import 'package:exalted/features/devices/keyence/keyence_scanner_coordinator.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';

import 'support/keyence_sr751_simulator.dart';

Future<void> _until(FutureOr<bool> Function() ok) async {
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (!await ok()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KeyenceSr751Simulator sim;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    sim = await KeyenceSr751Simulator.start(
      model: 'SR-751',
      firmware: 'V2.30',
      defaultBarcode: '4006381333931',
    );
  });
  tearDown(() => sim.close());

  ProviderContainer make([AppConfig? cfg]) {
    final c = ProviderContainer(
      overrides: [
        if (cfg != null) configProvider.overrideWithValue(cfg),
        keyenceSr751ClientProvider.overrideWith((ref) {
          final client = KeyenceSr751Client(
            defaultHost: sim.address.address,
            defaultPort: sim.port,
          );
          ref.onDispose(client.dispose);
          return client;
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('a successful connect saves the endpoint into the config', () async {
    final c = make();
    await c
        .read(keyenceScannerCoordinatorProvider.notifier)
        .connect(targetHost: sim.address.address, targetPort: sim.port);
    await _until(() => c.read(configControllerProvider).scanner.hostSaved);
    final s = c.read(configControllerProvider).scanner;
    expect(s.host, sim.address.address);
    expect(s.port, sim.port);
    expect(s.deviceLabel, 'SR-751');
  });

  test(
    'startup auto-connects to a saved endpoint and verifies KEYENCE identity',
    () async {
      final c = make(
        AppConfig(
          scanner: ScannerConfig(
            host: sim.address.address,
            port: sim.port,
            deviceLabel: 'KEYENCE SR-751',
            autoConnect: true,
            autoReconnect: false,
            hostSaved: true,
          ),
        ),
      );

      c.read(keyenceScannerCoordinatorProvider);
      await _until(() => c.read(keyenceScannerCoordinatorProvider).isConnected);

      expect(sim.connectionCount, 1);
      expect(sim.receivedCommands, contains('KEYENCE'));
      expect(c.read(keyenceScannerCoordinatorProvider).model, 'SR-751');
      expect(
        c.read(keyenceScannerCoordinatorProvider).host,
        sim.address.address,
      );
    },
  );

  test(
    'uses a separate listen-only Data Port 1 connection when configured',
    () async {
      final dataSim = await KeyenceSr751Simulator.start(
        model: 'SR-751',
        firmware: 'V2.30',
      );
      addTearDown(dataSim.close);

      final c = make();
      final coordinator = c.read(keyenceScannerCoordinatorProvider.notifier);
      final connected = await coordinator.connect(
        targetHost: sim.address.address,
        targetPort: sim.port,
        targetDataPort: dataSim.port,
      );

      expect(connected, isTrue);
      await _until(
        () => c.read(keyenceScannerCoordinatorProvider).dataChannelConnected,
      );
      await _until(() => dataSim.connectionCount == 1);
      expect(dataSim.receivedCommands, isEmpty);

      dataSim.sendBarcode('DATA-PORT-1-READ');
      await _until(
        () => c.read(keyenceScannerCoordinatorProvider).scanCount == 1,
      );
      final state = c.read(keyenceScannerCoordinatorProvider);
      expect(state.lastScan, 'DATA-PORT-1-READ');
      expect(state.dataPort, dataSim.port);

      await _until(
        () async =>
            c.read(configControllerProvider).scanner.dataPort == dataSim.port,
      );
    },
  );

  test('auto-reconnect changes are saved into the config', () async {
    final c = make();
    await c
        .read(keyenceScannerCoordinatorProvider.notifier)
        .setAutoReconnect(false);
    expect(c.read(configControllerProvider).scanner.autoReconnect, isFalse);
  });

  test('startup values come from the config', () async {
    final c = make(
      const AppConfig(
        scanner: ScannerConfig(
          host: '10.9.8.7',
          port: 9100,
          deviceLabel: 'SR-1000',
          autoConnect: false,
          autoReconnect: false,
          hostSaved: true,
        ),
      ),
    );
    c.read(keyenceScannerCoordinatorProvider);
    await _until(() => c.read(keyenceScannerCoordinatorProvider).port == 9100);
    final st = c.read(keyenceScannerCoordinatorProvider);
    expect(st.host, '10.9.8.7');
    expect(st.model, 'SR-1000');
    expect(st.autoReconnect, isFalse);
    expect(st.isConnected, isFalse);
  });

  test('migration marks the host as saved only when one existed', () {
    expect(
      migrateFromLegacy(const LegacySettings(host: 'h')).scanner.hostSaved,
      isTrue,
    );
    expect(
      migrateFromLegacy(const LegacySettings()).scanner.hostSaved,
      isFalse,
    );
  });
}
