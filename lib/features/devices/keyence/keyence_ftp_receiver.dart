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

typedef ActiveFtpDataConnector = Future<Socket> Function(
  InternetAddress address,
  int port,
  int sourcePort,
);

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
    this.port = 21,
    ImageStorageService? imageStorage,
    this.username,
    this.password,
    this.maxUploadBytes = kMaxUploadBytes,
    InternetAddress? bindAddress,
    this.activeDataSourcePort = 20,
    ActiveFtpDataConnector? activeDataConnector,
  }) : _imageStorage = imageStorage ?? ImageStorageService(),
       _bindAddress = bindAddress ?? InternetAddress.anyIPv4,
       _activeDataConnector =
           activeDataConnector ??
           ((address, port, sourcePort) => Socket.connect(
             address,
             port,
             sourcePort: sourcePort,
             timeout: const Duration(seconds: 5),
           ));

  final int port;
  String? username;
  String? password;
  final int maxUploadBytes;
  final ImageStorageService _imageStorage;
  final InternetAddress _bindAddress;
  final int activeDataSourcePort;
  final ActiveFtpDataConnector _activeDataConnector;

  /// Last startup failure, suitable for diagnostics without exposing secrets.
  String? lastStartError;

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
    lastStartError = null;
    if (_isRunning) {
      if (_controlServer?.port == bindPort) return true;
      lastStartError =
          'FTP receiver is already running on port ${_controlServer?.port}. Stop it before changing the port.';
      return false;
    }

    // Fail closed: FTP has no transport encryption, so anonymous access must
    // never be an implicit fallback when credentials are missing.
    if (username == null ||
        username!.trim().isEmpty ||
        password == null ||
        password!.isEmpty) {
      lastStartError = 'A non-empty FTP username and password are required.';
      debugPrint('[KEYENCE][FTP] Startup refused: $lastStartError');
      return false;
    }

    try {
      _controlServer = await ServerSocket.bind(
        _bindAddress,
        bindPort,
        shared: true,
      );
      _isRunning = true;
      lastStartError = null;
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
      lastStartError = e.toString();
      debugPrint(
        '[KEYENCE][FTP] Failed to bind FTP server on port $bindPort: $e',
      );
      _isRunning = false;
      _controlServer = null;
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
      activeDataSourcePort: activeDataSourcePort,
      activeDataConnector: _activeDataConnector,
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
    required this.activeDataSourcePort,
    required this.activeDataConnector,
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
    'OPTS',
    'CLNT',
  };

  final Socket controlSocket;
  final String clientIp;
  final ImageStorageService imageStorage;
  final String? username;
  final String? password;
  final int maxUploadBytes;
  final int activeDataSourcePort;
  final ActiveFtpDataConnector activeDataConnector;
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
  String _virtualDirectory = '';

  ServerSocket? _passiveServer;
  Socket? _dataSocket;
  Completer<Socket>? _passiveSocketCompleter;
  InternetAddress? _activeDataAddress;
  int? _activeDataPort;
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
        controlSocket.write(
          '211-Features:\r\n'
          ' PORT\r\n'
          ' PASV\r\n'
          ' UTF8\r\n'
          '211 End\r\n',
        );
        break;

      case 'PWD':
      case 'XPWD':
        _reply(
          '257 "${_virtualDirectory.isEmpty ? '/' : '/$_virtualDirectory'}" is current directory.',
        );
        break;

      case 'CWD':
        final requested = args.replaceAll('\\', '/').trim();
        if (requested.isEmpty || requested == '.') {
          _reply('250 Directory unchanged.');
        } else if (requested == '/' || requested == '..') {
          _virtualDirectory = '';
          _reply('250 Directory changed to /.');
        } else {
          final directory = _safeVirtualDirectory(requested);
          if (directory == null) {
            _reply('550 Invalid virtual directory name.');
          } else {
            _virtualDirectory = directory;
            _reply('250 Directory changed to /$directory.');
          }
        }
        break;

      case 'CDUP':
        _virtualDirectory = '';
        _reply('250 Directory changed to /.');
        break;

      case 'MKD':
        final directory = _safeVirtualDirectory(args);
        if (directory == null) {
          _reply('550 Invalid virtual directory name.');
        } else {
          _reply('257 "/$directory" directory created.');
        }
        break;

      case 'OPTS':
        if (args.toUpperCase() == 'UTF8 ON') {
          _reply('200 UTF8 mode enabled.');
        } else {
          _reply('501 Unsupported FTP option.');
        }
        break;

      case 'CLNT':
        _reply('200 Client identification accepted.');
        break;

      case 'STRU':
        if (args.toUpperCase() == 'F') {
          _reply('200 Structure set to File.');
        } else {
          _reply('504 Only file structure is supported.');
        }
        break;

      case 'MODE':
        if (args.toUpperCase() == 'S') {
          _reply('200 Mode set to Stream.');
        } else {
          _reply('504 Only stream mode is supported.');
        }
        break;

      case 'ALLO':
        _reply('202 Allocation command not required.');
        break;

      case 'TYPE':
        final requestedType = args.toUpperCase();
        if (requestedType != 'A' && requestedType != 'I') {
          _reply('504 Only TYPE A and TYPE I are supported.');
          break;
        }
        _currentTransferType = requestedType;
        _reply('200 Type set to $_currentTransferType.');
        break;

      case 'PASV':
        await _enterPassiveMode();
        break;

      case 'PORT':
        await _enterActiveMode(args);
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

  /// Accepts the SR-750's configured remote directory as a virtual FTP
  /// directory. Uploads still go through ImageStorageService; no client path
  /// is ever used as a filesystem path.
  String? _safeVirtualDirectory(String raw) {
    var value = raw.trim().replaceAll('\\', '/');
    if (value.startsWith('/')) value = value.substring(1);
    if (value.endsWith('/')) value = value.substring(0, value.length - 1);
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        !RegExp(r'^[A-Za-z0-9._-]{1,32}$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  Future<void> _enterPassiveMode() async {
    await _closePassive();
    _activeDataAddress = null;
    _activeDataPort = null;

    try {
      final localAddress = await _passiveAddress();
      if (localAddress == null) {
        _reply(
          '425 Cannot select a passive IPv4 address. Configure a specific FTP network interface.',
        );
        return;
      }
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

  /// Accepts the standard IPv4 PORT command used by the reader's default
  /// active FTP mode. To prevent FTP bounce attacks, the advertised address
  /// must exactly match the control connection peer and the data port must be
  /// an ephemeral port (1024..65535).
  Future<void> _enterActiveMode(String args) async {
    await _closePassive();
    _activeDataAddress = null;
    _activeDataPort = null;

    final octets = args.split(',').map(int.tryParse).toList();
    if (octets.length != 6 ||
        octets.any((value) => value == null || value < 0 || value > 255)) {
      _reply('501 Invalid PORT argument.');
      return;
    }

    final values = octets.cast<int>();
    final address = InternetAddress.tryParse(values.take(4).join('.'));
    final dataPort = (values[4] << 8) | values[5];
    if (address == null ||
        address.type != InternetAddressType.IPv4 ||
        address.address != clientIp ||
        dataPort < 1024 ||
        dataPort > 65535) {
      _reply(
        '501 PORT address must match the control peer and use an ephemeral port.',
      );
      return;
    }

    _activeDataAddress = address;
    _activeDataPort = dataPort;
    _reply('200 PORT command successful.');
  }

  Future<InternetAddress?> _passiveAddress() async {
    final socketAddress = controlSocket.address;
    if (socketAddress.address != InternetAddress.anyIPv4.address) {
      return socketAddress;
    }

    final remoteAddress = InternetAddress.tryParse(clientIp);
    if (remoteAddress?.isLoopback == true) {
      // Windows may report the wildcard listener address on accepted sockets.
      // Loopback clients need a concrete PASV address rather than 0.0.0.0.
      return InternetAddress.loopbackIPv4;
    }

    final candidates = <String>{};
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    )) {
      for (final address in interface.addresses) {
        if (address.type == InternetAddressType.IPv4 &&
            !address.isLoopback &&
            !address.address.startsWith('169.254.') &&
            address.address != InternetAddress.anyIPv4.address) {
          candidates.add(address.address);
        }
      }
    }

    // With one active IPv4 interface the route is unambiguous. On hosts with
    // several interfaces, fail closed rather than advertise a wrong PASV IP;
    // selecting the interface in FTP settings makes the endpoint explicit.
    if (candidates.length == 1) {
      return InternetAddress(candidates.single);
    }
    return null;
  }

  Future<void> _receiveFile(String rawName) async {
    if (_currentTransferType != 'I') {
      _reply('504 Image uploads require TYPE I (binary mode).');
      await _closePassive();
      return;
    }
    final ext = safeUploadExtension(rawName);
    if (ext == null) {
      _reply('553 File name not allowed.');
      await _closePassive();
      return;
    }

    final completer = _passiveSocketCompleter;
    final activeAddress = _activeDataAddress;
    final activePort = _activeDataPort;
    if (completer == null && (activeAddress == null || activePort == null)) {
      _reply('425 Use PORT or PASV first.');
      return;
    }

    final fileName = rawName.split(RegExp(r'[\\/]')).last;
    _reply('150 Opening BINARY mode data connection for $fileName.');

    try {
      final Socket dataSocket;
      if (activeAddress != null && activePort != null) {
        _activeDataAddress = null;
        _activeDataPort = null;
        // The SR-750 manual lists TCP source port 20 for active FTP data.
        // Binding it is required for strict active-mode compatibility; systems
        // that cannot bind privileged ports receive a clear transfer failure.
        dataSocket = await activeDataConnector(
          activeAddress,
          activePort,
          activeDataSourcePort,
        );
        if (dataSocket.remoteAddress.address != activeAddress.address) {
          dataSocket.destroy();
          throw const SocketException('Active FTP peer address mismatch');
        }
        _dataSocket = dataSocket;
      } else {
        dataSocket = await completer!.future.timeout(
          const Duration(seconds: 5),
        );
      }

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
    _activeDataAddress = null;
    _activeDataPort = null;
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
    // Never fall back to all interfaces on a bad value.
    bindAddress:
        InternetAddress.tryParse(sc.ftpBindAddress) ??
        InternetAddress.loopbackIPv4,
  );
  ref.onDispose(server.dispose);
  return server;
});
