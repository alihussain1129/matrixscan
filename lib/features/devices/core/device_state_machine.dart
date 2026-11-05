import 'dart:async';

import 'device_exception.dart';

/// Lifecycle state of one registered device.
enum DeviceState {
  discovered,
  sdkMissing,
  driverMissing,
  unsupported,
  ready,
  connecting,
  connected,
  acquiring,
  busy,
  reconnecting,
  disconnected,
  error,
}

/// Enforces the valid lifecycle transitions of a device.
///
/// Single-isolate use: every transition is one synchronous step.
/// Same-state transitions are no-ops.
class DeviceStateMachine {
  DeviceStateMachine([DeviceState initial = DeviceState.discovered])
    : _state = initial;

  static const Map<DeviceState, Set<DeviceState>> _allowed = {
    DeviceState.discovered: {
      DeviceState.ready,
      DeviceState.sdkMissing,
      DeviceState.driverMissing,
      DeviceState.unsupported,
      DeviceState.error,
    },
    DeviceState.sdkMissing: {
      DeviceState.discovered,
      DeviceState.ready,
      DeviceState.unsupported,
    },
    DeviceState.driverMissing: {
      DeviceState.discovered,
      DeviceState.ready,
      DeviceState.unsupported,
    },
    DeviceState.unsupported: {DeviceState.discovered},
    DeviceState.ready: {
      DeviceState.connecting,
      DeviceState.discovered,
      DeviceState.sdkMissing,
      DeviceState.driverMissing,
      DeviceState.unsupported,
      DeviceState.error,
    },
    DeviceState.connecting: {
      DeviceState.connected,
      DeviceState.busy,
      DeviceState.disconnected,
      DeviceState.error,
      DeviceState.sdkMissing,
      DeviceState.driverMissing,
    },
    DeviceState.connected: {
      DeviceState.acquiring,
      DeviceState.busy,
      DeviceState.reconnecting,
      DeviceState.disconnected,
      DeviceState.error,
    },
    DeviceState.acquiring: {
      DeviceState.connected,
      DeviceState.busy,
      DeviceState.reconnecting,
      DeviceState.disconnected,
      DeviceState.error,
    },
    DeviceState.busy: {
      DeviceState.ready,
      DeviceState.connecting,
      DeviceState.connected,
      DeviceState.acquiring,
      DeviceState.reconnecting,
      DeviceState.disconnected,
      DeviceState.error,
    },
    DeviceState.reconnecting: {
      DeviceState.connected,
      DeviceState.busy,
      DeviceState.disconnected,
      DeviceState.error,
    },
    DeviceState.disconnected: {
      DeviceState.connecting,
      DeviceState.ready,
      DeviceState.discovered,
      DeviceState.error,
      DeviceState.sdkMissing,
      DeviceState.driverMissing,
    },
    DeviceState.error: {
      DeviceState.connecting,
      DeviceState.ready,
      DeviceState.discovered,
      DeviceState.disconnected,
      DeviceState.sdkMissing,
      DeviceState.driverMissing,
    },
  };

  static Set<DeviceState> allowedFrom(DeviceState from) =>
      _allowed[from] ?? const <DeviceState>{};

  static bool canTransition(DeviceState from, DeviceState to) =>
      allowedFrom(from).contains(to);

  DeviceState _state;
  bool _disposed = false;
  final StreamController<DeviceState> _controller =
      StreamController<DeviceState>.broadcast();

  DeviceState get state => _state;
  bool get isDisposed => _disposed;

  /// Emits every state the machine moves into.
  Stream<DeviceState> get changes => _controller.stream;

  /// Moves to [next]. Returns false if already there; throws a
  /// [DeviceException] (invalidState) for a forbidden move.
  bool transition(DeviceState next) {
    if (_disposed) {
      throw const DeviceException(
        DeviceFailureKind.disposed,
        'Device state machine is disposed',
      );
    }
    if (next == _state) return false;
    if (!canTransition(_state, next)) {
      throw DeviceException(
        DeviceFailureKind.invalidState,
        'Cannot move from ${_state.name} to ${next.name}',
      );
    }
    _state = next;
    _controller.add(next);
    return true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.close();
  }
}
