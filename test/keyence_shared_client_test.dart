import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/core/device_backend_factory.dart';
import 'package:exalted/features/devices/core/device_hub.dart';
import 'package:exalted/features/devices/keyence/keyence_barcode_reader_adapter.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';

void main() {
  test(
    'a shared client is not disposed when the hub closes its adapter',
    () async {
      // Loopback stand-in for the reader. A simulation, not a real SR-751.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      server.listen(sockets.add);
      final client = KeyenceSr751Client(
        defaultHost: '127.0.0.1',
        defaultPort: server.port,
        reconnectBaseDelay: const Duration(milliseconds: 30),
        reconnectMaxDelay: const Duration(milliseconds: 120),
      );
      addTearDown(() async {
        client.dispose();
        for (final s in sockets) {
          s.destroy();
        }
        await server.close();
      });

      final identity = keyenceSr751Identity(
        host: '127.0.0.1',
        port: server.port,
      );
      final backends = DeviceBackendFactory()
        ..register(
          keyenceSr751Registration(
            ownsClient: false,
            clientFactory: (i, c) => client,
          ),
        );
      final hub = DeviceHub(backends: backends);
      hub.register(identity);
      await hub.connect(identity.id);
      expect(client.status, KeyenceConnectionStatus.connected);
      expect(sockets.length, 1);

      await hub.dispose();
      expect(client.status, KeyenceConnectionStatus.disconnected);
      // A disposed client refuses to connect; a shared one must still work.
      expect(await client.connect(), isTrue);
    },
  );
}
