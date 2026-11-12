import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/config_provider.dart';
import '../scanner/scanner_controller.dart';
import 'camera/scanner_camera_adapter.dart';
import 'core/device_backend_factory.dart';
import 'core/device_hub.dart';
import 'keyence/keyence_barcode_reader_adapter.dart';
import 'keyence/keyence_scanner_coordinator.dart';
import 'keyence/keyence_sr751_client.dart';

/// The scanner's camera, or null until it is wired to the scanner controller.
/// Override this to enable the scanner-camera backend.
final scannerCameraPortProvider = Provider<ScannerCameraPort?>((ref) => null);

/// The single app-wide device hub.
///
/// The SR-751 backend reuses the app's shared [KeyenceSr751Client] instead of
/// opening a second connection, and never disposes it.
final deviceHubProvider = Provider<DeviceHub>((ref) {
  final backends = DeviceBackendFactory();
  final port = ref.watch(scannerCameraPortProvider);
  if (port != null) backends.register(scannerCameraRegistration(port));
  final client = ref.watch(keyenceSr751ClientProvider);
  backends.register(
    keyenceSr751Registration(
      ownsClient: false,
      clientFactory: (identity, configuration) => client,
    ),
  );
  // Read once: rebuilding the hub on a config change would drop live links.
  final sc = ref.read(configProvider).scanner;
  final hub = DeviceHub(
    backends: backends,
    connectTimeout: Duration(milliseconds: sc.connectTimeoutMs),
    acquisitionTimeout: Duration(milliseconds: sc.acquisitionTimeoutMs),
    operationTimeout: Duration(milliseconds: sc.operationTimeoutMs),
    discoveryTimeout: Duration(milliseconds: sc.discoveryTimeoutMs),
    reconnectPolicy: ReconnectPolicy(
      initialDelay: Duration(milliseconds: sc.reconnectInitialDelayMs),
      maxDelay: Duration(milliseconds: sc.reconnectMaxDelayMs),
      maxAttempts: sc.reconnectMaxAttempts,
    ),
  );
  final discovery = ref.watch(keyenceScannerDiscoveryServiceProvider);
  hub.addSource(discovery);

  // Dispatch all decoded reads from any reader connected to the hub into ScannerController
  final sub = hub.readEvents.listen((hubEvent) {
    if (hubEvent.event.success && hubEvent.event.data.isNotEmpty) {
      try {
        ref
            .read(scannerControllerProvider.notifier)
            .presentIndustrialScan(
              text: hubEvent.event.data,
              format: 'Industrial Reader (${hubEvent.deviceId})',
            );
      } catch (_) {}
    }
  });

  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(hub.dispose());
  });
  return hub;
});
