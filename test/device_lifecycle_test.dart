import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/core/device_backend_factory.dart';
import 'package:exalted/features/devices/core/device_exception.dart';
import 'package:exalted/features/devices/core/device_hub.dart';
import 'package:exalted/features/devices/core/device_models.dart';
import 'package:exalted/features/devices/core/device_ownership_manager.dart';
import 'package:exalted/features/devices/core/device_state_machine.dart';

import 'support/fake_device_adapter.dart';

void main() {
  late DeviceOwnershipManager ownership;
  late List<FakeAdapter> created;
  late FakeAdapter Function() build;
  late DeviceHub hub;
  late DeviceIdentity camera;

  DeviceHub newHub() => DeviceHub(
    backends: DeviceBackendFactory()
      ..register(
        fakeRegistration(
          make: (i, c) {
            final adapter = build();
            created.add(adapter);
            return adapter;
          },
        ),
      ),
    ownership: ownership,
    connectTimeout: const Duration(milliseconds: 200),
    acquisitionTimeout: const Duration(milliseconds: 100),
    operationTimeout: const Duration(milliseconds: 200),
    cancelGrace: const Duration(milliseconds: 50),
    reconnectPolicy: const ReconnectPolicy(enabled: false),
  );

  setUp(() {
    ownership = DeviceOwnershipManager();
    created = [];
    build = FakeAdapter.new;
    camera = testCamera();
    hub = newHub();
    hub.register(camera);
  });

  tearDown(() async => hub.dispose());

  group('connect cancellation and timeout', () {
    test('1. cancelling stops the backend and only then disposes it', () async {
      build = () => FakeAdapter()..connectGate = Completer<void>();
      final token = CancelToken();
      final attempt = hub.connect(camera.id, cancel: token);
      await until(() => created.isNotEmpty);
      token.cancel();
      await expectLater(attempt, failsWith(DeviceFailureKind.cancelled));

      final adapter = created.single;
      expect(adapter.lastConnectToken!.isCancelled, isTrue);
      expect(hub.status(camera.id).state, DeviceState.disconnected);
      expect(
        adapter.events.indexOf('connect-end'),
        lessThan(adapter.events.indexOf('dispose')),
      );
      expect(adapter.disposeCalls, 1);
      expect(ownership.isHeld(camera.id), isFalse);
      expect(hub.quarantined, isEmpty);
    });

    test(
      '2. a timeout cancels the backend and leaves nothing running',
      () async {
        build = () => FakeAdapter()..connectGate = Completer<void>();
        await expectLater(
          hub.connect(camera.id, timeout: const Duration(milliseconds: 40)),
          failsWith(DeviceFailureKind.timeout),
        );
        final adapter = created.single;
        expect(adapter.lastConnectToken!.isCancelled, isTrue);
        expect(
          adapter.events.indexOf('connect-end'),
          lessThan(adapter.events.indexOf('dispose')),
        );
        expect(hub.status(camera.id).state, DeviceState.error);
        expect(hub.quarantined, isEmpty);
        expect(ownership.isHeld(camera.id), isFalse);
      },
    );

    test(
      '3. disconnect during a connect never disposes a busy adapter',
      () async {
        build = () => FakeAdapter()..connectGate = Completer<void>();
        final attempt = hub
            .connect(camera.id)
            .then<Object?>((_) => null, onError: (Object e) => e);
        await until(() => created.isNotEmpty);
        await hub.disconnect(camera.id);

        final error = await attempt;
        expect(error, isA<DeviceException>());
        expect((error! as DeviceException).kind, DeviceFailureKind.cancelled);
        final adapter = created.single;
        expect(
          adapter.events.indexOf('connect-end'),
          lessThan(adapter.events.indexOf('dispose')),
        );
        expect(hub.status(camera.id).state, DeviceState.disconnected);
        expect(ownership.isHeld(camera.id), isFalse);
      },
    );

    test(
      '8. connect, disconnect, connect in a row ends connected once',
      () async {
        var first = true;
        build = () {
          final adapter = FakeAdapter();
          if (first) {
            adapter.connectGate = Completer<void>();
            first = false;
          }
          return adapter;
        };
        final a = hub
            .connect(camera.id)
            .then<Object?>((_) => null, onError: (Object e) => e);
        await until(() => created.isNotEmpty);
        final d1 = hub.disconnect(camera.id);
        final d2 = hub.disconnect(camera.id);
        final b = hub.connect(camera.id);

        await Future.wait([d1, d2, b]);
        final aError = await a;
        expect((aError! as DeviceException).kind, DeviceFailureKind.cancelled);
        expect(created, hasLength(2));
        expect(created.first.disposeCalls, 1);
        expect(created.last.disposeCalls, 0);
        expect(hub.status(camera.id).state, DeviceState.connected);
        expect(ownership.ownersOf(camera.id), [hub.ownerId]);
      },
    );
  });

  group('a backend that ignores cancellation', () {
    for (final claims in [true, false]) {
      test('4/5. is quarantined, keeps its lease, and a late result changes '
          'nothing (claimsCancellation=$claims)', () async {
        final gate = Completer<void>();
        build = () =>
            FakeAdapter(ignoreCancel: true, claimsCancellation: claims)
              ..connectGate = gate;
        await expectLater(
          hub.connect(camera.id, timeout: const Duration(milliseconds: 40)),
          failsWith(DeviceFailureKind.timeout),
        );

        final adapter = created.single;
        expect(hub.status(camera.id).state, DeviceState.error);
        expect(hub.status(camera.id).lastError, contains('quarantined'));
        expect(hub.quarantined, hasLength(1));
        expect(adapter.disposeCalls, 0);
        expect(ownership.isHeld(camera.id), isTrue);

        await expectLater(
          hub.connect(camera.id),
          failsWith(DeviceFailureKind.operationQuarantined),
        );
        expect(created, hasLength(1));

        gate.complete();
        await until(() => hub.quarantined.isEmpty);
        expect(adapter.disposeCalls, 1);
        expect(adapter.disconnectCalls, greaterThanOrEqualTo(1));
        expect(ownership.isHeld(camera.id), isFalse);
        expect(hub.status(camera.id).state, DeviceState.error);
      });
    }

    test(
      '5. a late success after remove does not resurrect the device',
      () async {
        final gate = Completer<void>();
        build = () => FakeAdapter(ignoreCancel: true)..connectGate = gate;
        await expectLater(
          hub.connect(camera.id, timeout: const Duration(milliseconds: 40)),
          failsWith(DeviceFailureKind.timeout),
        );
        expect(await hub.remove(camera.id), isTrue);
        gate.complete();
        await until(() => hub.quarantined.isEmpty);
        expect(hub.devices, isEmpty);
        expect(created.single.disposeCalls, 1);
        expect(ownership.isHeld(camera.id), isFalse);
      },
    );
  });

  group('disposal during connection', () {
    test(
      '6a. a cooperative backend is stopped before it is disposed',
      () async {
        build = () => FakeAdapter()..connectGate = Completer<void>();
        final attempt = hub
            .connect(camera.id)
            .then<Object?>((_) => null, onError: (Object e) => e);
        await until(() => created.isNotEmpty);
        await hub.dispose();

        expect(await attempt, isA<DeviceException>());
        final adapter = created.single;
        expect(
          adapter.events.indexOf('connect-end'),
          lessThan(adapter.events.indexOf('dispose')),
        );
        expect(adapter.disposeCalls, 1);
        expect(ownership.isHeld(camera.id), isFalse);
      },
    );

    test(
      '6b. a stubborn backend is quarantined, not disposed under its feet',
      () async {
        final gate = Completer<void>();
        build = () => FakeAdapter(ignoreCancel: true)..connectGate = gate;
        final attempt = hub
            .connect(camera.id)
            .then<Object?>((_) => null, onError: (Object e) => e);
        await until(() => created.isNotEmpty);
        await hub.dispose();

        expect(await attempt, isA<DeviceException>());
        expect(hub.quarantined, hasLength(1));
        expect(created.single.disposeCalls, 0);
        expect(ownership.isHeld(camera.id), isTrue);

        gate.complete();
        await until(() => hub.quarantined.isEmpty);
        expect(created.single.disposeCalls, 1);
        expect(ownership.isHeld(camera.id), isFalse);
      },
    );
  });

  group('acquisition timeout', () {
    test('7a. a timed-out start is cancelled and undone', () async {
      build = () => FakeAdapter()..startGate = Completer<void>();
      await hub.connect(camera.id);
      await expectLater(
        hub.startAcquisition(camera.id),
        failsWith(DeviceFailureKind.timeout),
      );
      final adapter = created.single;
      expect(adapter.lastStartToken!.isCancelled, isTrue);
      expect(adapter.stopCalls, 1);
      expect(hub.status(camera.id).state, DeviceState.connected);
      expect(hub.status(camera.id).lastError, contains('timed out'));
      expect(hub.quarantined, isEmpty);
    });

    test('7b. a start that will not stop quarantines the adapter', () async {
      final gate = Completer<void>();
      build = () => FakeAdapter(ignoreCancel: true)..startGate = gate;
      await hub.connect(camera.id);
      await expectLater(
        hub.startAcquisition(camera.id),
        failsWith(DeviceFailureKind.timeout),
      );
      final adapter = created.single;
      expect(hub.status(camera.id).state, DeviceState.error);
      expect(hub.quarantined, hasLength(1));
      expect(adapter.disposeCalls, 0);
      expect(ownership.isHeld(camera.id), isTrue);

      gate.complete();
      await until(() => hub.quarantined.isEmpty);
      expect(adapter.stopCalls, greaterThanOrEqualTo(1));
      expect(adapter.disposeCalls, 1);
      expect(ownership.isHeld(camera.id), isFalse);
      expect(hub.status(camera.id).state, DeviceState.error);
    });

    test('a frame that arrives after a capture timeout is released', () async {
      final gate = Completer<void>();
      build = () => FakeAdapter(ignoreCancel: true)..captureGate = gate;
      await hub.connect(camera.id);
      await expectLater(
        hub.captureFrame(camera.id),
        failsWith(DeviceFailureKind.timeout),
      );
      final adapter = created.single;
      expect(adapter.framesReleased, 0);
      gate.complete();
      await until(() => adapter.framesReleased == 1);
    });
  });
}
