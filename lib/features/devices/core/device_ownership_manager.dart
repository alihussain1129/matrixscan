import 'device_exception.dart';
import 'device_models.dart';

/// A claim on one device by one Exalted service. Release it when done.
class OwnershipLease {
  OwnershipLease._(this._manager, this.deviceId, this.ownerId, this.mode);

  final DeviceOwnershipManager _manager;
  final String deviceId;
  final String ownerId;
  final AccessMode mode;
  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _manager._release(this);
  }
}

/// Stops two Exalted services opening the same device at once.
///
/// It only knows about Exalted's own claims. It never closes another
/// program's handle and never decides a device is busy elsewhere; only a
/// backend can report that. An existing camera owner (ScannerController)
/// takes one lease per physical device, like any other service.
class DeviceOwnershipManager {
  final Map<String, List<OwnershipLease>> _leases = {};

  OwnershipLease acquire({
    required String deviceId,
    required String ownerId,
    AccessMode mode = AccessMode.exclusive,
    Set<AccessMode> supportedModes = const {AccessMode.exclusive},
  }) {
    if (!supportedModes.contains(mode)) {
      throw DeviceException(
        DeviceFailureKind.unsupportedAccessMode,
        'This device does not support ${mode.name} access',
        deviceId: deviceId,
      );
    }
    final held = _leases[deviceId] ?? const <OwnershipLease>[];
    if (held.any((lease) => lease.ownerId == ownerId)) {
      throw DeviceException(
        DeviceFailureKind.alreadyOpen,
        '$ownerId has already opened this device',
        deviceId: deviceId,
      );
    }
    if (held.isNotEmpty &&
        (mode == AccessMode.exclusive ||
            held.any((lease) => lease.mode == AccessMode.exclusive))) {
      throw DeviceException(
        DeviceFailureKind.ownershipConflict,
        'Device is already held by ${held.map((l) => l.ownerId).join(', ')}',
        deviceId: deviceId,
      );
    }
    final lease = OwnershipLease._(this, deviceId, ownerId, mode);
    _leases.putIfAbsent(deviceId, () => <OwnershipLease>[]).add(lease);
    return lease;
  }

  bool isHeld(String deviceId) => (_leases[deviceId] ?? const []).isNotEmpty;

  List<String> ownersOf(String deviceId) => [
    for (final lease in _leases[deviceId] ?? const <OwnershipLease>[])
      lease.ownerId,
  ];

  void _release(OwnershipLease lease) {
    final list = _leases[lease.deviceId];
    if (list == null) return;
    list.remove(lease);
    if (list.isEmpty) _leases.remove(lease.deviceId);
  }
}
