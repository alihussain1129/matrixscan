import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connection state of the Keyence SR-751 device.
enum KeyenceConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

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
/// Implements standard Keyence command protocols (LON, LOFF, T1, T2, PRG, FTPOUT).
class KeyenceSr751Client {
  KeyenceSr751Client({
    this.defaultHost = '192.168.100.100',
    this.defaultPort = 9004,
  })  : host = defaultHost,
        port = defaultPort;

  String host;
  int port;
  final String defaultHost;
  final int defaultPort;

  Socket? _socket;
  StreamSubscription<List<int>>? _socketSub;
  final StringBuffer _receiveBuffer = StringBuffer();

  final _statusController =
      StreamController<KeyenceConnectionStatus>.broadcast();
  Stream<KeyenceConnectionStatus> get statusStream => _statusController.stream;

  KeyenceConnectionStatus _status = KeyenceConnectionStatus.disconnected;
  KeyenceConnectionStatus get status => _status;

  final _scanController = StreamController<KeyenceScanResult>.broadcast();
  Stream<KeyenceScanResult> get scanStream => _scanController.stream;

  String? _lastError;
  String? get lastError => _lastError;

  void _setStatus(KeyenceConnectionStatus s, [String? error]) {
    _status = s;
    _lastError = error;
    _statusController.add(s);
  }

  /// Connects to the Keyence SR-751 reader over TCP.
  Future<bool> connect({String? targetHost, int? targetPort, Duration timeout = const Duration(seconds: 4)}) async {
    if (targetHost != null) host = targetHost;
    if (targetPort != null) port = targetPort;

    await disconnect();
    _setStatus(KeyenceConnectionStatus.connecting);

    try {
      _socket = await Socket.connect(host, port, timeout: timeout);
      _setStatus(KeyenceConnectionStatus.connected);

      _socketSub = _socket!.listen(
        _onDataReceived,
        onError: (e) {
          debugPrint('[KEYENCE][TCP] Socket error: $e');
          _setStatus(KeyenceConnectionStatus.error, e.toString());
          disconnect();
        },
        onDone: () {
          debugPrint('[KEYENCE][TCP] Socket closed by remote');
          _setStatus(KeyenceConnectionStatus.disconnected);
          disconnect();
        },
      );
      return true;
    } catch (e) {
      debugPrint('[KEYENCE][TCP] Connection failed: $e');
      _setStatus(KeyenceConnectionStatus.error, e.toString());
      return false;
    }
  }

  /// Disconnects from the reader.
  Future<void> disconnect() async {
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _socket?.close();
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _receiveBuffer.clear();
    if (_status != KeyenceConnectionStatus.disconnected) {
      _setStatus(KeyenceConnectionStatus.disconnected);
    }
  }

  /// Sends a raw command string to the Keyence reader, appending '\r' as required
  /// by the Keyence protocol.
  Future<bool> sendCommand(String command) async {
    if (_socket == null || _status != KeyenceConnectionStatus.connected) {
      return false;
    }

    try {
      final formatted = command.endsWith('\r') ? command : '$command\r';
      _socket!.write(formatted);
      await _socket!.flush();
      debugPrint('[KEYENCE][TX] $command');
      return true;
    } catch (e) {
      debugPrint('[KEYENCE][TX] Send error: $e');
      _setStatus(KeyenceConnectionStatus.error, e.toString());
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

  void _onDataReceived(List<int> bytes) {
    final chunk = utf8.decode(bytes, allowMalformed: true);
    _receiveBuffer.write(chunk);

    final raw = _receiveBuffer.toString();
    if (raw.contains('\r') || raw.contains('\n')) {
      final lines = raw.split(RegExp(r'[\r\n]+'));
      // Keep any trailing unterminated fragment in buffer
      if (!raw.endsWith('\r') && !raw.endsWith('\n')) {
        _receiveBuffer.clear();
        _receiveBuffer.write(lines.last);
        lines.removeLast();
      } else {
        _receiveBuffer.clear();
      }

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _handleResponse(trimmed);
        }
      }
    }
  }

  void _handleResponse(String response) {
    debugPrint('[KEYENCE][RX] $response');

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

  void dispose() {
    disconnect();
    _statusController.close();
    _scanController.close();
  }
}

final keyenceSr751ClientProvider = Provider<KeyenceSr751Client>((ref) {
  final client = KeyenceSr751Client();
  ref.onDispose(client.dispose);
  return client;
});
