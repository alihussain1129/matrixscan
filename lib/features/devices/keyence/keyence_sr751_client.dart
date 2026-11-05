import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/message_framer.dart';

/// Connection state of the Keyence SR-751 device.
enum KeyenceConnectionStatus { disconnected, connecting, connected, error }

/// A barcode decoded and transmitted by the Keyence SR-751 reader.
class KeyenceScanResult {
  const KeyenceScanResult({
    required this.data,
    required this.timestamp,
    this.rawResponse = '',
    this.command = '',
    this.isError = false,
    this.errorMessage,
  });

  final String data;
  final DateTime timestamp;
  final String rawResponse;
  final String command;
  final bool isError;
  final String? errorMessage;

  @override
  String toString() =>
      'KeyenceScanResult(data: $data, isError: $isError, time: $timestamp)';
}

/// TCP/IP client interface for communicating with the KEYENCE SR-751 series
/// industrial code reader over Ethernet.
///
/// Incoming bytes are framed with [MessageFramer]. When [receiveTerminator] is
/// null the client accepts CR, LF or CRLF as a line ending; pass the delimiter
/// configured on the reader to switch to strict framing.
///
/// Connection recovery retries forever with exponential backoff
/// ([reconnectBaseDelay] doubling up to [reconnectMaxDelay]) until
/// [disconnect] or [dispose] is called.
class KeyenceSr751Client {
  KeyenceSr751Client({
    this.defaultHost = '192.168.100.100',
    this.defaultPort = 9004,
    List<int>? receiveTerminator,
    this.reconnectBaseDelay = const Duration(seconds: 1),
    this.reconnectMaxDelay = const Duration(seconds: 16),
  }) : host = defaultHost,
       port = defaultPort,
       _tolerantLineEndings = receiveTerminator == null,
       _framer = MessageFramer(terminator: receiveTerminator ?? const [0x0D]);

  String host;
  int port;
  final String defaultHost;
  final int defaultPort;
  final Duration reconnectBaseDelay;
  final Duration reconnectMaxDelay;

  final bool _tolerantLineEndings;
  final MessageFramer _framer;

  Socket? _socket;
  StreamSubscription<List<int>>? _socketSub;

  final _statusController =
      StreamController<KeyenceConnectionStatus>.broadcast();
  Stream<KeyenceConnectionStatus> get statusStream => _statusController.stream;

  KeyenceConnectionStatus _status = KeyenceConnectionStatus.disconnected;
  KeyenceConnectionStatus get status => _status;

  final _scanController = StreamController<KeyenceScanResult>.broadcast();
  Stream<KeyenceScanResult> get scanStream => _scanController.stream;

  String? _lastError;
  String? get lastError => _lastError;

  bool autoReconnect = true;
  int _reconnectAttempts = 0;

  /// Consecutive failed or lost connections since the last good connection.
  int get reconnectAttempts => _reconnectAttempts;

  Timer? _reconnectTimer;
  bool _explicitDisconnect = false;
  bool _disposed = false;
  int _connectGen = 0;

  void _setStatus(KeyenceConnectionStatus s, [String? error]) {
    if (_disposed) return;
    _status = s;
    _lastError = error;
    _statusController.add(s);
  }

  /// Connects to the Keyence SR-751 reader over TCP.
  Future<bool> connect({
    String? targetHost,
    int? targetPort,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_disposed) return false;
    if (targetHost != null) host = targetHost;
    if (targetPort != null) port = targetPort;

    _explicitDisconnect = false;
    _cancelReconnectTimer();
    final gen = ++_connectGen;
    await _closeSocketOnly();
    if (gen != _connectGen) return false;
    _setStatus(KeyenceConnectionStatus.connecting);

    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } catch (e) {
      if (gen != _connectGen) return false;
      debugPrint('[KEYENCE][TCP] Connection failed: $e');
      _setStatus(KeyenceConnectionStatus.error, e.toString());
      _scheduleReconnect();
      return false;
    }

    if (gen != _connectGen || _disposed || _explicitDisconnect) {
      socket.destroy();
      return false;
    }

    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    _socket = socket;
    _framer.reset();
    _reconnectAttempts = 0;
    _setStatus(KeyenceConnectionStatus.connected);

    _socketSub = socket.listen(
      _onDataReceived,
      onError: (Object e) {
        debugPrint('[KEYENCE][TCP] Socket error: $e');
        _onSocketLost(socket, e.toString());
      },
      onDone: () {
        debugPrint('[KEYENCE][TCP] Socket closed by remote');
        _onSocketLost(socket, null);
      },
      cancelOnError: true,
    );
    return true;
  }

  /// Handles a lost connection once. Events from sockets that were already
  /// replaced or closed are ignored, so one drop never starts two reconnects.
  void _onSocketLost(Socket socket, String? error) {
    if (!identical(socket, _socket)) return;
    _setStatus(
      error != null
          ? KeyenceConnectionStatus.error
          : KeyenceConnectionStatus.disconnected,
      error,
    );
    unawaited(_closeSocketOnly());
    _scheduleReconnect();
  }

  Duration _nextReconnectDelay() {
    final shift = _reconnectAttempts > 21 ? 20 : _reconnectAttempts - 1;
    final micros = reconnectBaseDelay.inMicroseconds * (1 << shift);
    final cap = reconnectMaxDelay.inMicroseconds;
    return Duration(microseconds: micros > cap ? cap : micros);
  }

  void _scheduleReconnect() {
    if (_disposed || _explicitDisconnect || !autoReconnect) return;
    if (_reconnectTimer != null) return;
    _reconnectAttempts++;
    final delay = _nextReconnectDelay();
    debugPrint(
      '[KEYENCE][TCP] Reconnect attempt $_reconnectAttempts in ${delay.inMilliseconds} ms...',
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_disposed ||
          _explicitDisconnect ||
          _status == KeyenceConnectionStatus.connected) {
        return;
      }
      unawaited(connect());
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _closeSocketOnly() async {
    final socket = _socket;
    final sub = _socketSub;
    _socket = null;
    _socketSub = null;
    _framer.reset();
    try {
      await sub?.cancel();
    } catch (_) {}
    if (socket == null) return;
    try {
      await socket.close().timeout(const Duration(seconds: 1));
    } catch (_) {}
    socket.destroy();
  }

  /// Disconnects from the reader and stops automatic reconnection.
  Future<void> disconnect() async {
    _explicitDisconnect = true;
    _connectGen++;
    _cancelReconnectTimer();
    await _closeSocketOnly();
    if (_status != KeyenceConnectionStatus.disconnected) {
      _setStatus(KeyenceConnectionStatus.disconnected);
    }
  }

  /// Sends a raw command string to the Keyence reader, appending '\r' as required
  /// by the Keyence protocol.
  Future<bool> sendCommand(String command) async {
    final socket = _socket;
    if (socket == null || _status != KeyenceConnectionStatus.connected) {
      return false;
    }

    try {
      final formatted = command.endsWith('\r') ? command : '$command\r';
      socket.write(formatted);
      await socket.flush();
      debugPrint('[KEYENCE][TX] $command');
      return true;
    } catch (e) {
      debugPrint('[KEYENCE][TX] Send error: $e');
      _onSocketLost(socket, e.toString());
      return false;
    }
  }

  /// Sends 'LON' (Laser / Illumination ON and Trigger read).
  Future<bool> triggerRead() => sendCommand('LON');

  /// Sends 'LOFF' (Stop reading / turn illumination OFF).
  Future<bool> stopRead() => sendCommand('LOFF');

  /// Sends 'T1' (Software Trigger 1).
  Future<bool> triggerT1() => sendCommand('T1');

  /// Sends 'T2' (Software Trigger 2).
  Future<bool> triggerT2() => sendCommand('T2');

  /// Requests the SR-751 to transmit its latest CMOS frame buffer to the FTP server.
  Future<bool> requestFtpImage() => sendCommand('FTPOUT');

  /// Changes the active recipe/program bank (e.g. PRG,00 to PRG,15).
  Future<bool> switchProgram(int programIndex) {
    final prgStr = programIndex.toString().padLeft(2, '0');
    return sendCommand('PRG,$prgStr');
  }

  /// Resets error state on the reader.
  Future<bool> resetError() => sendCommand('RESET');

  /// Triggers test buzzer on the SR-751 unit.
  Future<bool> beep() => sendCommand('BEEP');

  /// Queries the reader model and firmware information.
  Future<bool> queryModel() => sendCommand('KEYENCE');

  void _onDataReceived(List<int> bytes) {
    final input = _tolerantLineEndings
        ? <int>[for (final b in bytes) b == 0x0A ? 0x0D : b]
        : bytes;

    final overflowBefore = _framer.overflowCount;
    final messages = _framer.add(input);
    if (_framer.overflowCount != overflowBefore) {
      debugPrint('[KEYENCE][RX] Discarded an over-long message');
    }

    for (final message in messages) {
      final text = utf8.decode(message, allowMalformed: true).trim();
      if (text.isNotEmpty) _handleResponse(text);
    }
  }

  void _handleResponse(String response) {
    debugPrint('[KEYENCE][RX] $response');
    if (_scanController.isClosed) return;

    // NOTE: every non-error line is still treated as a scan. Command replies
    // (OK, model string, ...) need the official reply formats before they can
    // be separated from barcode data.
    final isErr = response.startsWith('ERROR') || response == 'NG';
    final result = KeyenceScanResult(
      data: isErr ? '' : response,
      timestamp: DateTime.now(),
      rawResponse: response,
      isError: isErr,
      errorMessage: isErr ? response : null,
    );

    _scanController.add(result);
  }

  /// Stops reconnecting, closes the socket, then closes the streams.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _explicitDisconnect = true;
    _connectGen++;
    _cancelReconnectTimer();
    unawaited(
      _closeSocketOnly().whenComplete(() {
        _statusController.close();
        _scanController.close();
      }),
    );
  }
}

final keyenceSr751ClientProvider = Provider<KeyenceSr751Client>((ref) {
  final client = KeyenceSr751Client();
  ref.onDispose(client.dispose);
  return client;
});
