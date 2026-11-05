import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/core/device_adapter.dart';
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
  late List<DeviceConfiguration> createdConfigs;
  late FakeAdapter Function() build;
  late DeviceHub hub;
  late DeviceIdentity camera;

  DeviceHub newHub({
    DeviceBackendFactory? backends,
    Iterable<DeviceDiscoverySource> sources = const [],
    ReconnectPolicy? policy,
  }) {
    return DeviceHub(
      backends:
          backends ??
          (DeviceBackendFactory()..register(
            fakeRegistration(
              make: (identity, config) {
                final adapter = build();
                created.add(adapter);
                createdConfigs.add(config);
                return adapter;
              },
            ),
          )),
      ownership: ownership,
      sources: sources,
      connectTimeout: const Duration(milliseconds: 300),
      acquisitionTimeout: const Duration(milliseconds: 300),
      operationTimeout: const Duration(milliseconds: 300),
      reconnectPolicy:
          policy ??
          const ReconnectPolicy(
            initialDelay: Duration(milliseconds: 5),
            maxDelay: Duration(milliseconds: 10),
            maxAttempts: 3,
          ),
    );
  }

  setUp(() {
    ownership = DeviceOwnershipManager();
    created = [];
    createdConfigs = [];
    build = FakeAdapter.new;
    camera = testCamera();
    hub = newHub();
  });

  tearDown(() async => hub.dispose());

  group('registration', () {
    test('a supported device becomes ready with its capabilities', () {
      final snapshot = hub.register(camera);
      expect(snapshot.state, DeviceState.ready);
      expect(snapshot.backendId, 'fake');
      expect(snapshot.has(DeviceCapability.continuousFrames), isTrue);
    });

    test('discovering the same device twice registers it once', () {
      hub.register(camera);
      final again = hub.register(testCamera(ip: '10.0.0.9'));
      expect(hub.devices, hasLength(1));
      expect(again.identity.ipAddress, '10.0.0.9');
    });

    test('a device no backend supports is marked unsupported', () async {
      final tcpOnly = newHub(
        backends: DeviceBackendFactory()
          ..register(
            fakeRegistration(
              make: (i, c) => FakeAdapter(),
              supports: (i) => i.transport == DeviceTransport.tcp,
            ),
          ),
      );
      addTearDown(tcpOnly.dispose);
      final snapshot = tcpOnly.register(camera);
      expect(snapshot.state, DeviceState.unsupported);
      expect(snapshot.capabilities, isEmpty);
      await expectLater(
        tcpOnly.connect(camera.id),
        failsWith(DeviceFailureKind.unsupportedDevice),
      );
    });

    test(
      'a missing SDK is reported and can be fixed without re-registering',
      () async {
        var sdkInstalled = false;
        final sdkHub = newHub(
          backends: DeviceBackendFactory()
            ..register(
              fakeRegistration(
                make: (i, c) {
                  final adapter = FakeAdapter();
                  created.add(adapter);
                  return adapter;
                },
                availability: () => sdkInstalled
                    ? const BackendAvailability.available()
                    : const BackendAvailability.sdkMissing(
                        'Vendor SDK not found',
                      ),
              ),
            ),
        );
        addTearDown(sdkHub.dispose);

        expect(sdkHub.register(camera).state, DeviceState.sdkMissing);
        await expectLater(
          sdkHub.connect(camera.id),
          failsWith(DeviceFailureKind.sdkMissing),
        );
        expect(created, isEmpty);

        sdkInstalled = true;
        expect(sdkHub.refreshAvailability(camera.id).state, DeviceState.ready);
        await sdkHub.connect(camera.id);
        expect(sdkHub.status(camera.id).state, DeviceState.connected);
      },
    );

    test('operations on an unknown device fail clearly', () async {
      await expectLater(
        hub.connect('nope'),
        failsWith(DeviceFailureKind.notRegistered),
      );
      expect(
        () => hub.status('nope'),
        failsWith(DeviceFailureKind.notRegistered),
      );
    });
  });

  group('connect and disconnect', () {
    test('connect takes ownership, disconnect releases everything', () async {
      hub.register(camera);
      await hub.connect(camera.id);

      final snapshot = hub.status(camera.id);
      expect(snapshot.state, DeviceState.connected);
      expect(snapshot.lastConnectedAt, isNotNull);
      expect(snapshot.lastError, isNull);
      expect(ownership.ownersOf(camera.id), [hub.ownerId]);

      final adapter = created.single;
      await hub.disconnect(camera.id);

      expect(hub.status(camera.id).state, DeviceState.disconnected);
      expect(ownership.isHeld(camera.id), isFalse);
      expect(adapter.disconnectCalls, 1);
      expect(adapter.disposeCalls, 1);
      expect(adapter.linkController.hasListener, isFalse);
      expect(adapter.readController.hasListener, isFalse);
      expect(adapter.commandController.hasListener, isFalse);
    });

    test('disconnecting twice is harmless and a reconnect works', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      await hub.disconnect(camera.id);
      await hub.disconnect(camera.id);
      await hub.connect(camera.id);
      expect(hub.status(camera.id).state, DeviceState.connected);
      expect(created, hasLength(2));
    });

    test('connecting an already connected device does nothing', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      await hub.connect(camera.id);
      expect(created, hasLength(1));
    });

    test('concurrent connect calls share one connection attempt', () async {
      final gate = Completer<void>();
      build = () => FakeAdapter()..connectGate = gate;
      hub.register(camera);
      final first = hub.connect(camera.id);
      final second = hub.connect(camera.id);
      gate.complete();
      await Future.wait([first, second]);
      expect(created, hasLength(1));
      expect(hub.status(camera.id).state, DeviceState.connected);
    });

    test('state changes are published to listeners', () async {
      final states = <DeviceState>[];
      final sub = hub.changes.listen((s) => states.add(s.state));
      addTearDown(sub.cancel);
      hub.register(camera);
      await hub.connect(camera.id);
      await until(() => states.contains(DeviceState.connected));
      expect(
        states.indexOf(DeviceState.connecting),
        lessThan(states.indexOf(DeviceState.connected)),
      );
    });

    test(
      'a backend failure becomes an error state and can be retried',
      () async {
        var first = true;
        build = () {
          final adapter = FakeAdapter();
          if (first) {
            adapter.connectFailures.add(StateError('connection refused'));
            first = false;
          }
          return adapter;
        };
        hub.register(camera);
        await expectLater(
          hub.connect(camera.id),
          failsWith(DeviceFailureKind.backendError),
        );
        final failed = hub.status(camera.id);
        expect(failed.state, DeviceState.error);
        expect(failed.lastError, contains('connection refused'));
        expect(ownership.isHeld(camera.id), isFalse);
        expect(created.single.disposeCalls, 1);

        await hub.connect(camera.id);
        expect(hub.status(camera.id).state, DeviceState.connected);
      },
    );

    test(
      'cancelling a connect leaves the device cleanly disconnected',
      () async {
        build = () => FakeAdapter()..connectGate = Completer<void>();
        hub.register(camera);
        final token = CancelToken();
        final attempt = hub.connect(camera.id, cancel: token);
        await until(() => created.isNotEmpty);
        token.cancel();
        await expectLater(attempt, failsWith(DeviceFailureKind.cancelled));

        expect(hub.status(camera.id).state, DeviceState.disconnected);
        expect(ownership.isHeld(camera.id), isFalse);
        expect(created.single.disposeCalls, 1);
      },
    );

    test('disconnect during a connect cancels it', () async {
      build = () => FakeAdapter()..connectGate = Completer<void>();
      hub.register(camera);
      final attempt = hub.connect(camera.id);
      await until(() => created.isNotEmpty);
      final disconnecting = hub.disconnect(camera.id);
      await expectLater(attempt, failsWith(DeviceFailureKind.cancelled));
      await disconnecting;
      expect(hub.status(camera.id).state, DeviceState.disconnected);
      expect(ownership.isHeld(camera.id), isFalse);
    });

    test('a connect that never finishes times out and cleans up', () async {
      build = () => FakeAdapter()..connectGate = Completer<void>();
      hub.register(camera);
      await expectLater(
        hub.connect(camera.id, timeout: const Duration(milliseconds: 50)),
        failsWith(DeviceFailureKind.timeout),
      );
      final snapshot = hub.status(camera.id);
      expect(snapshot.state, DeviceState.error);
      expect(snapshot.lastError, contains('Timed out'));
      expect(created.single.disposeCalls, 1);
      expect(ownership.isHeld(camera.id), isFalse);
    });
  });

  group('busy devices and ownership', () {
    test('a backend report of a busy device is surfaced as busy', () async {
      var first = true;
      build = () {
        final adapter = FakeAdapter();
        if (first) {
          adapter.connectFailures.add(
            const DeviceException(
              DeviceFailureKind.busyElsewhere,
              'Opened by another application',
            ),
          );
          first = false;
        }
        return adapter;
      };
      hub.register(camera);
      await expectLater(
        hub.connect(camera.id),
        failsWith(DeviceFailureKind.busyElsewhere),
      );
      final snapshot = hub.status(camera.id);
      expect(snapshot.state, DeviceState.busy);
      expect(snapshot.lastError, contains('another application'));
      expect(ownership.isHeld(camera.id), isFalse);

      await hub.connect(camera.id);
      expect(hub.status(camera.id).state, DeviceState.connected);
    });

    test(
      'an internal ownership conflict blocks the connect before any adapter',
      () async {
        final other = ownership.acquire(
          deviceId: camera.id,
          ownerId: 'other.service',
        );
        hub.register(camera);
        await expectLater(
          hub.connect(camera.id),
          failsWith(DeviceFailureKind.ownershipConflict),
        );
        expect(hub.status(camera.id).state, DeviceState.busy);
        expect(created, isEmpty);

        other.release();
        await hub.connect(camera.id);
        expect(hub.status(camera.id).state, DeviceState.connected);
      },
    );

    test(
      'a driver conflict reported by the backend is shown as busy',
      () async {
        build = () => FakeAdapter()
          ..connectFailures.add(
            const DeviceException(
              DeviceFailureKind.driverConflict,
              'Driver is held by another service',
            ),
          );
        hub.register(camera);
        await expectLater(
          hub.connect(camera.id),
          failsWith(DeviceFailureKind.driverConflict),
        );
        expect(hub.status(camera.id).state, DeviceState.busy);
      },
    );
  });

  group('capabilities and invalid operations', () {
    test('acquisition and capture are refused before connecting', () async {
      hub.register(camera);
      await expectLater(
        hub.startAcquisition(camera.id),
        failsWith(DeviceFailureKind.invalidState),
      );
      await expectLater(
        hub.captureFrame(camera.id),
        failsWith(DeviceFailureKind.invalidState),
      );
    });

    test('acquisition starts, is idempotent, and stops', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      await hub.startAcquisition(camera.id);
      await hub.startAcquisition(camera.id);
      expect(hub.status(camera.id).state, DeviceState.acquiring);
      expect(created.single.startCalls, 1);

      await hub.stopAcquisition(camera.id);
      expect(hub.status(camera.id).state, DeviceState.connected);
      await hub.stopAcquisition(camera.id);
      expect(created.single.stopCalls, 1);
    });

    test(
      'frames, single capture and triggers work on an image device',
      () async {
        hub.register(camera);
        await hub.connect(camera.id);
        expect(hub.frameStream(camera.id), isA<Stream<DeviceFrame>>());
        final frame = await hub.captureFrame(camera.id);
        expect(frame.width, 4);
        await hub.triggerSoftware(camera.id);
        await hub.setTriggerMode(camera.id, TriggerMode.software);
        expect(created.single.triggerCalls, 1);
        expect(created.single.lastTriggerMode, TriggerMode.software);
      },
    );

    test('hardware trigger is refused without that capability', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      await expectLater(
        hub.setTriggerMode(camera.id, TriggerMode.hardware),
        failsWith(DeviceFailureKind.unsupportedCapability),
      );
    });

    test('a reader is never asked for frames', () async {
      final readerHub = newHub(
        backends: DeviceBackendFactory()
          ..register(
            fakeRegistration(
              make: (i, c) => FakeAdapter(
                capabilities: const {
                  DeviceCapability.decodedReads,
                  DeviceCapability.commandResponses,
                  DeviceCapability.connectionMonitoring,
                },
              ),
              capabilities: const {
                DeviceCapability.decodedReads,
                DeviceCapability.commandResponses,
                DeviceCapability.connectionMonitoring,
              },
            ),
          ),
      );
      addTearDown(readerHub.dispose);
      final reader = testReader();
      readerHub.register(reader);
      await readerHub.connect(reader.id);

      await expectLater(
        readerHub.startAcquisition(reader.id),
        failsWith(DeviceFailureKind.unsupportedCapability),
      );
      await expectLater(
        readerHub.captureFrame(reader.id),
        failsWith(DeviceFailureKind.unsupportedCapability),
      );
      expect(
        () => readerHub.frameStream(reader.id),
        failsWith(DeviceFailureKind.unsupportedCapability),
      );
      expect(
        readerHub.capabilities(reader.id),
        isNot(contains(DeviceCapability.continuousFrames)),
      );
    });
  });

  group('reader events', () {
    test(
      'read results and command replies travel on separate streams',
      () async {
        hub.register(camera);
        await hub.connect(camera.id);
        final reads = <HubReadEvent>[];
        final replies = <HubCommandResponse>[];
        final readSub = hub.readEvents.listen(reads.add);
        final replySub = hub.commandResponses.listen(replies.add);
        addTearDown(readSub.cancel);
        addTearDown(replySub.cancel);

        final adapter = created.single;
        adapter.readController.add(
          DeviceReadEvent(data: 'ABC123', timestamp: DateTime(2026, 11, 5)),
        );
        adapter.commandController.add(
          DeviceCommandResponse(
            response: 'OK',
            timestamp: DateTime(2026, 11, 5),
          ),
        );

        await until(() => reads.isNotEmpty && replies.isNotEmpty);
        expect(reads.single.deviceId, camera.id);
        expect(reads.single.event.data, 'ABC123');
        expect(replies.single.response.response, 'OK');
        expect(reads, hasLength(1));
        expect(replies, hasLength(1));
      },
    );
  });

  group('reconnect', () {
    test('the hub reconnects an adapter that cannot do it itself', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      final adapter = created.single;

      adapter.linkController.add(const DeviceLinkEvent.down('cable unplugged'));
      await until(
        () => hub.status(camera.id).state == DeviceState.reconnecting,
      );
      await until(() => hub.status(camera.id).state == DeviceState.connected);

      expect(adapter.connectCalls, 2);
      expect(created, hasLength(1));
      expect(hub.status(camera.id).lastError, isNull);
      expect(ownership.ownersOf(camera.id), [hub.ownerId]);
    });

    test('acquisition resumes after a reconnect', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      await hub.startAcquisition(camera.id);
      final adapter = created.single;

      adapter.linkController.add(const DeviceLinkEvent.down());
      await until(
        () => hub.status(camera.id).state == DeviceState.reconnecting,
      );
      await until(() => hub.status(camera.id).state == DeviceState.acquiring);
      expect(adapter.startCalls, 2);
    });

    test('an adapter that reconnects itself is only waited for', () async {
      build = () => FakeAdapter(reconnectsAutomatically: true);
      hub.register(camera);
      await hub.connect(camera.id);
      final adapter = created.single;

      adapter.linkController.add(const DeviceLinkEvent.down());
      await until(
        () => hub.status(camera.id).state == DeviceState.reconnecting,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(adapter.connectCalls, 1);

      adapter.linkController.add(const DeviceLinkEvent.up());
      await until(() => hub.status(camera.id).state == DeviceState.connected);
      expect(adapter.connectCalls, 1);
    });

    test(
      'reconnecting stops after the allowed attempts and cleans up',
      () async {
        hub.register(camera);
        await hub.connect(camera.id);
        final adapter = created.single..alwaysFailConnect = true;

        adapter.linkController.add(const DeviceLinkEvent.down());
        await until(() => hub.status(camera.id).state == DeviceState.error);

        expect(adapter.connectCalls, 4);
        expect(hub.status(camera.id).lastError, contains('Reconnect failed'));
        expect(adapter.disposeCalls, 1);
        expect(ownership.isHeld(camera.id), isFalse);
      },
    );

    test('disconnecting while reconnecting stops the reconnect loop', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      final adapter = created.single..alwaysFailConnect = true;

      adapter.linkController.add(const DeviceLinkEvent.down());
      await until(
        () => hub.status(camera.id).state == DeviceState.reconnecting,
      );
      await hub.disconnect(camera.id);
      final calls = adapter.connectCalls;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(hub.status(camera.id).state, DeviceState.disconnected);
      expect(adapter.connectCalls, calls);
    });

    test('with reconnect disabled a lost link ends in error', () async {
      final noRetry = newHub(policy: const ReconnectPolicy(enabled: false));
      addTearDown(noRetry.dispose);
      noRetry.register(camera);
      await noRetry.connect(camera.id);
      created.single.linkController.add(const DeviceLinkEvent.down());
      await until(() => noRetry.status(camera.id).state == DeviceState.error);
      expect(created.single.connectCalls, 1);
    });
  });

  group('configuration and diagnostics', () {
    test('settings saved before connecting reach the adapter', () async {
      hub.register(camera);
      await hub.configure(camera.id, DeviceConfiguration({'exposure': 5}));
      await hub.connect(camera.id);
      expect(createdConfigs.single.values['exposure'], 5);
      expect(created.single.applied, isEmpty);
    });

    test('settings changed while connected are applied and stored', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      await hub.configure(camera.id, DeviceConfiguration({'gain': 2}));
      expect(created.single.applied.single.values['gain'], 2);
      expect(hub.status(camera.id).configuration.values['gain'], 2);
    });

    test('configuration is refused without the capability', () async {
      final noConfig = newHub(
        backends: DeviceBackendFactory()
          ..register(
            fakeRegistration(
              make: (i, c) => FakeAdapter(),
              capabilities: const {DeviceCapability.connectionMonitoring},
            ),
          ),
      );
      addTearDown(noConfig.dispose);
      noConfig.register(camera);
      await expectLater(
        noConfig.configure(camera.id, DeviceConfiguration({'a': 1})),
        failsWith(DeviceFailureKind.unsupportedCapability),
      );
    });

    test('diagnostics include the state log and adapter details', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      final diagnostics = await hub.diagnostics(camera.id);
      expect(diagnostics.snapshot.state, DeviceState.connected);
      expect(
        diagnostics.log.any((l) => l.contains('state -> connected')),
        isTrue,
      );
      expect(diagnostics.adapter['fake'], isTrue);
    });
  });

  group('discovery', () {
    test(
      'merges sources, dedupes devices and reports failing sources',
      () async {
        final discoveringHub = newHub(
          sources: [
            _Source('good', [camera, testCamera(ip: '10.0.0.3')]),
            _Source.failing('bad'),
          ],
        );
        addTearDown(discoveringHub.dispose);
        final result = await discoveringHub.discover();
        expect(result.devices, hasLength(1));
        expect(result.errors.keys, ['bad']);
        expect(discoveringHub.devices, hasLength(1));
      },
    );
  });

  group('disposal', () {
    test('removing a connected device releases everything', () async {
      hub.register(camera);
      await hub.connect(camera.id);
      final adapter = created.single;
      final removed = <String>[];
      final sub = hub.removals.listen(removed.add);
      addTearDown(sub.cancel);

      expect(await hub.remove(camera.id), isTrue);
      expect(await hub.remove(camera.id), isFalse);
      await until(() => removed.isNotEmpty);

      expect(removed, [camera.id]);
      expect(adapter.disposeCalls, 1);
      expect(ownership.isHeld(camera.id), isFalse);
      expect(
        () => hub.status(camera.id),
        failsWith(DeviceFailureKind.notRegistered),
      );
    });

    test(
      'disposing the hub closes every device and rejects further use',
      () async {
        hub.register(camera);
        await hub.connect(camera.id);
        final adapter = created.single;

        await hub.dispose();
        await hub.dispose();

        expect(adapter.disposeCalls, 1);
        expect(ownership.isHeld(camera.id), isFalse);
        await expectLater(
          hub.connect(camera.id),
          failsWith(DeviceFailureKind.disposed),
        );
      },
    );
  });
}

class _Source implements DeviceDiscoverySource {
  _Source(this.id, this._devices) : _fail = false;
  _Source.failing(this.id) : _devices = const [], _fail = true;

  @override
  final String id;
  final List<DeviceIdentity> _devices;
  final bool _fail;

  @override
  Future<List<DeviceIdentity>> discover() async {
    if (_fail) throw StateError('scan failed');
    return _devices;
  }
}
