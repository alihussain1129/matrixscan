import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/image_storage_service.dart';

/// Event fired when an industrial camera or Keyence SR-751 uploads a CMOS frame.
class KeyenceFtpImageReceived {
  const KeyenceFtpImageReceived({
    required this.file,
    required this.fileName,
    required this.clientIp,
    required this.timestamp,
    required this.byteSize,
  });

  final File file;
  final String fileName;
  final String clientIp;
  final DateTime timestamp;
  final int byteSize;

  @override
  String toString() =>
      'KeyenceFtpImageReceived($fileName, $byteSize bytes, from $clientIp)';
}

/// Lightweight, embedded FTP server designed specifically to receive image transfers
/// from Keyence SR-751 readers and industrial optical inspection cameras.
///
/// Runs entirely in pure Dart without external dependencies.
class KeyenceFtpReceiver {
  KeyenceFtpReceiver({
    this.port = 2121,
    ImageStorageService? imageStorage,
  }) : _imageStorage = imageStorage ?? ImageStorageService();

  final int port;
  final ImageStorageService _imageStorage;

  ServerSocket? _controlServer;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// The active bound listening port of the server.
  int get boundPort => _controlServer?.port ?? port;

  final _imageStreamController =
      StreamController<KeyenceFtpImageReceived>.broadcast();
  Stream<KeyenceFtpImageReceived> get onImageReceived =>
      _imageStreamController.stream;

  /// Starts the embedded FTP receiver server.
  Future<bool> start({int? listenPort}) async {
    final bindPort = listenPort ?? port;
    if (_isRunning) return true;

    try {
      _controlServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        bindPort,
        shared: true,
      );
      _isRunning = true;
      debugPrint('[KEYENCE][FTP] Server started on port ${_controlServer!.port}');

      _controlServer!.listen(
        _handleClientConnection,
        onError: (e) {
          debugPrint('[KEYENCE][FTP] Server socket error: $e');
        },
      );
      return true;
    } catch (e) {
      debugPrint('[KEYENCE][FTP] Failed to bind FTP server on port $bindPort: $e');
      _isRunning = false;
      return false;
    }
  }

  /// Stops the FTP receiver server.
  Future<void> stop() async {
    _isRunning = false;
    await _controlServer?.close();
    _controlServer = null;
    debugPrint('[KEYENCE][FTP] Server stopped');
  }

  void _handleClientConnection(Socket clientSocket) {
    final clientIp = clientSocket.remoteAddress.address;
    debugPrint('[KEYENCE][FTP] Connection accepted from $clientIp');

    // Welcome banner
    clientSocket.write('220 Exalted Industrial FTP Ready\r\n');

    final session = _FtpSession(
      controlSocket: clientSocket,
      clientIp: clientIp,
      imageStorage: _imageStorage,
      onImageReceived: (event) => _imageStreamController.add(event),
    );

    clientSocket.listen(
      session.handleData,
      onError: (e) {
        debugPrint('[KEYENCE][FTP] Client error ($clientIp): $e');
        session.close();
      },
      onDone: () {
        debugPrint('[KEYENCE][FTP] Client disconnected ($clientIp)');
        session.close();
      },
    );
  }

  void dispose() {
    stop();
    _imageStreamController.close();
  }
}

class _FtpSession {
  _FtpSession({
    required this.controlSocket,
    required this.clientIp,
    required this.imageStorage,
    required this.onImageReceived,
  });

  final Socket controlSocket;
  final String clientIp;
  final ImageStorageService imageStorage;
  final ValueChanged<KeyenceFtpImageReceived> onImageReceived;

  final StringBuffer _buffer = StringBuffer();
  ServerSocket? _passiveServer;
  Completer<Socket>? _passiveSocketCompleter;
  String _currentTransferType = 'A'; // ASCII default, 'I' is Binary

  void handleData(List<int> bytes) {
    _buffer.write(utf8.decode(bytes, allowMalformed: true));
    final raw = _buffer.toString();

    if (raw.contains('\r\n') || raw.contains('\n')) {
      final lines = raw.split(RegExp(r'\r?\n'));
      _buffer.clear();
      if (!raw.endsWith('\n')) {
        _buffer.write(lines.last);
        lines.removeLast();
      }

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _executeCommand(trimmed);
        }
      }
    }
  }

  Future<void> _executeCommand(String commandLine) async {
    debugPrint('[KEYENCE][FTP-CMD] $commandLine');
    final spaceIdx = commandLine.indexOf(' ');
    final cmd = (spaceIdx == -1 ? commandLine : commandLine.substring(0, spaceIdx)).toUpperCase();
    final args = spaceIdx == -1 ? '' : commandLine.substring(spaceIdx + 1).trim();

    switch (cmd) {
      case 'USER':
        controlSocket.write('331 User name okay, need password.\r\n');
        break;

      case 'PASS':
        controlSocket.write('230 User logged in, proceed.\r\n');
        break;

      case 'SYST':
        controlSocket.write('215 UNIX Type: L8\r\n');
        break;

      case 'FEAT':
        controlSocket.write('211-Features:\r\n PASV\r\n UTF8\r\n211 End\r\n');
        break;

      case 'PWD':
      case 'XPWD':
        controlSocket.write('257 "/" is current directory.\r\n');
        break;

      case 'TYPE':
        _currentTransferType = args.toUpperCase();
        controlSocket.write('200 Type set to $_currentTransferType.\r\n');
        break;

      case 'PASV':
        await _enterPassiveMode();
        break;

      case 'STOR':
        await _receiveFile(args);
        break;

      case 'NOOP':
        controlSocket.write('200 OK.\r\n');
        break;

      case 'QUIT':
        controlSocket.write('221 Goodbye.\r\n');
        close();
        break;

      default:
        controlSocket.write('502 Command not implemented: $cmd\r\n');
        break;
    }
  }

  Future<void> _enterPassiveMode() async {
    await _closePassive();

    try {
      _passiveServer = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _passiveSocketCompleter = Completer<Socket>();

      _passiveServer!.listen(
        (dataSocket) {
          if (_passiveSocketCompleter != null &&
              !_passiveSocketCompleter!.isCompleted) {
            _passiveSocketCompleter!.complete(dataSocket);
          }
        },
        onError: (e) {
          if (_passiveSocketCompleter != null &&
              !_passiveSocketCompleter!.isCompleted) {
            _passiveSocketCompleter!.completeError(e);
          }
        },
      );

      final localIp = controlSocket.address.address;
      final ipParts = localIp == '0.0.0.0' ? [127, 0, 0, 1] : localIp.split('.').map(int.parse).toList();
      final port = _passiveServer!.port;
      final p1 = port >> 8;
      final p2 = port & 0xFF;

      controlSocket.write(
        '227 Entering Passive Mode (${ipParts.join(',')},$p1,$p2)\r\n',
      );
    } catch (e) {
      controlSocket.write('425 Cannot enter passive mode: $e\r\n');
    }
  }

  Future<void> _receiveFile(String fileName) async {
    if (_passiveSocketCompleter == null) {
      controlSocket.write('425 Use PASV first.\r\n');
      return;
    }

    controlSocket.write('150 Opening BINARY mode data connection for $fileName.\r\n');

    try {
      final dataSocket = await _passiveSocketCompleter!.future.timeout(
        const Duration(seconds: 5),
      );

      final chunks = <List<int>>[];
      await for (final chunk in dataSocket) {
        chunks.add(chunk);
      }
      await dataSocket.close();
      await _closePassive();

      final totalLen = chunks.fold<int>(0, (prev, c) => prev + c.length);
      final bytes = Uint8List(totalLen);
      var offset = 0;
      for (final chunk in chunks) {
        bytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      // Persist permanently via ImageStorageService
      final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
      final savedPath = await imageStorage.saveImageBytes(
        bytes,
        prefix: 'keyence_cmos',
        ext: ext,
      );

      controlSocket.write('226 Transfer complete ($totalLen bytes received).\r\n');

      final event = KeyenceFtpImageReceived(
        file: File(savedPath),
        fileName: fileName,
        clientIp: clientIp,
        timestamp: DateTime.now(),
        byteSize: totalLen,
      );

      onImageReceived(event);
      debugPrint('[KEYENCE][FTP] Stored CMOS frame: $savedPath ($totalLen bytes)');
    } catch (e) {
      debugPrint('[KEYENCE][FTP] Transfer error: $e');
      controlSocket.write('426 Connection closed; transfer aborted: $e\r\n');
      await _closePassive();
    }
  }

  Future<void> _closePassive() async {
    try {
      await _passiveServer?.close();
    } catch (_) {}
    _passiveServer = null;
    _passiveSocketCompleter = null;
  }

  void close() {
    _closePassive();
    try {
      controlSocket.close();
    } catch (_) {}
  }
}

final keyenceFtpReceiverProvider = Provider<KeyenceFtpReceiver>((ref) {
  final imageStorage = ref.watch(imageStorageServiceProvider);
  final server = KeyenceFtpReceiver(imageStorage: imageStorage);
  ref.onDispose(server.dispose);
  return server;
});
