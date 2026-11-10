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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ftp_test_');
    imageStorage = ImageStorageService(directoryProvider: () async => tempDir);
    ftpReceiver = KeyenceFtpReceiver(
      port: 0,
      imageStorage: imageStorage,
      username: 'keyence',
      password: 'keyence@exalted.local',
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
}
