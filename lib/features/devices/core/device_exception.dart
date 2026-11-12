/// Why a device operation failed.
///
/// [busyElsewhere], [sessionRestricted] and [driverConflict] must only be
/// raised by a backend that has real evidence for them. [ownershipConflict]
/// and [alreadyOpen] come from Exalted's own ownership manager.
enum DeviceFailureKind {
  notRegistered,
  invalidState,
  unsupportedCapability,
  unsupportedAccessMode,
  unsupportedDevice,
  timeout,
  cancelled,
  disposed,
  ownershipConflict,
  alreadyOpen,
  operationQuarantined,
  busyElsewhere,
  sessionRestricted,
  driverConflict,
  sdkMissing,
  driverMissing,
  deviceDisconnected,
  connectionFailed,
  backendError,
}

class DeviceException implements Exception {
  const DeviceException(this.kind, this.message, {this.deviceId, this.cause});

  final DeviceFailureKind kind;
  final String message;
  final String? deviceId;
  final Object? cause;

  @override
  String toString() =>
      'DeviceException(${kind.name}${deviceId == null ? '' : ' [$deviceId]'}): $message';
}
