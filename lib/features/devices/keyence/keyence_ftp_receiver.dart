import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/image_storage_service.dart';
import '../core/message_framer.dart';
import '../core/upload_guard.dart';
import '../../../core/config/config_controller.dart';

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

/// Lightweight embedded FTP server that receives image uploads from Keyence
/// SR-751 readers and industrial cameras. Pure Dart, no external dependencies.
///
/// Security: both [username] and [password] are required. The receiver refuses
/// to start without them; anonymous login is never accepted. Uploads are limited to [maxUploadBytes] and to image file
/// extensions, and a data connection is only accepted from the same IP as the
/// control connection.
class KeyenceFtpReceiver {
  KeyenceFtpReceiver({
    this.port = 2121,
    ImageStorageService? imageStorage,
    this.username,
    this.password,
    this.maxUploadBytes = kMaxUploadBytes,
    InternetAddress? bindAddress,
  }) : _imageStorage = imageStorage ?? ImageStorageService(),
       _bindAddress = bindAddress ?? InternetAddress.anyIPv4;

  final int port;
  String? username;
  String? password;
  final int maxUploadBytes;
  final ImageStorageService _imageStorage;
  final InternetAddress _bindAddress;

  ServerSocket? _controlServer;
  final Set<_FtpSession> _sessions = <_FtpSession>{};
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// The active bound listening port of the server.
  int get boundPort => _controlServer?.port ?? port;

  final _imageStreamController =
      StreamController<KeyenceFtpImageReceived>.broadcast();
  Stream<KeyenceFtpImageReceived> get onImageReceived =>
      _imageStreamController.stream;

  /// Installs the credentials (the password comes from the OS credential
  /// vault). They cannot change while the listener is running.
  void configureCredentials({
    required String? username,
    required String? password,
  }) {
    if (_isRunning) {
      throw StateError('Stop the FTP receiver before changing credentials.');
    }
    this.username = username;
    this.password = password;
  }

  /// Starts the embedded FTP receiver server.
  Future<bool> start({int? listenPort}) async {
    final bindPort = listenPort ?? port;
    if (_isRunning) return true;

    // Fail closed: FTP has no transport encryption, so anonymous access must
    // never be an implicit fallback when credentials are missing.
    if (username == null ||
        username!.trim().isEmpty ||
        password == null ||
        password!.isEmpty) {
      debugPrint(
        '[KEYENCE][FTP] Startup refused: a non-empty username and password are required.',
      );
      return false;
    }

    try {
      _controlServer = await ServerSocket.bind(
        _bindAddress,
        bindPort,
        shared: true,
      );
      _isRunning = true;
      debugPrint(
        '[KEYENCE][FTP] Server started on port ${_controlServer!.port}',
      );

      _controlServer!.listen(
        _handleClientConnection,
        onError: (Object e) {
          debugPrint('[KEYENCE][FTP] Server socket error: $e');
        },
      );
      return true;
    } catch (e) {
      debugPrint(
        '[KEYENCE][FTP] Failed to bind FTP server on port $bindPort: $e',
      );
      _isRunning = false;
      return false;
    }
  }

  /// Stops the server and closes every active session.
  Future<void> stop() async {
    _isRunning = false;
    final server = _controlServer;
    _controlServer = null;
    await server?.close();
    for (final session in _sessions.toList()) {
      session.close();
    }
    _sessions.clear();
    debugPrint('[KEYENCE][FTP] Server stopped');
  }

  void _handleClientConnection(Socket clientSocket) {
    final clientIp = clientSocket.remoteAddress.address;
    debugPrint('[KEYENCE][FTP] Connection accepted from $clientIp');

    final session = _FtpSession(
      controlSocket: clientSocket,
      clientIp: clientIp,
      imageStorage: _imageStorage,
      username: username,
      password: password,
      maxUploadBytes: maxUploadBytes,
      onImageReceived: (event) {
        if (!_imageStreamController.isClosed) {
          _imageStreamController.add(event);
        }
      },
      onClosed: _sessions.remove,
    );
    _sessions.add(session);
    session.sendBanner();

    clientSocket.listen(
      session.handleData,
      onError: (Object e) {
        debugPrint('[KEYENCE][FTP] Client error ($clientIp): $e');
        session.close();
      },
      onDone: () {
        debugPrint('[KEYENCE][FTP] Client disconnected ($clientIp)');
        session.close();
      },
      cancelOnError: true,
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
    required this.username,
    required this.password,
    required this.maxUploadBytes,
    required this.onImageReceived,
    required this.onClosed,
  }) : _authenticated = false {
    _touch();
  }

  static const Duration _idleTimeout = Duration(minutes: 5);
  static const int _maxFailedLogins = 3;
  static const Set<String> _preAuthCommands = {
    'USER',
    'PASS',
    'QUIT',
    'NOOP',
    'SYST',
    'FEAT',
  };

  final Socket controlSocket;
  final String clientIp;
  final ImageStorageService imageStorage;
  final String? username;
  final String? password;
  final int maxUploadBytes;
  final ValueChanged<KeyenceFtpImageReceived> onImageReceived;
  final void Function(_FtpSession) onClosed;

  final MessageFramer _framer = MessageFramer(
    terminator: const [0x0A],
    maxMessageBytes: 4096,
  );
  Future<void> _queue = Future<void>.value();
  Timer? _idleTimer;
  bool _closed = false;
  bool _authenticated;
  String? _pendingUser;
  int _failedLogins = 0;

  ServerSocket? _passiveServer;
  Socket? _dataSocket;
  Completer<Socket>? _passiveSocketCompleter;
  String _currentTransferType = 'A'; // ASCII default, 'I' is Binary

  void sendBanner() => _reply('220 Exalted Industrial FTP Ready');

  void _touch() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      debugPrint('[KEYENCE][FTP] Idle timeout ($clientIp)');
      close();
    });
  }

  void _reply(String line) {
    if (_closed) return;
    try {
      controlSocket.write('$line\r\n');
    } catch (_) {}
  }

  void handleData(List<int> bytes) {
    if (_closed) return;
    _touch();

    final messages = _framer.add(bytes);
    if (_framer.overflowCount > 0) {
      _reply('500 Command line too long.');
      close();
      return;
    }

    for (final message in messages) {
      final line = utf8.decode(message, allowMalformed: true).trim();
      if (line.isEmpty) continue;
      // Commands run strictly one after another.
      _queue = _queue.then((_) => _executeCommand(line)).catchError((Object e) {
        debugPrint('[KEYENCE][FTP] Command error: $e');
      });
    }
  }

  Future<void> _executeCommand(String commandLine) async {
    if (_closed) return;
    final spaceIdx = commandLine.indexOf(' ');
    final cmd =
        (spaceIdx == -1 ? commandLine : commandLine.substring(0, spaceIdx))
            .toUpperCase();
    final args = spaceIdx == -1
        ? ''
        : commandLine.substring(spaceIdx + 1).trim();

    // Never log credentials.
    debugPrint(
      '[KEYENCE][FTP-CMD] ${cmd == 'PASS' ? 'PASS ****' : commandLine}',
    );

    if (!_authenticated && !_preAuthCommands.contains(cmd)) {
      _reply('530 Please log in with USER and PASS.');
      return;
    }

    switch (cmd) {
      case 'USER':
        _pendingUser = args;
        _reply('331 User name okay, need password.');
        break;

      case 'PASS':
        if (username != null &&
            password != null &&
            _pendingUser == username &&
            args == password) {
          _authenticated = true;
          _reply('230 User logged in, proceed.');
        } else {
          _authenticated = false;
          _pendingUser = null;
          _failedLogins++;
          debugPrint('[KEYENCE][FTP] Failed login from $clientIp');
          _reply('530 Login incorrect.');
          if (_failedLogins >= _maxFailedLogins) close();
        }
        break;

      case 'SYST':
        _reply('215 UNIX Type: L8');
        break;

      case 'FEAT':
        controlSocket.write('211-Features:\r\n PASV\r\n UTF8\r\n211 End\r\n');
        break;

      case 'PWD':
      case 'XPWD':
        _reply('257 "/" is current directory.');
        break;

      case 'TYPE':
        _currentTransferType = args.toUpperCase();
        _reply('200 Type set to $_currentTransferType.');
        break;

      case 'PASV':
        await _enterPassiveMode();
        break;

      case 'STOR':
        await _receiveFile(args);
        break;

      case 'NOOP':
        _reply('200 OK.');
        break;

      case 'QUIT':
        _reply('221 Goodbye.');
        close();
        break;

      default:
        _reply('502 Command not implemented: $cmd');
        break;
    }
  }

  Future<void> _enterPassiveMode() async {
    await _closePassive();

    try {
      final localAddress = controlSocket.address;
      final octets = localAddress.address.split('.');
      if (localAddress.type != InternetAddressType.IPv4 || octets.length != 4) {
        _reply('425 Passive mode needs an IPv4 connection.');
        return;
      }

      // Listen only on the address the client already connected to.
      final server = await ServerSocket.bind(localAddress, 0);
      final completer = Completer<Socket>();
      _passiveServer = server;
      _passiveSocketCompleter = completer;

      server.listen(
        (dataSocket) {
          // Only the control client may open the data connection, once.
          if (dataSocket.remoteAddress.address != clientIp ||
              completer.isCompleted) {
            debugPrint(
              '[KEYENCE][FTP] Rejected data connection from ${dataSocket.remoteAddress.address}',
            );
            dataSocket.destroy();
            return;
          }
          _dataSocket = dataSocket;
          completer.complete(dataSocket);
        },
        onError: (Object e) {
          debugPrint('[KEYENCE][FTP] Passive socket error: $e');
        },
      );

      final port = server.port;
      _reply(
        '227 Entering Passive Mode (${octets.join(',')},${port >> 8},${port & 0xFF})',
      );
    } catch (e) {
      debugPrint('[KEYENCE][FTP] Passive mode error: $e');
      _reply('425 Cannot enter passive mode.');
    }
  }

  Future<void> _receiveFile(String rawName) async {
    final ext = safeUploadExtension(rawName);
    if (ext == null) {
      _reply('553 File name not allowed.');
      await _closePassive();
      return;
    }

    final completer = _passiveSocketCompleter;
    if (completer == null) {
      _reply('425 Use PASV first.');
      return;
    }

    final fileName = rawName.split(RegExp(r'[\\/]')).last;
    _reply('150 Opening BINARY mode data connection for $fileName.');

    try {
      final dataSocket = await completer.future.timeout(
        const Duration(seconds: 5),
      );

      final builder = BytesBuilder();
      var total = 0;
      var tooLarge = false;
      await for (final chunk in dataSocket.timeout(
        const Duration(seconds: 30),
      )) {
        total += chunk.length;
        if (total > maxUploadBytes) {
          tooLarge = true;
          break;
        }
        builder.add(chunk);
      }

      if (tooLarge) {
        dataSocket.destroy();
        await _closePassive();
        _reply('552 Upload exceeds the $maxUploadBytes byte limit.');
        return;
      }

      try {
        await dataSocket.close();
      } catch (_) {}
      await _closePassive();

      if (total == 0) {
        _reply('550 Empty upload rejected.');
        return;
      }

      final bytes = builder.takeBytes();
      final savedPath = await imageStorage.saveImageBytes(
        bytes,
        prefix: 'keyence_cmos',
        ext: ext,
      );

      _reply('226 Transfer complete ($total bytes received).');

      onImageReceived(
        KeyenceFtpImageReceived(
          file: File(savedPath),
          fileName: fileName,
          clientIp: clientIp,
          timestamp: DateTime.now(),
          byteSize: total,
        ),
      );
      debugPrint('[KEYENCE][FTP] Stored CMOS frame: $savedPath ($total bytes)');
    } catch (e) {
      debugPrint('[KEYENCE][FTP] Transfer error: $e');
      _reply('426 Connection closed; transfer aborted.');
      await _closePassive();
    }
  }

  Future<void> _closePassive() async {
    final server = _passiveServer;
    final data = _dataSocket;
    _passiveServer = null;
    _dataSocket = null;
    _passiveSocketCompleter = null;
    try {
      await server?.close();
    } catch (_) {}
    try {
      data?.destroy();
    } catch (_) {}
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _idleTimer?.cancel();
    _closePassive();
    try {
      controlSocket.close();
    } catch (_) {}
    onClosed(this);
  }
}

final keyenceFtpReceiverProvider = Provider<KeyenceFtpReceiver>((ref) {
  final imageStorage = ref.watch(imageStorageServiceProvider);
  // Read once. Credentials are installed by the caller through
  // configureCredentials(); the password never passes through config.
  final sc = ref.read(configControllerProvider).scanner;
  final server = KeyenceFtpReceiver(
    port: sc.ftpReceiverPort,
    imageStorage: imageStorage,
    maxUploadBytes: sc.ftpMaxUploadBytes ?? kMaxUploadBytes,
    bindAddress: InternetAddress.tryParse(sc.ftpBindAddress),
  );
  ref.onDispose(server.dispose);
  return server;
});
