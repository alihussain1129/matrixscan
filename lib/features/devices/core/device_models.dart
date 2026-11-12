import 'dart:async';

export 'device_frame.dart';

import 'device_state_machine.dart';

enum DeviceInterfaceType { usb, ethernet, builtIn, other }

enum DeviceTransport { uvc, platformCamera, tcp, gigeVision, usb3Vision, other }

/// What a device can do. A device only gets the operations it lists.
enum DeviceCapability {
  // Image acquisition
  continuousFrames,
  singleFrame,
  livePreview,
  softwareTrigger,
  hardwareTrigger,
  // Decoded reader input
  decodedReads,
  readerStatus,
  commandResponses,
  // Common
  connectionMonitoring,
  deviceInfo,
  configuration,
  diagnostics,
}

enum AccessMode { exclusive, shared }

enum TriggerMode { off, software, hardware }

/// Cooperative cancellation. Backends must watch it and stop their work.
class CancelToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Normalized, stable identity of a device.
///
/// The [id] never depends on discovery order. It is built from transport,
/// manufacturer, model and the best discriminator: serial number, then
/// network address (with port), then an operating-system device id.
class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.manufacturer,
    required this.model,
    required this.interfaceType,
    required this.transport,
    this.serialNumber,
    this.firmwareVersion,
    this.ipAddress,
    this.port,
    this.systemId,
    this.displayName,
  });

  factory DeviceIdentity.create({
    required String manufacturer,
    required String model,
    required DeviceInterfaceType interfaceType,
    required DeviceTransport transport,
    String? serialNumber,
    String? firmwareVersion,
    String? ipAddress,
    int? port,
    String? systemId,
    String? displayName,
  }) {
    return DeviceIdentity(
      id: stableId(
        manufacturer: manufacturer,
        model: model,
        transport: transport,
        serialNumber: serialNumber,
        ipAddress: ipAddress,
        port: port,
        systemId: systemId,
      ),
      manufacturer: manufacturer,
      model: model,
      interfaceType: interfaceType,
      transport: transport,
      serialNumber: serialNumber,
      firmwareVersion: firmwareVersion,
      ipAddress: ipAddress,
      port: port,
      systemId: systemId,
      displayName: displayName,
    );
  }

  final String id;
  final String manufacturer;
  final String model;
  final DeviceInterfaceType interfaceType;
  final DeviceTransport transport;
  final String? serialNumber;
  final String? firmwareVersion;
  final String? ipAddress;
  final int? port;
  final String? systemId;
  final String? displayName;

  static String stableId({
    required String manufacturer,
    required String model,
    required DeviceTransport transport,
    String? serialNumber,
    String? ipAddress,
    int? port,
    String? systemId,
  }) {
    String? discriminator;
    if (_has(serialNumber)) {
      discriminator = serialNumber;
    } else if (_has(ipAddress)) {
      discriminator = port == null ? ipAddress : '$ipAddress:$port';
    } else if (_has(systemId)) {
      discriminator = systemId;
    }
    if (discriminator == null) {
      throw ArgumentError(
        'A serial number, network address or system id is required '
        'to build a stable device id',
      );
    }
    return [
      transport.name,
      manufacturer,
      model,
      discriminator,
    ].map(_slug).join(':');
  }

  static bool _has(String? value) => value != null && value.trim().isNotEmpty;

  static String _slug(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '_');

  /// Combines a repeat discovery of the same device with this record. Newer
  /// non-null details win; the id and fixed properties never change.
  DeviceIdentity mergedWith(DeviceIdentity other) {
    if (other.id != id) {
      throw ArgumentError('Cannot merge different devices ($id / ${other.id})');
    }
    final merged = DeviceIdentity(
      id: id,
      manufacturer: manufacturer,
      model: model,
      interfaceType: interfaceType,
      transport: transport,
      serialNumber: other.serialNumber ?? serialNumber,
      firmwareVersion: other.firmwareVersion ?? firmwareVersion,
      ipAddress: other.ipAddress ?? ipAddress,
      port: other.port ?? port,
      systemId: other.systemId ?? systemId,
      displayName: other.displayName ?? displayName,
    );
    return merged == this ? this : merged;
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceIdentity &&
      other.id == id &&
      other.manufacturer == manufacturer &&
      other.model == model &&
      other.interfaceType == interfaceType &&
      other.transport == transport &&
      other.serialNumber == serialNumber &&
      other.firmwareVersion == firmwareVersion &&
      other.ipAddress == ipAddress &&
      other.port == port &&
      other.systemId == systemId &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(
    id,
    manufacturer,
    model,
    interfaceType,
    transport,
    serialNumber,
    firmwareVersion,
    ipAddress,
    port,
    systemId,
    displayName,
  );

  @override
  String toString() => 'DeviceIdentity($id)';
}

/// A decoded read (or a read failure) from a code reader.
class DeviceReadEvent {
  const DeviceReadEvent({
    required this.data,
    required this.timestamp,
    this.success = true,
    this.errorMessage,
    this.raw = '',
  });

  final String data;
  final DateTime timestamp;
  final bool success;
  final String? errorMessage;
  final String raw;
}

/// A reply to a command sent to the device. Never a read result.
class DeviceCommandResponse {
  const DeviceCommandResponse({
    required this.response,
    required this.timestamp,
    this.command = '',
  });

  final String response;
  final DateTime timestamp;
  final String command;
}

/// The device link went down or came back.
class DeviceLinkEvent {
  const DeviceLinkEvent.up() : connected = true, error = null;
  const DeviceLinkEvent.down([this.error]) : connected = false;

  final bool connected;
  final String? error;
}

/// Free-form, serializable device settings. Never put secrets in here.
class DeviceConfiguration {
  DeviceConfiguration([Map<String, Object?> values = const <String, Object?>{}])
    : values = Map<String, Object?>.unmodifiable(values);

  static final DeviceConfiguration empty = DeviceConfiguration();

  final Map<String, Object?> values;

  bool get isEmpty => values.isEmpty;

  DeviceConfiguration merged(DeviceConfiguration other) =>
      DeviceConfiguration({...values, ...other.values});
}

/// Point-in-time view of a registered device, safe to hand to the UI.
class DeviceSnapshot {
  const DeviceSnapshot({
    required this.identity,
    required this.backendId,
    required this.capabilities,
    required this.state,
    required this.lastConnectedAt,
    required this.lastError,
    required this.configuration,
  });

  final DeviceIdentity identity;
  final String? backendId;
  final Set<DeviceCapability> capabilities;
  final DeviceState state;
  final DateTime? lastConnectedAt;
  final String? lastError;
  final DeviceConfiguration configuration;

  String get id => identity.id;

  bool has(DeviceCapability capability) => capabilities.contains(capability);
}

class DeviceDiagnostics {
  const DeviceDiagnostics({
    required this.snapshot,
    required this.log,
    required this.adapter,
    required this.reconnectAttempts,
  });

  final DeviceSnapshot snapshot;
  final List<String> log;
  final Map<String, Object?> adapter;
  final int reconnectAttempts;
}
