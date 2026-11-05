import 'device_models.dart';

/// What every device backend provides: link control and diagnostics.
///
/// ## Cancellation and cleanup contract
///
/// * [connect] and [FrameSource.startAcquisition] receive a [CancelToken].
///   When it is cancelled the backend must abort the underlying work (close
///   the socket, call the SDK abort, stop the native open) and make the
///   returned future complete, normally or with an error. The hub treats the
///   completion of that future as "the backend no longer uses the device".
/// * The hub never calls [disconnect] or [dispose] while one of these
///   operations is still running. It first waits for the operation to settle.
/// * If the operation does not settle within the hub's grace period, the hub
///   quarantines the adapter: it keeps the ownership lease, does NOT dispose
///   the adapter, and closes it only after the operation really finishes.
///   A backend that cannot abort at all must return false from
///   [supportsCancellation] so the hub quarantines immediately.
/// * [disconnect], [dispose] and [FrameSource.stopAcquisition] must be
///   idempotent and safe even if the matching start never ran or failed.
abstract class DeviceAdapter {
  String get backendId;

  /// Must include every capability the backend registration declares.
  Set<DeviceCapability> get capabilities;

  /// True if the backend honours the [CancelToken] of long operations.
  bool get supportsCancellation => true;

  /// True if the adapter restores its own link after a loss. The hub then only
  /// waits for [linkEvents] instead of running its own reconnect loop.
  bool get reconnectsAutomatically => false;

  /// Reports the link going down or coming back after a successful connect.
  Stream<DeviceLinkEvent> get linkEvents;

  Future<void> connect(CancelToken cancel);
  Future<void> disconnect();
  Future<Map<String, Object?>> diagnostics();
  Future<void> dispose();
}

/// Continuous image acquisition.
abstract interface class FrameSource {
  /// Frames are delivered to one consumer, which must call
  /// [DeviceFrame.release] on each.
  Stream<DeviceFrame> get frames;

  /// Must observe [cancel] (see [DeviceAdapter]).
  Future<void> startAcquisition(CancelToken cancel);

  /// Idempotent.
  Future<void> stopAcquisition();
}

abstract interface class SingleFrameCapture {
  /// The caller owns the returned frame and releases it.
  Future<DeviceFrame> captureFrame(CancelToken cancel);
}

abstract interface class SoftwareTriggerable {
  Future<void> triggerSoftware();
}

abstract interface class TriggerConfigurable {
  Future<void> setTriggerMode(TriggerMode mode);
}

/// Decoded read results only. Command replies must never appear here.
abstract interface class ReadEventSource {
  Stream<DeviceReadEvent> get reads;
}

/// Replies to commands, kept apart from read results.
abstract interface class CommandResponseSource {
  Stream<DeviceCommandResponse> get commandResponses;
}

/// Applies a change to a connected device. Receives only the changed keys.
abstract interface class ConfigurableDevice {
  Future<void> applyConfiguration(DeviceConfiguration configuration);
}

abstract interface class DeviceDiscoverySource {
  String get id;
  Future<List<DeviceIdentity>> discover();
}
