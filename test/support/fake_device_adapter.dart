import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/devices/core/device_adapter.dart';
import 'package:exalted/features/devices/core/device_backend_factory.dart';
import 'package:exalted/features/devices/core/device_exception.dart';
import 'package:exalted/features/devices/core/device_models.dart';

const Set<DeviceCapability> kFakeCapabilities = {
  DeviceCapability.continuousFrames,
  DeviceCapability.singleFrame,
  DeviceCapability.livePreview,
  DeviceCapability.softwareTrigger,
  DeviceCapability.decodedReads,
  DeviceCapability.commandResponses,
  DeviceCapability.connectionMonitoring,
  DeviceCapability.deviceInfo,
  DeviceCapability.configuration,
  DeviceCapability.diagnostics,
};

/// Controllable adapter for hub tests. By default it honours cancellation.
/// Set [ignoreCancel] to model a backend that keeps running after cancel.
class FakeAdapter
    implements
        DeviceAdapter,
        FrameSource,
        SingleFrameCapture,
        SoftwareTriggerable,
        TriggerConfigurable,
        ReadEventSource,
        CommandResponseSource,
        ConfigurableDevice {
  FakeAdapter({
    Set<DeviceCapability>? capabilities,
    this.reconnectsAutomatically = false,
    this.ignoreCancel = false,
    this.claimsCancellation = true,
  }) : capabilities = capabilities ?? kFakeCapabilities;

  @override
  final Set<DeviceCapability> capabilities;
  @override
  final bool reconnectsAutomatically;

  /// If true the fake keeps waiting for its gate after the token fires.
  final bool ignoreCancel;
  final bool claimsCancellation;

  @override
  bool get supportsCancellation => claimsCancellation;

  @override
  String get backendId => 'fake';

  final StreamController<DeviceLinkEvent> linkController =
      StreamController<DeviceLinkEvent>.broadcast();
  final StreamController<DeviceReadEvent> readController =
      StreamController<DeviceReadEvent>.broadcast();
  final StreamController<DeviceCommandResponse> commandController =
      StreamController<DeviceCommandResponse>.broadcast();
  final StreamController<DeviceFrame> frameController =
      StreamController<DeviceFrame>.broadcast();

  Completer<void>? connectGate;
  Completer<void>? startGate;
  Completer<void>? captureGate;

  /// Consumed one per connect attempt.
  final List<Object> connectFailures = [];
  bool alwaysFailConnect = false;

  /// Returned by captureFrame instead of the default frame.
  DeviceFrame? frameToReturn;

  int connectCalls = 0;
  int disconnectCalls = 0;
  int disposeCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int triggerCalls = 0;
  int framesReleased = 0;
  final List<DeviceConfiguration> applied = [];
  TriggerMode? lastTriggerMode;
  CancelToken? lastConnectToken;
  CancelToken? lastStartToken;

  /// Ordered record of what the adapter did, e.g. connect-end before dispose.
  final List<String> events = [];

  @override
  Stream<DeviceLinkEvent> get linkEvents => linkController.stream;
  @override
  Stream<DeviceReadEvent> get reads => readController.stream;
  @override
  Stream<DeviceCommandResponse> get commandResponses =>
      commandController.stream;
  @override
  Stream<DeviceFrame> get frames => frameController.stream;

  Future<void> _wait(Completer<void>? gate, CancelToken token) async {
    if (gate == null) return;
    if (ignoreCancel) {
      await gate.future;
      return;
    }
    await Future.any<void>([gate.future, token.whenCancelled]);
    if (token.isCancelled) {
      throw const DeviceException(
        DeviceFailureKind.cancelled,
        'aborted by cancellation',
      );
    }
  }

  @override
  Future<void> connect(CancelToken cancel) async {
    connectCalls++;
    lastConnectToken = cancel;
    events.add('connect-start');
    try {
      await _wait(connectGate, cancel);
      if (alwaysFailConnect) throw StateError('connection refused');
      if (connectFailures.isNotEmpty) throw connectFailures.removeAt(0);
    } finally {
      events.add('connect-end');
    }
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    events.add('disconnect');
  }

  @override
  Future<Map<String, Object?>> diagnostics() async => {'fake': true};

  @override
  Future<void> dispose() async {
    disposeCalls++;
    events.add('dispose');
  }

  @override
  Future<void> startAcquisition(CancelToken cancel) async {
    startCalls++;
    lastStartToken = cancel;
    await _wait(startGate, cancel);
  }

  @override
  Future<void> stopAcquisition() async {
    stopCalls++;
  }

  @override
  Future<DeviceFrame> captureFrame(CancelToken cancel) async {
    await _wait(captureGate, cancel);
    return frameToReturn ??
        DeviceFrame.single(
          width: 4,
          height: 2,
          format: DevicePixelFormat.luma8,
          bytes: Uint8List(8),
          timestamp: DateTime(2026, 11, 5),
          onRelease: () => framesReleased++,
        );
  }

  @override
  Future<void> triggerSoftware() async {
    triggerCalls++;
  }

  @override
  Future<void> setTriggerMode(TriggerMode mode) async {
    lastTriggerMode = mode;
  }

  @override
  Future<void> applyConfiguration(DeviceConfiguration configuration) async {
    applied.add(configuration);
  }
}

BackendRegistration fakeRegistration({
  required FakeAdapter Function(
    DeviceIdentity identity,
    DeviceConfiguration configuration,
  )
  make,
  String backendId = 'fake',
  int priority = 0,
  Set<DeviceCapability> capabilities = kFakeCapabilities,
  bool Function(DeviceIdentity identity)? supports,
  BackendAvailability Function()? availability,
  Set<AccessMode> supportedAccessModes = const {AccessMode.exclusive},
}) {
  return BackendRegistration(
    backendId: backendId,
    capabilities: capabilities,
    supports: supports ?? (_) => true,
    create: make,
    availability: availability,
    priority: priority,
    supportedAccessModes: supportedAccessModes,
  );
}

DeviceIdentity testCamera({String serial = 'SN1', String? ip}) =>
    DeviceIdentity.create(
      manufacturer: 'Acme',
      model: 'Cam 1',
      interfaceType: DeviceInterfaceType.usb,
      transport: DeviceTransport.uvc,
      serialNumber: serial,
      ipAddress: ip,
    );

DeviceIdentity testReader() => DeviceIdentity.create(
  manufacturer: 'KEYENCE',
  model: 'SR-751',
  interfaceType: DeviceInterfaceType.ethernet,
  transport: DeviceTransport.tcp,
  ipAddress: '192.168.100.100',
  port: 9004,
);

Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Matcher failsWith(DeviceFailureKind kind) =>
    throwsA(isA<DeviceException>().having((e) => e.kind, 'kind', kind));
