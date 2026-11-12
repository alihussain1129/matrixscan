import 'dart:async';
import 'dart:math' as math;

import 'device_adapter.dart';
import 'device_backend_factory.dart';
import 'device_exception.dart';
import 'device_models.dart';
import 'device_ownership_manager.dart';
import 'device_state_machine.dart';

/// How the hub restores a lost link for adapters that do not do it themselves.
class ReconnectPolicy {
  const ReconnectPolicy({
    this.enabled = true,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 16),
    this.maxAttempts,
  });

  final bool enabled;
  final Duration initialDelay;
  final Duration maxDelay;

  /// Null retries until the device is disconnected or removed.
  final int? maxAttempts;

  /// Delay before [attempt] (1-based), doubling up to [maxDelay].
  Duration delayFor(int attempt) {
    final shift = math.min(math.max(attempt - 1, 0), 20);
    final micros = initialDelay.inMicroseconds * (1 << shift);
    final cap = maxDelay.inMicroseconds;
    return Duration(microseconds: micros > cap ? cap : micros);
  }
}

class HubReadEvent {
  const HubReadEvent(this.deviceId, this.event);
  final String deviceId;
  final DeviceReadEvent event;
}

class HubCommandResponse {
  const HubCommandResponse(this.deviceId, this.response);
  final String deviceId;
  final DeviceCommandResponse response;
}

class DiscoveryResult {
  const DiscoveryResult({required this.devices, required this.errors});

  final List<DeviceSnapshot> devices;

  /// Discovery source id to the error it reported.
  final Map<String, String> errors;
}

/// A backend operation that did not stop when cancelled. The hub keeps the
/// adapter and its ownership lease until the operation really finishes, then
/// closes the adapter. It never changes the device state afterwards.
class QuarantinedOperation {
  QuarantinedOperation._(this.deviceId, this.operation, this.since);

  final String deviceId;
  final String operation;
  final DateTime since;
  Future<void> _closed = Future<void>.value();

  /// Completes after the late operation finished and the adapter was closed.
  Future<void> get closed => _closed;
}

enum _Why { completed, timeout, cancelled }

class _RunResult {
  const _RunResult(this.why, this.settled, this.error, this.stack);

  final _Why why;

  /// True if the backend call has really returned (not just timed out).
  final bool settled;
  final Object? error;
  final StackTrace? stack;
}

class _Entry {
  _Entry(this.identity) : machine = DeviceStateMachine();

  DeviceIdentity identity;
  BackendRegistration? registration;
  Set<DeviceCapability> capabilities = const <DeviceCapability>{};
  final DeviceStateMachine machine;
  DeviceAdapter? adapter;
  OwnershipLease? lease;
  DateTime? lastConnectedAt;
  String? lastError;
  DeviceConfiguration configuration = DeviceConfiguration.empty;
  int epoch = 0;
  Future<void>? connecting;
  Future<void>? teardown;
  CancelToken? connectCancel;
  final Set<CancelToken> opCancels = {};
  final Set<Future<void>> pending = {};
  Timer? reconnectTimer;
  int reconnectAttempts = 0;
  bool wasAcquiring = false;
  bool acqMaybeRunning = false;
  bool removed = false;
  final List<StreamSubscription<dynamic>> subs = [];
  final List<String> log = [];
}

/// Central authority for registered devices, adapter selection and lifecycle.
///
/// Use it from one isolate (the UI isolate). State changes are synchronous
/// steps; every wait is asynchronous, so the UI is never blocked.
///
/// Safety rules:
/// * An epoch counter invalidates in-flight work on disconnect/remove/dispose.
/// * Every backend call that may take time is tracked in `pending`. An adapter
///   is only disposed when nothing is pending; otherwise it is quarantined.
/// * `Future.timeout` is never trusted to stop work: on timeout the hub
///   cancels the [CancelToken] and waits [cancelGrace] for the backend.
/// * Late results never change the state of a disconnected or removed device.
class DeviceHub {
  DeviceHub({
    required this.backends,
    DeviceOwnershipManager? ownership,
    Iterable<DeviceDiscoverySource> sources = const [],
    this.ownerId = 'exalted.device_hub',
    this.connectTimeout = const Duration(seconds: 10),
    this.acquisitionTimeout = const Duration(seconds: 5),
    this.operationTimeout = const Duration(seconds: 5),
    this.discoveryTimeout = const Duration(seconds: 10),
    this.cancelGrace = const Duration(seconds: 2),
    this.reconnectPolicy = const ReconnectPolicy(),
    DateTime Function()? clock,
  }) : ownership = ownership ?? DeviceOwnershipManager(),
       _sources = List<DeviceDiscoverySource>.of(sources),
       _clock = clock ?? DateTime.now;

  final DeviceBackendFactory backends;
  final DeviceOwnershipManager ownership;
  final String ownerId;
  final Duration connectTimeout;
  final Duration acquisitionTimeout;
  final Duration operationTimeout;
  final Duration discoveryTimeout;

  /// How long a cancelled backend call may take to stop before quarantine.
  final Duration cancelGrace;
  final ReconnectPolicy reconnectPolicy;

  final List<DeviceDiscoverySource> _sources;
  final DateTime Function() _clock;
  final Map<String, _Entry> _entries = {};
  final List<QuarantinedOperation> _quarantined = [];
  bool _disposed = false;

  static const int _maxLogLines = 100;
  static const Set<DeviceState> _activeStates = {
    DeviceState.connecting,
    DeviceState.connected,
    DeviceState.acquiring,
    DeviceState.reconnecting,
  };
  static const Set<DeviceState> _liveStates = {
    DeviceState.connected,
    DeviceState.acquiring,
    DeviceState.reconnecting,
  };

  final StreamController<DeviceSnapshot> _changes =
      StreamController<DeviceSnapshot>.broadcast();
  final StreamController<String> _removals =
      StreamController<String>.broadcast();
  final StreamController<HubReadEvent> _reads =
      StreamController<HubReadEvent>.broadcast();
  final StreamController<HubCommandResponse> _commandResponses =
      StreamController<HubCommandResponse>.broadcast();

  /// A snapshot after every change of a device (state, details, config).
  Stream<DeviceSnapshot> get changes => _changes.stream;

  /// Ids of devices removed from the hub.
  Stream<String> get removals => _removals.stream;

  /// Decoded read results from every connected reader.
  Stream<HubReadEvent> get readEvents => _reads.stream;

  /// Command replies, kept apart from read results.
  Stream<HubCommandResponse> get commandResponses => _commandResponses.stream;

  List<DeviceSnapshot> get devices => [
    for (final entry in _entries.values) _snapshot(entry),
  ];

  /// Backend operations that ignored cancellation and are still running.
  List<QuarantinedOperation> get quarantined =>
      List<QuarantinedOperation>.unmodifiable(_quarantined);

  // ---------------------------------------------------------------- discovery

  void addSource(DeviceDiscoverySource source) {
    _ensureOpen();
    _sources.add(source);
  }

  Future<DiscoveryResult> discover() async {
    _ensureOpen();
    final errors = <String, String>{};
    final found = <String, DeviceSnapshot>{};
    for (final source in List<DeviceDiscoverySource>.of(_sources)) {
      try {
        final identities = await source.discover().timeout(discoveryTimeout);
        if (_disposed) break;
        for (final identity in identities) {
          final snapshot = register(identity);
          found[snapshot.id] = snapshot;
        }
      } catch (err) {
        errors[source.id] = err.toString();
      }
    }
    return DiscoveryResult(devices: found.values.toList(), errors: errors);
  }

  // ------------------------------------------------------------ registration

  /// Registers a device, or merges a repeat discovery into the existing one.
  DeviceSnapshot register(
    DeviceIdentity identity, {
    DeviceConfiguration? configuration,
  }) {
    _ensureOpen();
    final existing = _entries[identity.id];
    if (existing != null) {
      final merged = existing.identity.mergedWith(identity);
      if (merged != existing.identity) {
        existing.identity = merged;
        _emit(existing);
      }
      return _snapshot(existing);
    }
    final entry = _Entry(identity);
    if (configuration != null) entry.configuration = configuration;
    _entries[identity.id] = entry;
    _refresh(entry);
    return _snapshot(entry);
  }

  /// Re-checks backend availability, e.g. after an SDK was installed.
  DeviceSnapshot refreshAvailability(String id) {
    final entry = _requireEntry(id);
    _refresh(entry);
    return _snapshot(entry);
  }

  /// Disconnects (if needed) and forgets a device. Returns false if unknown.
  Future<bool> remove(String id) async {
    if (_disposed) return false;
    final entry = _entries.remove(id);
    if (entry == null) return false;
    entry.removed = true;
    await _teardown(entry);
    entry.machine.dispose();
    if (!_removals.isClosed) _removals.add(id);
    return true;
  }

  DeviceSnapshot status(String id) => _snapshot(_requireEntry(id));

  Set<DeviceCapability> capabilities(String id) =>
      Set<DeviceCapability>.unmodifiable(_requireEntry(id).capabilities);

  // --------------------------------------------------------------- lifecycle

  Future<void> connect(
    String id, {
    Duration? timeout,
    CancelToken? cancel,
  }) async {
    var entry = _requireEntry(id);
    final running = entry.teardown;
    if (running != null) {
      try {
        await running;
      } catch (_) {}
      entry = _requireEntry(id);
    }
    var state = entry.machine.state;
    if (state == DeviceState.connected || state == DeviceState.acquiring) {
      return;
    }
    if (state == DeviceState.connecting) {
      await entry.connecting;
      return;
    }
    if (state == DeviceState.reconnecting) {
      throw DeviceException(
        DeviceFailureKind.invalidState,
        'Device is reconnecting',
        deviceId: id,
      );
    }
    if (state == DeviceState.discovered ||
        state == DeviceState.sdkMissing ||
        state == DeviceState.driverMissing ||
        state == DeviceState.unsupported) {
      _refresh(entry);
      state = entry.machine.state;
      if (state != DeviceState.ready) throw _unavailable(entry);
    }
    if (_quarantined.any((q) => q.deviceId == id)) {
      throw DeviceException(
        DeviceFailureKind.operationQuarantined,
        'A previous backend operation is still running and quarantined; '
        'the device cannot be reopened until it finishes',
        deviceId: id,
      );
    }

    final future = _connectImpl(entry, timeout ?? connectTimeout, cancel);
    entry.connecting = future;
    try {
      await future;
    } finally {
      if (identical(entry.connecting, future)) entry.connecting = null;
    }
  }

  Future<void> disconnect(String id) async {
    final entry = _requireEntry(id);
    final running = entry.teardown;
    if (running != null) {
      await running;
      return;
    }
    if (!_activeStates.contains(entry.machine.state)) return;
    await _teardown(entry, moveToDisconnected: true);
  }

  // ------------------------------------------------------------- acquisition

  Future<void> startAcquisition(String id) async {
    final entry = _requireEntry(id);
    _requireCapability(entry, DeviceCapability.continuousFrames);
    if (entry.machine.state == DeviceState.acquiring) return;
    final (adapter, source) = _adapterFor<FrameSource>(entry, const {
      DeviceState.connected,
    }, 'start acquisition');
    final epoch = entry.epoch;
    entry.acqMaybeRunning = true;
    await _op<void>(
      entry,
      adapter,
      'start acquisition',
      (token) => source.startAcquisition(token),
      acquisitionTimeout,
      quarantineIfStuck: true,
      undoOnTimeout: () async {
        await source.stopAcquisition();
        entry.acqMaybeRunning = false;
      },
    );
    if (_isGone(entry) ||
        epoch != entry.epoch ||
        entry.machine.state != DeviceState.connected) {
      throw DeviceException(
        DeviceFailureKind.invalidState,
        'Device state changed while starting acquisition',
        deviceId: id,
      );
    }
    _move(entry, DeviceState.acquiring);
  }

  Future<void> stopAcquisition(String id) async {
    final entry = _requireEntry(id);
    _requireCapability(entry, DeviceCapability.continuousFrames);
    if (entry.machine.state == DeviceState.connected) return;
    final (adapter, source) = _adapterFor<FrameSource>(entry, const {
      DeviceState.acquiring,
    }, 'stop acquisition');
    final epoch = entry.epoch;
    await _op<void>(
      entry,
      adapter,
      'stop acquisition',
      (token) => source.stopAcquisition(),
      acquisitionTimeout,
    );
    entry.acqMaybeRunning = false;
    if (!_isGone(entry) &&
        epoch == entry.epoch &&
        entry.machine.state == DeviceState.acquiring) {
      _move(entry, DeviceState.connected);
    }
  }

  /// The device's frame stream. Subscribe after connecting; a new connection
  /// replaces it, so resubscribe after a disconnect/connect cycle.
  Stream<DeviceFrame> frameStream(String id) {
    final entry = _requireEntry(id);
    _requireCapability(entry, DeviceCapability.continuousFrames);
    final (_, source) = _adapterFor<FrameSource>(entry, const {
      DeviceState.connected,
      DeviceState.acquiring,
    }, 'read frames');
    return source.frames;
  }

  /// The caller owns the returned frame and must [DeviceFrame.release] it.
  Future<DeviceFrame> captureFrame(String id) async {
    final entry = _requireEntry(id);
    _requireCapability(entry, DeviceCapability.singleFrame);
    final (adapter, capture) = _adapterFor<SingleFrameCapture>(entry, const {
      DeviceState.connected,
      DeviceState.acquiring,
    }, 'capture a frame');
    return _op<DeviceFrame>(
      entry,
      adapter,
      'capture frame',
      (token) => capture.captureFrame(token),
      acquisitionTimeout,
      discard: (late) => late.release(),
    );
  }

  Future<void> triggerSoftware(String id) async {
    final entry = _requireEntry(id);
    _requireCapability(entry, DeviceCapability.softwareTrigger);
    final (adapter, trigger) = _adapterFor<SoftwareTriggerable>(entry, const {
      DeviceState.connected,
      DeviceState.acquiring,
    }, 'send a software trigger');
    await _op<void>(
      entry,
      adapter,
      'software trigger',
      (token) => trigger.triggerSoftware(),
      operationTimeout,
    );
  }

  Future<void> setTriggerMode(String id, TriggerMode mode) async {
    final entry = _requireEntry(id);
    switch (mode) {
      case TriggerMode.software:
        _requireCapability(entry, DeviceCapability.softwareTrigger);
      case TriggerMode.hardware:
        _requireCapability(entry, DeviceCapability.hardwareTrigger);
      case TriggerMode.off:
        if (!entry.capabilities.contains(DeviceCapability.softwareTrigger) &&
            !entry.capabilities.contains(DeviceCapability.hardwareTrigger)) {
          throw DeviceException(
            DeviceFailureKind.unsupportedCapability,
            'Device has no trigger support',
            deviceId: id,
          );
        }
    }
    final (adapter, trigger) = _adapterFor<TriggerConfigurable>(entry, const {
      DeviceState.connected,
    }, 'set the trigger mode');
    await _op<void>(
      entry,
      adapter,
      'set trigger mode',
      (token) => trigger.setTriggerMode(mode),
      operationTimeout,
    );
  }

  // ----------------------------------------------------- configuration, info

  /// Stores [configuration] (merged over what is saved) and, if the device is
  /// connected, applies the changed keys to it. Stored values are passed to
  /// the adapter whenever it is created.
  Future<void> configure(String id, DeviceConfiguration configuration) async {
    final entry = _requireEntry(id);
    _requireCapability(entry, DeviceCapability.configuration);
    final state = entry.machine.state;
    if (state == DeviceState.connected || state == DeviceState.acquiring) {
      final (adapter, device) = _adapterFor<ConfigurableDevice>(entry, const {
        DeviceState.connected,
        DeviceState.acquiring,
      }, 'apply configuration');
      await _op<void>(
        entry,
        adapter,
        'apply configuration',
        (token) => device.applyConfiguration(configuration),
        operationTimeout,
      );
    }
    if (_isGone(entry)) return;
    entry.configuration = entry.configuration.merged(configuration);
    _emit(entry);
  }

  Future<DeviceDiagnostics> diagnostics(String id) async {
    final entry = _requireEntry(id);
    var adapterInfo = const <String, Object?>{};
    final adapter = entry.adapter;
    if (adapter != null &&
        entry.capabilities.contains(DeviceCapability.diagnostics) &&
        _liveStates.contains(entry.machine.state)) {
      try {
        adapterInfo = await _op<Map<String, Object?>>(
          entry,
          adapter,
          'diagnostics',
          (token) => adapter.diagnostics(),
          operationTimeout,
          recordFailure: false,
        );
      } catch (err) {
        adapterInfo = {'error': err.toString()};
      }
    }
    return DeviceDiagnostics(
      snapshot: _snapshot(entry),
      log: List<String>.unmodifiable(entry.log),
      adapter: adapterInfo,
      reconnectAttempts: entry.reconnectAttempts,
    );
  }

  // ----------------------------------------------------------------- dispose

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final entries = _entries.values.toList();
    _entries.clear();
    for (final entry in entries) {
      entry.removed = true;
    }
    await Future.wait(
      entries.map((entry) async {
        try {
          await _teardown(entry);
        } catch (_) {}
        entry.machine.dispose();
      }),
    );
    if (_quarantined.isNotEmpty) {
      await Future.wait(_quarantined.map((q) => q.closed))
          .timeout(cancelGrace, onTimeout: () => <void>[]);
    }
    await _changes.close();
    await _removals.close();
    await _reads.close();
    await _commandResponses.close();
  }

  // ------------------------------------------------------------ connect path

  Future<void> _connectImpl(
    _Entry entry,
    Duration timeout,
    CancelToken? userCancel,
  ) async {
    final epoch = entry.epoch;
    final id = entry.identity.id;
    final cancel = CancelToken();
    entry.connectCancel = cancel;
    if (userCancel != null) {
      unawaited(userCancel.whenCancelled.then((_) => cancel.cancel()));
    }
    _move(entry, DeviceState.connecting);
    try {
      entry.lease = ownership.acquire(
        deviceId: id,
        ownerId: ownerId,
        supportedModes:
            entry.registration?.supportedAccessModes ??
            const {AccessMode.exclusive},
      );
      final adapter = backends.createAdapter(
        entry.identity,
        entry.configuration,
      );
      entry.adapter = adapter;
      if (!adapter.capabilities.containsAll(entry.capabilities)) {
        throw DeviceException(
          DeviceFailureKind.backendError,
          'Adapter ${adapter.backendId} does not provide the capabilities '
          'its backend declares',
          deviceId: id,
        );
      }
      final run = await _run(
        entry,
        adapter.connect,
        timeout,
        cancel,
        cancellable: adapter.supportsCancellation,
      );
      if (run.why == _Why.timeout) {
        throw DeviceException(
          DeviceFailureKind.timeout,
          'Timed out after ${timeout.inMilliseconds} ms',
          deviceId: id,
        );
      }
      if (run.why == _Why.cancelled || cancel.isCancelled) {
        throw DeviceException(
          DeviceFailureKind.cancelled,
          'Operation cancelled',
          deviceId: id,
        );
      }
      if (run.error != null) {
        Error.throwWithStackTrace(run.error!, run.stack ?? StackTrace.current);
      }
      _ensureCurrent(entry, epoch);
      _attach(entry, adapter);
      entry.lastConnectedAt = _clock();
      entry.lastError = null;
      entry.reconnectAttempts = 0;
      _move(entry, DeviceState.connected);
    } on Object catch (err, stack) {
      final failure = _asDeviceException(entry, err);
      final quarantined = await _releaseResources(entry, waitForPending: false);
      if (!_isGone(entry) && epoch == entry.epoch) {
        if (quarantined) {
          entry.lastError =
              '${failure.message} '
              '(backend connect still running; adapter quarantined)';
          _log(entry, entry.lastError!);
          _move(entry, DeviceState.error);
        } else {
          if (failure.kind != DeviceFailureKind.cancelled) {
            entry.lastError = failure.message;
          }
          _log(
            entry,
            'connect failed: ${failure.kind.name}: ${failure.message}',
          );
          _move(entry, _stateForFailure(failure.kind));
        }
      }
      Error.throwWithStackTrace(failure, stack);
    } finally {
      if (identical(entry.connectCancel, cancel)) entry.connectCancel = null;
    }
  }

  /// Runs a backend call with timeout and cancellation. The call is tracked
  /// in [_Entry.pending] until it really returns. On timeout or cancel the
  /// token is cancelled and, if [cancellable], the call gets [cancelGrace]
  /// to stop. [_RunResult.settled] tells whether it actually returned.
  Future<_RunResult> _run(
    _Entry entry,
    Future<void> Function(CancelToken token) op,
    Duration timeout,
    CancelToken token, {
    required bool cancellable,
  }) async {
    Object? error;
    StackTrace? stack;
    var finished = false;
    final done = Future<void>.sync(() => op(token))
        .then<void>(
          (_) {},
          onError: (Object e, StackTrace s) {
            error = e;
            stack = s;
          },
        )
        .whenComplete(() {
          finished = true;
        });
    entry.pending.add(done);
    unawaited(
      done.whenComplete(() {
        entry.pending.remove(done);
      }),
    );

    final first = Completer<_Why>();
    final timer = Timer(timeout, () {
      if (!first.isCompleted) first.complete(_Why.timeout);
    });
    unawaited(
      token.whenCancelled.then((_) {
        if (!first.isCompleted) first.complete(_Why.cancelled);
      }),
    );
    unawaited(
      done.then((_) {
        if (!first.isCompleted) first.complete(_Why.completed);
      }),
    );

    final why = await first.future;
    timer.cancel();
    if (why != _Why.completed) {
      token.cancel();
      if (cancellable) {
        await done.timeout(cancelGrace, onTimeout: () {});
      }
    }
    return _RunResult(why, finished, error, stack);
  }

  /// Runs a short adapter call through [_run]. Errors become
  /// [DeviceException]s. A frame (or other value) that arrives after a
  /// timeout is passed to [discard] instead of being returned.
  Future<T> _op<T>(
    _Entry entry,
    DeviceAdapter adapter,
    String what,
    Future<T> Function(CancelToken token) fn,
    Duration timeout, {
    void Function(T late)? discard,
    Future<void> Function()? undoOnTimeout,
    bool quarantineIfStuck = false,
    bool recordFailure = true,
  }) async {
    final id = entry.identity.id;
    final epoch = entry.epoch;
    final token = CancelToken();
    entry.opCancels.add(token);
    T? value;
    var hasValue = false;
    try {
      final run = await _run(
        entry,
        (t) async {
          final result = await fn(t);
          if (t.isCancelled) {
            discard?.call(result);
          } else {
            value = result;
            hasValue = true;
          }
        },
        timeout,
        token,
        cancellable: adapter.supportsCancellation,
      );

      DeviceException? failure;
      if (run.why == _Why.timeout) {
        failure = DeviceException(
          DeviceFailureKind.timeout,
          '$what timed out after ${timeout.inMilliseconds} ms',
          deviceId: id,
        );
      } else if (run.why == _Why.cancelled) {
        failure = DeviceException(
          DeviceFailureKind.cancelled,
          '$what cancelled',
          deviceId: id,
        );
      } else if (run.error != null) {
        final err = run.error!;
        failure = err is DeviceException
            ? err
            : DeviceException(
                DeviceFailureKind.backendError,
                '$what failed: $err',
                deviceId: id,
                cause: err,
              );
      } else if (!hasValue) {
        failure = DeviceException(
          DeviceFailureKind.cancelled,
          '$what cancelled',
          deviceId: id,
        );
      }
      if (failure == null) return value as T;

      if (!run.settled && quarantineIfStuck) {
        await _releaseResources(entry, waitForPending: false);
        if (!_isGone(entry) && epoch == entry.epoch) {
          entry.lastError =
              '${failure.message} (backend still running; adapter quarantined)';
          _log(entry, entry.lastError!);
          _move(entry, DeviceState.error);
        }
        throw failure;
      }
      if (run.why == _Why.timeout && run.settled && undoOnTimeout != null) {
        try {
          await undoOnTimeout().timeout(operationTimeout);
        } catch (err) {
          _log(entry, 'undo after timeout failed: $err');
        }
      }
      if (recordFailure && failure.kind != DeviceFailureKind.cancelled) {
        _noteFailure(entry, what, failure.message);
      }
      throw failure;
    } finally {
      entry.opCancels.remove(token);
    }
  }

  void _attach(_Entry entry, DeviceAdapter adapter) {
    final id = entry.identity.id;
    entry.subs.add(
      adapter.linkEvents.listen(
        (event) => _onLink(entry, adapter, event),
        onError: (Object err) => _log(entry, 'link stream error: $err'),
      ),
    );
    if (adapter is ReadEventSource) {
      entry.subs.add(
        (adapter as ReadEventSource).reads.listen((event) {
          if (!_reads.isClosed) _reads.add(HubReadEvent(id, event));
        }, onError: (Object err) => _log(entry, 'read stream error: $err')),
      );
    }
    if (adapter is CommandResponseSource) {
      entry.subs.add(
        (adapter as CommandResponseSource).commandResponses.listen((response) {
          if (!_commandResponses.isClosed) {
            _commandResponses.add(HubCommandResponse(id, response));
          }
        }, onError: (Object err) => _log(entry, 'command stream error: $err')),
      );
    }
  }

  // --------------------------------------------------------------- reconnect

  void _onLink(_Entry entry, DeviceAdapter adapter, DeviceLinkEvent event) {
    if (_isGone(entry) || !identical(entry.adapter, adapter)) return;
    final state = entry.machine.state;
    if (!event.connected) {
      if (state != DeviceState.connected && state != DeviceState.acquiring) {
        return;
      }
      entry.wasAcquiring = state == DeviceState.acquiring;
      entry.lastError = event.error ?? 'Connection lost';
      _log(entry, 'link down: ${entry.lastError}');
      _move(entry, DeviceState.reconnecting);
      if (!adapter.reconnectsAutomatically) _scheduleReconnect(entry);
    } else if (state == DeviceState.reconnecting) {
      entry.reconnectTimer?.cancel();
      entry.reconnectTimer = null;
      _onReconnected(entry);
    }
  }

  void _scheduleReconnect(_Entry entry) {
    if (entry.reconnectTimer != null || _isGone(entry)) return;
    final policy = reconnectPolicy;
    final attempt = entry.reconnectAttempts + 1;
    if (!policy.enabled) {
      unawaited(_giveUp(entry, 'Connection lost and reconnect is disabled'));
      return;
    }
    final limit = policy.maxAttempts;
    if (limit != null && attempt > limit) {
      unawaited(
        _giveUp(
          entry,
          'Reconnect failed after ${entry.reconnectAttempts} attempts',
        ),
      );
      return;
    }
    entry.reconnectAttempts = attempt;
    final epoch = entry.epoch;
    entry.reconnectTimer = Timer(policy.delayFor(attempt), () {
      entry.reconnectTimer = null;
      unawaited(_reconnectOnce(entry, epoch));
    });
  }

  bool _reconnectStale(_Entry entry, int epoch) =>
      _isGone(entry) ||
      epoch != entry.epoch ||
      entry.machine.state != DeviceState.reconnecting;

  Future<void> _reconnectOnce(_Entry entry, int epoch) async {
    if (_reconnectStale(entry, epoch)) return;
    final adapter = entry.adapter;
    if (adapter == null) return;
    final cancel = CancelToken();
    entry.connectCancel = cancel;
    try {
      try {
        await adapter.disconnect().timeout(operationTimeout);
      } catch (_) {}
      final run = await _run(
        entry,
        adapter.connect,
        connectTimeout,
        cancel,
        cancellable: adapter.supportsCancellation,
      );
      if (_reconnectStale(entry, epoch)) return;
      if (!run.settled) {
        await _releaseResources(entry, waitForPending: false);
        entry.lastError =
            'Reconnect did not stop after cancel; adapter quarantined';
        _log(entry, entry.lastError!);
        _move(entry, DeviceState.error);
        return;
      }
      if (run.why == _Why.completed &&
          run.error == null &&
          !cancel.isCancelled) {
        _onReconnected(entry);
        return;
      }
      throw run.error ??
          DeviceException(
            run.why == _Why.timeout
                ? DeviceFailureKind.timeout
                : DeviceFailureKind.cancelled,
            run.why == _Why.timeout ? 'Timed out' : 'Cancelled',
            deviceId: entry.identity.id,
          );
    } catch (err) {
      if (_reconnectStale(entry, epoch)) return;
      entry.lastError =
          'Reconnect attempt ${entry.reconnectAttempts} failed: $err';
      _log(entry, entry.lastError!);
      _emit(entry);
      _scheduleReconnect(entry);
    } finally {
      if (identical(entry.connectCancel, cancel)) entry.connectCancel = null;
    }
  }

  void _onReconnected(_Entry entry) {
    entry.reconnectAttempts = 0;
    entry.lastConnectedAt = _clock();
    entry.lastError = null;
    _move(entry, DeviceState.connected);
    if (entry.wasAcquiring) {
      entry.wasAcquiring = false;
      unawaited(_resumeAcquisition(entry, entry.epoch));
    }
  }

  Future<void> _resumeAcquisition(_Entry entry, int epoch) async {
    final adapter = entry.adapter;
    if (adapter == null || adapter is! FrameSource) return;
    final source = adapter as FrameSource;
    try {
      entry.acqMaybeRunning = true;
      await _op<void>(
        entry,
        adapter,
        'resume acquisition',
        (token) => source.startAcquisition(token),
        acquisitionTimeout,
        quarantineIfStuck: true,
        undoOnTimeout: () async {
          await source.stopAcquisition();
          entry.acqMaybeRunning = false;
        },
      );
      if (_isGone(entry) ||
          epoch != entry.epoch ||
          entry.machine.state != DeviceState.connected) {
        return;
      }
      _move(entry, DeviceState.acquiring);
    } catch (err) {
      if (_isGone(entry)) return;
      entry.lastError = 'Could not resume acquisition: $err';
      _log(entry, entry.lastError!);
      _emit(entry);
    }
  }

  Future<void> _giveUp(_Entry entry, String reason) async {
    final epoch = entry.epoch;
    await _releaseResources(entry, waitForPending: false);
    if (_isGone(entry) || epoch != entry.epoch) return;
    entry.lastError = reason;
    _log(entry, reason);
    _move(entry, DeviceState.error);
  }

  // ---------------------------------------------------------------- cleanup

  /// Closes everything this entry holds. Returns true if the adapter had to be
  /// quarantined because a backend call was still running.
  ///
  /// Idempotent: fields are cleared before the first await, so a second
  /// caller finds nothing to do. The adapter is only disposed when no tracked
  /// backend call is pending.
  Future<bool> _releaseResources(
    _Entry entry, {
    required bool waitForPending,
  }) async {
    final adapter = entry.adapter;
    final lease = entry.lease;
    final subs = List<StreamSubscription<dynamic>>.of(entry.subs);
    entry.adapter = null;
    entry.lease = null;
    entry.subs.clear();
    for (final sub in subs) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    if (adapter == null) {
      lease?.release();
      return false;
    }
    if (waitForPending && entry.pending.isNotEmpty) {
      await Future.wait(entry.pending.toList())
          .timeout(cancelGrace, onTimeout: () => <void>[]);
    }
    if (entry.pending.isNotEmpty) {
      _quarantine(
        entry.identity.id,
        adapter,
        lease,
        Future.wait(entry.pending.toList()),
        'backend operation',
      );
      _log(entry, 'adapter quarantined: a backend call is still running');
      return true;
    }
    if (entry.acqMaybeRunning && adapter is FrameSource) {
      try {
        await (adapter as FrameSource).stopAcquisition().timeout(
          operationTimeout,
        );
      } catch (err) {
        _log(entry, 'stopAcquisition during cleanup failed: $err');
      }
    }
    entry.acqMaybeRunning = false;
    try {
      await adapter.disconnect().timeout(operationTimeout);
    } catch (err) {
      _log(entry, 'adapter disconnect failed: $err');
    }
    try {
      await adapter.dispose().timeout(operationTimeout);
    } catch (err) {
      _log(entry, 'adapter dispose failed: $err');
    }
    lease?.release();
    return false;
  }

  /// Parks an adapter whose backend call has not returned. Keeps the lease
  /// so nobody reopens the device, and closes the adapter once [done]
  /// completes. Never touches device state.
  void _quarantine(
    String deviceId,
    DeviceAdapter adapter,
    OwnershipLease? lease,
    Future<void> done,
    String what,
  ) {
    final q = QuarantinedOperation._(deviceId, what, _clock());
    _quarantined.add(q);
    q._closed = done.then<void>((_) async {
      if (adapter is FrameSource) {
        try {
          await (adapter as FrameSource).stopAcquisition().timeout(
            operationTimeout,
          );
        } catch (_) {}
      }
      try {
        await adapter.disconnect().timeout(operationTimeout);
      } catch (_) {}
      try {
        await adapter.dispose().timeout(operationTimeout);
      } catch (_) {}
      lease?.release();
      _quarantined.remove(q);
    });
  }

  Future<void> _teardown(_Entry entry, {bool moveToDisconnected = false}) {
    final running = entry.teardown;
    if (running != null) return running;
    final future = _teardownImpl(entry, moveToDisconnected);
    entry.teardown = future;
    return future.whenComplete(() {
      if (identical(entry.teardown, future)) entry.teardown = null;
    });
  }

  Future<void> _teardownImpl(_Entry entry, bool moveToDisconnected) async {
    entry.epoch++;
    entry.reconnectTimer?.cancel();
    entry.reconnectTimer = null;
    entry.connectCancel?.cancel();
    for (final token in entry.opCancels.toList()) {
      token.cancel();
    }
    final connecting = entry.connecting;
    if (connecting != null) {
      try {
        await connecting;
      } catch (_) {}
    }
    await _releaseResources(entry, waitForPending: true);
    entry.reconnectAttempts = 0;
    entry.wasAcquiring = false;
    if (moveToDisconnected &&
        !entry.removed &&
        DeviceStateMachine.canTransition(
          entry.machine.state,
          DeviceState.disconnected,
        )) {
      _move(entry, DeviceState.disconnected);
    }
  }

  // ----------------------------------------------------------------- helpers

  void _ensureOpen() {
    if (_disposed) {
      throw const DeviceException(
        DeviceFailureKind.disposed,
        'Device hub is disposed',
      );
    }
  }

  _Entry _requireEntry(String id) {
    _ensureOpen();
    final entry = _entries[id];
    if (entry == null) {
      throw DeviceException(
        DeviceFailureKind.notRegistered,
        'Device $id is not registered',
        deviceId: id,
      );
    }
    return entry;
  }

  void _requireCapability(_Entry entry, DeviceCapability capability) {
    if (!entry.capabilities.contains(capability)) {
      throw DeviceException(
        DeviceFailureKind.unsupportedCapability,
        '${entry.identity.id} does not support ${capability.name}',
        deviceId: entry.identity.id,
      );
    }
  }

  (DeviceAdapter, T) _adapterFor<T extends Object>(
    _Entry entry,
    Set<DeviceState> allowed,
    String what,
  ) {
    final state = entry.machine.state;
    if (!allowed.contains(state)) {
      throw DeviceException(
        DeviceFailureKind.invalidState,
        'Cannot $what while the device is ${state.name}',
        deviceId: entry.identity.id,
      );
    }
    final adapter = entry.adapter;
    if (adapter == null || adapter is! T) {
      throw DeviceException(
        DeviceFailureKind.unsupportedCapability,
        '${entry.identity.id} cannot $what',
        deviceId: entry.identity.id,
      );
    }
    return (adapter, adapter as T);
  }

  void _noteFailure(_Entry entry, String what, String message) {
    if (_isGone(entry)) return;
    entry.lastError = message;
    _log(entry, '$what failed: $message');
    _emit(entry);
  }

  DeviceException _asDeviceException(_Entry entry, Object err) {
    if (err is DeviceException) {
      return err.deviceId != null
          ? err
          : DeviceException(
              err.kind,
              err.message,
              deviceId: entry.identity.id,
              cause: err.cause,
            );
    }
    return DeviceException(
      DeviceFailureKind.backendError,
      'Backend failure: $err',
      deviceId: entry.identity.id,
      cause: err,
    );
  }

  DeviceState _stateForFailure(DeviceFailureKind kind) {
    switch (kind) {
      case DeviceFailureKind.sdkMissing:
        return DeviceState.sdkMissing;
      case DeviceFailureKind.driverMissing:
        return DeviceState.driverMissing;
      case DeviceFailureKind.busyElsewhere:
      case DeviceFailureKind.sessionRestricted:
      case DeviceFailureKind.driverConflict:
      case DeviceFailureKind.ownershipConflict:
      case DeviceFailureKind.alreadyOpen:
        return DeviceState.busy;
      case DeviceFailureKind.cancelled:
        return DeviceState.disconnected;
      default:
        return DeviceState.error;
    }
  }

  DeviceException _unavailable(_Entry entry) {
    final state = entry.machine.state;
    final kind = switch (state) {
      DeviceState.sdkMissing => DeviceFailureKind.sdkMissing,
      DeviceState.driverMissing => DeviceFailureKind.driverMissing,
      DeviceState.unsupported => DeviceFailureKind.unsupportedDevice,
      _ => DeviceFailureKind.backendError,
    };
    return DeviceException(
      kind,
      entry.lastError ?? 'Device is ${state.name}',
      deviceId: entry.identity.id,
    );
  }

  void _ensureCurrent(_Entry entry, int epoch) {
    if (_isGone(entry) || epoch != entry.epoch) {
      throw DeviceException(
        DeviceFailureKind.cancelled,
        'Operation cancelled',
        deviceId: entry.identity.id,
      );
    }
  }

  bool _isGone(_Entry entry) => entry.removed || _disposed;

  void _refresh(_Entry entry) {
    const refreshable = {
      DeviceState.discovered,
      DeviceState.sdkMissing,
      DeviceState.driverMissing,
      DeviceState.unsupported,
      DeviceState.ready,
    };
    final current = entry.machine.state;
    if (!refreshable.contains(current)) return;
    final selection = backends.select(entry.identity);
    entry.registration = selection.registration;
    entry.capabilities =
        selection.registration?.capabilities ?? const <DeviceCapability>{};
    if (selection.state != DeviceState.ready) {
      entry.lastError = selection.message;
    } else if (current != DeviceState.ready &&
        current != DeviceState.discovered) {
      entry.lastError = null;
    }
    if (current != selection.state) {
      if (current != DeviceState.discovered) {
        _move(entry, DeviceState.discovered);
      }
      _move(entry, selection.state);
    } else {
      _emit(entry);
    }
  }

  /// Moves the state machine. An invalid move from an asynchronous callback
  /// is logged and ignored instead of crashing an unawaited future.
  bool _move(_Entry entry, DeviceState next) {
    if (entry.removed || entry.machine.isDisposed) return false;
    final current = entry.machine.state;
    if (current == next) return false;
    if (!DeviceStateMachine.canTransition(current, next)) {
      _log(entry, 'ignored invalid move ${current.name} -> ${next.name}');
      return false;
    }
    entry.machine.transition(next);
    _log(entry, 'state -> ${next.name}');
    _emit(entry);
    return true;
  }

  void _log(_Entry entry, String message) {
    entry.log.add('${_clock().toIso8601String()} $message');
    if (entry.log.length > _maxLogLines) {
      entry.log.removeRange(0, entry.log.length - _maxLogLines);
    }
  }

  void _emit(_Entry entry) {
    if (entry.removed || _changes.isClosed) return;
    _changes.add(_snapshot(entry));
  }

  DeviceSnapshot _snapshot(_Entry entry) => DeviceSnapshot(
    identity: entry.identity,
    backendId: entry.registration?.backendId,
    capabilities: Set<DeviceCapability>.unmodifiable(entry.capabilities),
    state: entry.machine.state,
    lastConnectedAt: entry.lastConnectedAt,
    lastError: entry.lastError,
    configuration: entry.configuration,
  );
}
