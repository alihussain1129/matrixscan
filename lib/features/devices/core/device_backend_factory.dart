import 'device_adapter.dart';
import 'device_exception.dart';
import 'device_models.dart';
import 'device_state_machine.dart';

enum BackendAvailabilityStatus { available, sdkMissing, driverMissing }

/// Whether a backend's SDK or driver is present on this machine.
class BackendAvailability {
  const BackendAvailability.available()
    : status = BackendAvailabilityStatus.available,
      message = '';
  const BackendAvailability.sdkMissing(this.message)
    : status = BackendAvailabilityStatus.sdkMissing;
  const BackendAvailability.driverMissing(this.message)
    : status = BackendAvailabilityStatus.driverMissing;

  final BackendAvailabilityStatus status;
  final String message;
}

/// One way of talking to a family of devices.
class BackendRegistration {
  const BackendRegistration({
    required this.backendId,
    required this.capabilities,
    required this.supports,
    required this.create,
    this.availability,
    this.priority = 0,
    this.supportedAccessModes = const {AccessMode.exclusive},
  });

  final String backendId;

  /// What devices served by this backend can do; the hub gates on this.
  final Set<DeviceCapability> capabilities;
  final bool Function(DeviceIdentity identity) supports;
  final DeviceAdapter Function(
    DeviceIdentity identity,
    DeviceConfiguration configuration,
  )
  create;

  /// Null means always available.
  final BackendAvailability Function()? availability;

  /// Higher wins when several backends support the same device.
  final int priority;
  final Set<AccessMode> supportedAccessModes;
}

class BackendSelection {
  const BackendSelection({
    required this.state,
    required this.message,
    this.registration,
  });

  /// ready, sdkMissing, driverMissing, unsupported or error.
  final DeviceState state;
  final String message;
  final BackendRegistration? registration;
}

/// Picks the backend for a device. Never pretends a missing SDK is present.
class DeviceBackendFactory {
  final Map<String, BackendRegistration> _backends = {};

  List<String> get backendIds => List.unmodifiable(_backends.keys);

  void register(BackendRegistration registration) {
    if (_backends.containsKey(registration.backendId)) {
      throw ArgumentError(
        'Backend ${registration.backendId} is already registered',
      );
    }
    _backends[registration.backendId] = registration;
  }

  bool unregister(String backendId) => _backends.remove(backendId) != null;

  BackendSelection select(DeviceIdentity identity) {
    final candidates =
        _backends.values
            .where((backend) => _supports(backend, identity))
            .toList()
          ..sort((a, b) => b.priority.compareTo(a.priority));

    if (candidates.isEmpty) {
      return BackendSelection(
        state: DeviceState.unsupported,
        message:
            'No backend supports ${identity.manufacturer} '
            '${identity.model} over ${identity.transport.name}',
      );
    }

    DeviceState? problemState;
    var problemMessage = '';
    for (final candidate in candidates) {
      try {
        final availability =
            candidate.availability?.call() ??
            const BackendAvailability.available();
        if (availability.status == BackendAvailabilityStatus.available) {
          return BackendSelection(
            state: DeviceState.ready,
            message: '',
            registration: candidate,
          );
        }
        if (problemState == null) {
          problemState =
              availability.status == BackendAvailabilityStatus.sdkMissing
              ? DeviceState.sdkMissing
              : DeviceState.driverMissing;
          problemMessage = availability.message;
        }
      } catch (err) {
        problemState ??= DeviceState.error;
        if (problemMessage.isEmpty) {
          problemMessage =
              'Availability check of ${candidate.backendId} failed: $err';
        }
      }
    }
    return BackendSelection(
      state: problemState ?? DeviceState.error,
      message: problemMessage,
    );
  }

  DeviceAdapter createAdapter(
    DeviceIdentity identity, [
    DeviceConfiguration? configuration,
  ]) {
    final selection = select(identity);
    final registration = selection.registration;
    if (registration == null) {
      final kind = switch (selection.state) {
        DeviceState.sdkMissing => DeviceFailureKind.sdkMissing,
        DeviceState.driverMissing => DeviceFailureKind.driverMissing,
        DeviceState.unsupported => DeviceFailureKind.unsupportedDevice,
        _ => DeviceFailureKind.backendError,
      };
      throw DeviceException(kind, selection.message, deviceId: identity.id);
    }
    return registration.create(
      identity,
      configuration ?? DeviceConfiguration.empty,
    );
  }

  static bool _supports(BackendRegistration backend, DeviceIdentity identity) {
    try {
      return backend.supports(identity);
    } catch (_) {
      return false;
    }
  }
}
