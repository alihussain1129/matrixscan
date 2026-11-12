import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A realistic TCP/IP simulator for KEYENCE SR-750 / SR-751 series readers.
///
/// Implements standard Keyence commands (KEYENCE, LON, LOFF, STAT, T1, T2,
/// BEEP, RESET, PRG, FTPOUT), response framing with '\r', and can simulate
/// packet splitting, multiple messages per TCP frame, and network drops.
class KeyenceSr751Simulator {
  KeyenceSr751Simulator._({
    required this.server,
    this.model = 'SR-751',
    this.firmware = 'V2.30',
    this.serial = '12345678',
    this.defaultBarcode = 'EXALTED-DM-99420',
  }) {
    server.listen(_onIncomingConnection);
  }

  final ServerSocket server;
  String model;
  String firmware;
  String serial;
  String defaultBarcode;

  bool simulateSplitPackets = false;
  String? nextError;

  int get port => server.port;
  InternetAddress get address => server.address;

  final List<Socket> _activeSockets = [];
  final List<String> _receivedCommands = [];
  int _connectionCount = 0;

  int get connectionCount => _connectionCount;
  List<String> get receivedCommands => List.unmodifiable(_receivedCommands);
  List<Socket> get activeSockets => List.unmodifiable(_activeSockets);

  final _commandController = StreamController<String>.broadcast();
  Stream<String> get commandStream => _commandController.stream;

  static Future<KeyenceSr751Simulator> start({
    InternetAddress? address,
    int port = 0,
    String model = 'SR-751',
    String firmware = 'V2.30',
    String serial = '12345678',
    String defaultBarcode = 'EXALTED-DM-99420',
  }) async {
    final bindAddr = address ?? InternetAddress.loopbackIPv4;
    final server = await ServerSocket.bind(bindAddr, port);
    return KeyenceSr751Simulator._(
      server: server,
      model: model,
      firmware: firmware,
      serial: serial,
      defaultBarcode: defaultBarcode,
    );
  }

  void _onIncomingConnection(Socket socket) {
    _connectionCount++;
    _activeSockets.add(socket);

    final buffer = <int>[];

    socket.listen(
      (data) {
        buffer.addAll(data);
        while (true) {
          final idx = buffer.indexOf(0x0D); // '\r'
          if (idx < 0) break;
          final lineBytes = buffer.sublist(0, idx);
          buffer.removeRange(0, idx + 1);
          final cmd = utf8.decode(lineBytes, allowMalformed: true).trim();
          if (cmd.isNotEmpty) {
            _handleCommand(socket, cmd);
          }
        }
      },
      onError: (Object _) {
        _activeSockets.remove(socket);
      },
      onDone: () {
        _activeSockets.remove(socket);
      },
    );
  }

  void _handleCommand(Socket socket, String cmd) {
    _receivedCommands.add(cmd);
    _commandController.add(cmd);

    if (cmd == 'KEYENCE') {
      _sendReply(socket, '$model,$firmware,$serial');
    } else if (cmd == 'STAT') {
      _sendReply(socket, '00');
    } else if (cmd == 'LON') {
      if (nextError != null) {
        _sendReply(socket, nextError!);
        nextError = null;
      } else {
        _sendReply(socket, defaultBarcode);
      }
    } else if (cmd == 'LOFF' ||
        cmd == 'T1' ||
        cmd == 'T2' ||
        cmd == 'BEEP' ||
        cmd == 'RESET' ||
        cmd == 'FTPOUT' ||
        cmd.startsWith('PRG')) {
      _sendReply(socket, 'OK');
    } else {
      _sendReply(socket, 'ERROR,99');
    }
  }

  void _sendReply(Socket socket, String reply) {
    final formatted = '$reply\r';
    try {
      if (simulateSplitPackets && reply.length > 3) {
        final half = reply.length ~/ 2;
        socket.add(utf8.encode(formatted.substring(0, half)));
        Timer(const Duration(milliseconds: 20), () {
          try {
            socket.add(utf8.encode(formatted.substring(half)));
          } catch (_) {}
        });
      } else {
        socket.add(utf8.encode(formatted));
      }
    } catch (_) {}
  }

  /// Sends an unsolicited barcode read to all connected clients.
  void sendBarcode(String barcode) {
    for (final s in List<Socket>.of(_activeSockets)) {
      try {
        s.add(utf8.encode('$barcode\r'));
      } catch (_) {}
    }
  }

  /// Sends multiple barcodes packed into a single TCP write.
  void sendBatchedBarcodes(List<String> barcodes) {
    final payload = barcodes.map((b) => '$b\r').join();
    for (final s in List<Socket>.of(_activeSockets)) {
      try {
        s.add(utf8.encode(payload));
      } catch (_) {}
    }
  }

  /// Sends raw data directly to connected sockets.
  void sendRaw(String data) {
    for (final s in List<Socket>.of(_activeSockets)) {
      try {
        s.add(utf8.encode(data));
      } catch (_) {}
    }
  }

  /// Disconnects all current clients without shutting down the server.
  void disconnectClients() {
    for (final s in List<Socket>.of(_activeSockets)) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _activeSockets.clear();
  }

  /// Completely stops and closes the simulator server.
  Future<void> close() async {
    disconnectClients();
    await server.close();
    await _commandController.close();
  }
}
