import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera/scanner_camera_adapter.dart';
import 'core/device_backend_factory.dart';
import 'core/device_hub.dart';
import 'keyence/keyence_barcode_reader_adapter.dart';
import 'keyence/keyence_sr751_client.dart';

/// The scanner's camera, or null until it is wired to the scanner controller.
/// Override this to enable the scanner-camera backend.
final scannerCameraPortProvider = Provider<ScannerCameraPort?>((ref) => null);

/// The single app-wide device hub.
///
/// The SR-751 backend reuses the app's shared [KeyenceSr751Client] instead of
/// opening a second connection, and never disposes it. Limit: because the
/// client is shared, only one SR-751 can be served this way.
///
/// Nothing in the UI uses the hub yet. While the KEYENCE screen connects the
/// client itself, do not also connect the same reader through the hub.
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
  final hub = DeviceHub(backends: backends);
  ref.onDispose(() => unawaited(hub.dispose()));
  return hub;
});
