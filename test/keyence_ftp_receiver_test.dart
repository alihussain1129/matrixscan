import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/storage/image_storage_service.dart';
import 'package:exalted/features/devices/keyence/keyence_ftp_receiver.dart';

void main() {
  late Directory tempDir;
  late ImageStorageService imageStorage;
  late KeyenceFtpReceiver ftpReceiver;
  final activeSourcePorts = <int>[];

  setUp(() async {
    activeSourcePorts.clear();
    tempDir = await Directory.systemTemp.createTemp('ftp_test_');
    imageStorage = ImageStorageService(directoryProvider: () async => tempDir);
    ftpReceiver = KeyenceFtpReceiver(
      port: 0,
      imageStorage: imageStorage,
      username: 'keyence',
      password: 'keyence@exalted.local',
      activeDataConnector: (address, port, sourcePort) {
        activeSourcePorts.add(sourcePort);
        // Use an ephemeral source port in tests; the production connector
        // binds the documented active-FTP source port 20.
        return Socket.connect(address, port);
      },
    );
    await ftpReceiver.start();
  });

  tearDown(() async {
    await ftpReceiver.stop();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('FTP receiver handles full passive upload session and saves image', () async {
    final serverPort = ftpReceiver.boundPort;
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      serverPort,
    );

    final lineController = StreamController<String>.broadcast();
    final buffer = StringBuffer();

    socket.listen((data) {
      buffer.write(utf8.decode(data));
      final text = buffer.toString();
      if (text.contains('\n')) {
        final lines = text.split(RegExp(r'\r?\n'));
        buffer.clear();
        if (!text.endsWith('\n')) {
          buffer.write(lines.last);
          lines.removeLast();
        }
        for (final l in lines) {
          if (l.isNotEmpty) lineController.add(l);
        }
      }
    });

    Future<String> waitForLineStartingWith(String prefix) async {
      return lineController.stream
          .firstWhere((line) => line.startsWith(prefix))
          .timeout(const Duration(seconds: 4));
    }

    // Read banner
    await waitForLineStartingWith('220');

    // USER
    socket.write('USER keyence\r\n');
    await waitForLineStartingWith('331');

    // PASS
    socket.write('PASS keyence@exalted.local\r\n');
    await waitForLineStartingWith('230');

    // TYPE I
    socket.write('TYPE I\r\n');
    await waitForLineStartingWith('200');

    // PASV
    socket.write('PASV\r\n');
    final pasvResp = await waitForLineStartingWith('227');

    // Extract passive IP & Port from '227 Entering Passive Mode (127,0,0,1,p1,p2)'
    final match = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)')
        .firstMatch(pasvResp);
    expect(match, isNotNull);
    final ip =
        '${match!.group(1)}.${match.group(2)}.${match.group(3)}.${match.group(4)}';
    final p1 = int.parse(match.group(5)!);
    final p2 = int.parse(match.group(6)!);
    final dataPort = (p1 << 8) | p2;

    // Connect to passive data port
    final dataSocket = await Socket.connect(ip, dataPort);

    // Send STOR
    socket.write('STOR CMOS_FRAME_001.JPG\r\n');
    await waitForLineStartingWith('150');

    // Send dummy image bytes over data socket
    final dummyImageBytes = Uint8List.fromList([
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      1,
      2,
      3,
      4,
      0xFF,
      0xD9,
    ]);
    dataSocket.add(dummyImageBytes);
    await dataSocket.flush();
    await dataSocket.close();

    // Wait for 226 Transfer complete
    await waitForLineStartingWith('226');

    // Check emitted event
    final receivedFiles = await Directory('${tempDir.path}/exalted_media')
        .list()
        .toList();
    expect(receivedFiles.isNotEmpty, isTrue);

    // QUIT
    socket.write('QUIT\r\n');
    await waitForLineStartingWith('221');
    await socket.close();
    await lineController.close();
  });

  test('FTP receiver accepts common client negotiation commands', () async {
    final control = await Socket.connect(
      InternetAddress.loopbackIPv4,
      ftpReceiver.boundPort,
    );
    final lines = StreamController<String>.broadcast();
    final pending = StringBuffer();
    control.listen((data) {
      pending.write(utf8.decode(data, allowMalformed: true));
      final parts = pending.toString().split(RegExp(r'\r?\n'));
      pending.clear();
      if (parts.last.isNotEmpty) pending.write(parts.removeLast());
      for (final part in parts) {
        if (part.isNotEmpty) lines.add(part);
      }
    });
    addTearDown(() async {
      await control.close();
      await lines.close();
    });
    Future<String> waitFor(String prefix) => lines.stream
        .firstWhere((line) => line.startsWith(prefix))
        .timeout(const Duration(seconds: 4));

    await waitFor('220');
    control.write('FEAT\r\n');
    await waitFor('211-Features:');
    control.write('CLNT SR-751\r\n');
    expect(await waitFor('200'), startsWith('200'));
    control.write('OPTS UTF8 ON\r\n');
    expect(await waitFor('200'), contains('UTF8'));
    control.write('USER keyence\r\n');
    await waitFor('331');
    control.write('PASS keyence@exalted.local\r\n');
    await waitFor('230');
    control.write('STRU F\r\n');
    expect(await waitFor('200'), contains('File'));
    control.write('MODE S\r\n');
    expect(await waitFor('200'), contains('Stream'));
    control.write('CWD image\r\n');
    expect(await waitFor('250'), contains('/image'));
    control.write('PWD\r\n');
    expect(await waitFor('257'), contains('/image'));
    control.write('CDUP\r\n');
    expect(await waitFor('250'), contains('Directory changed'));
    control.write('MKD image\r\n');
    expect(await waitFor('257'), contains('/image'));
    control.write('CWD ../outside\r\n');
    expect(await waitFor('550'), startsWith('550'));
    control.write('ALLO 1024\r\n');
    expect(await waitFor('202'), startsWith('202'));
  });

  test('FTP receiver accepts a same-host active PORT upload', () async {
    final activeListener = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(activeListener.close);

    final control = await Socket.connect(
      InternetAddress.loopbackIPv4,
      ftpReceiver.boundPort,
    );
    final lines = StreamController<String>.broadcast();
    final pending = StringBuffer();
    control.listen((data) {
      pending.write(utf8.decode(data, allowMalformed: true));
      final parts = pending.toString().split(RegExp(r'\r?\n'));
      pending.clear();
      if (!parts.last.isEmpty) pending.write(parts.removeLast());
      for (final part in parts) {
        if (part.isNotEmpty) lines.add(part);
      }
    });
    addTearDown(() async {
      await control.close();
      await lines.close();
    });

    Future<String> waitFor(String prefix) => lines.stream
        .firstWhere((line) => line.startsWith(prefix))
        .timeout(const Duration(seconds: 4));

    await waitFor('220');
    control.write('USER keyence\r\n');
    await waitFor('331');
    control.write('PASS keyence@exalted.local\r\n');
    await waitFor('230');
    control.write('TYPE I\r\n');
    await waitFor('200');

    final port = activeListener.port;
    final p1 = port >> 8;
    final p2 = port & 0xff;
    control.write('PORT 127,0,0,1,$p1,$p2\r\n');
    await waitFor('200 PORT');

    control.write('STOR ACTIVE_FRAME_001.JPG\r\n');
    await waitFor('150');
    final dataSocket = await activeListener.first.timeout(
      const Duration(seconds: 4),
    );
    dataSocket.add(
      Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 0xFF, 0xD9]),
    );
    await dataSocket.flush();
    await dataSocket.close();
    await waitFor('226');
    expect(activeSourcePorts, contains(20));

    final receivedFiles = await Directory('${tempDir.path}/exalted_media')
        .list()
        .toList();
    expect(receivedFiles, isNotEmpty);
  });

  test('FTP PORT rejects a different host and privileged data ports', () async {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      ftpReceiver.boundPort,
    );
    final lines = StreamController<String>.broadcast();
    final pending = StringBuffer();
    socket.listen((data) {
      pending.write(utf8.decode(data, allowMalformed: true));
      final parts = pending.toString().split(RegExp(r'\r?\n'));
      pending.clear();
      if (!parts.last.isEmpty) pending.write(parts.removeLast());
      for (final part in parts) {
        if (part.isNotEmpty) lines.add(part);
      }
    });
    addTearDown(() async {
      await socket.close();
      await lines.close();
    });
    Future<String> waitFor(String prefix) => lines.stream
        .firstWhere((line) => line.startsWith(prefix))
        .timeout(const Duration(seconds: 4));

    await waitFor('220');
    socket.write('USER keyence\r\n');
    await waitFor('331');
    socket.write('PASS keyence@exalted.local\r\n');
    await waitFor('230');

    socket.write('PORT 127,0,0,2,8,1\r\n');
    expect(await waitFor('501'), startsWith('501'));
    socket.write('PORT 127,0,0,1,0,21\r\n');
    expect(await waitFor('501'), startsWith('501'));
  });
}
