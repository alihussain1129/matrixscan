import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/core/device_backend_factory.dart';
import 'package:exalted/features/devices/core/device_exception.dart';
import 'package:exalted/features/devices/core/device_hub.dart';
import 'package:exalted/features/devices/core/device_models.dart';
import 'package:exalted/features/devices/core/device_state_machine.dart';
import 'package:exalted/features/devices/keyence/keyence_barcode_reader_adapter.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';
import 'package:exalted/features/devices/keyence/sr751_message_classifier.dart';

/// A stand-in reader: a loopback TCP server. This is a simulation, not the
/// real SR-751.
class _Reader {
  _Reader._(this.server);

  final ServerSocket server;
  Socket? socket;
  int connections = 0;
  int closedConnections = 0;
  final List<String> received = <String>[];

  static Future<_Reader> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final reader = _Reader._(server);
    server.listen((s) {
      reader.socket = s;
      reader.connections++;
      s.listen(
        (d) => reader.received.add(utf8.decode(d, allowMalformed: true)),
        onError: (Object _) {},
        onDone: () => reader.closedConnections++,
      );
    });
    return reader;
  }

  int get port => server.port;
  String get allReceived => received.join();
  void send(String text) => socket!.write(text);
  void dropConnection() {
    socket?.destroy();
    socket = null;
  }

  Future<void> close() async {
    socket?.destroy();
    await server.close();
  }
}

Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

KeyenceSr751Client _client(int port) => KeyenceSr751Client(
  defaultHost: '127.0.0.1',
  defaultPort: port,
  reconnectBaseDelay: const Duration(milliseconds: 30),
  reconnectMaxDelay: const Duration(milliseconds: 120),
);

KeyenceSr751ReaderAdapter _adapter(
  int port, {
  KeyenceSr751Client? client,
  Sr751ReplyProfile profile = const Sr751ReplyProfile.legacy(),
}) => KeyenceSr751ReaderAdapter(
  client ?? _client(port),
  host: '127.0.0.1',
  port: port,
  classifier: Sr751MessageClassifier(profile: profile),
);

Future<(_Reader, KeyenceSr751ReaderAdapter)> _connected({
  Sr751ReplyProfile profile = const Sr751ReplyProfile.legacy(),
}) async {
  final reader = await _Reader.start();
  addTearDown(reader.close);
  final adapter = _adapter(reader.port, profile: profile);
  addTearDown(adapter.dispose);
  await adapter.connect(CancelToken());
  await _until(() => reader.socket != null);
  return (reader, adapter);
}

void main() {
  test('a decoded line becomes one read event', () async {
    final (reader, adapter) = await _connected();
    final reads = <DeviceReadEvent>[];
    adapter.reads.listen(reads.add);
    reader.send('LOT-9924-X\r');
    await _until(() => reads.length == 1);
    expect(reads.single.data, 'LOT-9924-X');
    expect(reads.single.raw, 'LOT-9924-X');
    expect(reads.single.success, isTrue);
  });

  test('split and combined messages come out whole and in order', () async {
    final (reader, adapter) = await _connected();
    final reads = <DeviceReadEvent>[];
    adapter.reads.listen(reads.add);
    reader.send('AB');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    reader.send('C\rDEF\rGH');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    reader.send('I\r');
    await _until(() => reads.length == 3);
    expect(reads.map((r) => r.data), ['ABC', 'DEF', 'GHI']);
  });

  test('an ERROR line is a read failure, never barcode data', () async {
    final (reader, adapter) = await _connected();
    final reads = <DeviceReadEvent>[];
    adapter.reads.listen(reads.add);
    reader.send('ERROR\r');
    await _until(() => reads.length == 1);
    expect(reads.single.success, isFalse);
    expect(reads.single.data, isEmpty);
    expect(reads.single.errorMessage, 'ERROR');
  });

  test(
    'a configured acknowledgement is a command response, not a read',
    () async {
      final (reader, adapter) = await _connected(
        profile: const Sr751ReplyProfile.guideDocumented(),
      );
      final reads = <DeviceReadEvent>[];
      final responses = <DeviceCommandResponse>[];
      adapter.reads.listen(reads.add);
      adapter.commandResponses.listen(responses.add);
      expect(await adapter.sendCommand('BEEP'), isTrue);
      await _until(() => reader.allReceived.contains('BEEP\r'));
      reader.send('OK\r');
      await _until(() => responses.length == 1);
      expect(responses.single.command, 'BEEP');
      expect(responses.single.response, 'OK');
      expect(reads, isEmpty);
    },
  );

  test(
    'unknown lines are counted and escaped, and never become reads',
    () async {
      final (reader, adapter) = await _connected(
        profile: const Sr751ReplyProfile(
          name: 'strict',
          barcodePrefix: 'DATA:',
        ),
      );
      final reads = <DeviceReadEvent>[];
      adapter.reads.listen(reads.add);
      reader.send('FOO\u0001BAR\r');
      reader.send('DATA:XYZ\r');
      await _until(() => reads.length == 1);
      expect(reads.single.data, 'XYZ');
      final diag = await adapter.diagnostics();
      expect(diag['unknownMessages'], 1);
      final recent = (diag['recentUnknown']! as List<String>).single;
      expect(recent, contains('FOO'));
      expect(recent, isNot(contains('\u0001')));
    },
  );

  test('a failed connect throws and stops the client retrying', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final client = _client(port);
    final adapter = _adapter(port, client: client);
    addTearDown(adapter.dispose);
    await expectLater(
      adapter.connect(CancelToken()),
      throwsA(
        isA<DeviceException>().having(
          (e) => e.kind,
          'kind',
          DeviceFailureKind.connectionFailed,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(client.status, KeyenceConnectionStatus.disconnected);
  });

  test('a cancelled token never opens a connection', () async {
    final reader = await _Reader.start();
    addTearDown(reader.close);
    final adapter = _adapter(reader.port);
    addTearDown(adapter.dispose);
    final token = CancelToken()..cancel();
    await expectLater(adapter.connect(token), failsWithKind);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(reader.connections, 0);
  });

  test('losing and regaining the link is reported once each', () async {
    final (reader, adapter) = await _connected();
    final links = <bool>[];
    adapter.linkEvents.listen((e) => links.add(e.connected));
    reader.dropConnection();
    await _until(() => links.length >= 2, timeout: const Duration(seconds: 5));
    expect(links.take(2), [false, true]);
    expect(reader.connections, 2);
  });

  test('disconnect and dispose are idempotent', () async {
    final (reader, adapter) = await _connected();
    await adapter.disconnect();
    await adapter.disconnect();
    await _until(() => reader.closedConnections == 1);
    await adapter.dispose();
    await adapter.dispose();
    expect(reader.closedConnections, 1);
  });

  test('software trigger sends LON and fails when not connected', () async {
    final (reader, adapter) = await _connected();
    await adapter.triggerSoftware();
    await _until(() => reader.allReceived.contains('LON\r'));

    final idle = _adapter(reader.port);
    addTearDown(idle.dispose);
    await expectLater(idle.triggerSoftware(), failsWithKind);
  });

  test(
    'the hub connects, reconnects after disconnect and disposes cleanly',
    () async {
      final reader = await _Reader.start();
      addTearDown(reader.close);
      final identity = keyenceSr751Identity(
        host: '127.0.0.1',
        port: reader.port,
      );
      final backends = DeviceBackendFactory()
        ..register(
          keyenceSr751Registration(
            clientFactory: (i, c) => _client(reader.port),
          ),
        );
      final hub = DeviceHub(
        backends: backends,
        sources: [
          KeyenceConfiguredDeviceSource([identity]),
        ],
      );
      addTearDown(hub.dispose);

      await hub.discover();
      await hub.connect(identity.id);
      final diag = await hub.diagnostics(identity.id);
      expect(diag.snapshot.state, DeviceState.connected);
      expect(diag.adapter['host'], '127.0.0.1');
      expect(diag.adapter['port'], reader.port);

      await hub.disconnect(identity.id);
      await _until(() => reader.closedConnections == 1);

      await hub.connect(identity.id);
      await _until(() => reader.connections == 2);

      await hub.dispose();
      await _until(() => reader.closedConnections == 2);
    },
  );
}

final Matcher failsWithKind = throwsA(isA<DeviceException>());
