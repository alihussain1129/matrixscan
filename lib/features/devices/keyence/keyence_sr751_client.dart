import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/message_framer.dart';
import '../core/reconnect_backoff.dart';

/// Connection state of the Keyence SR-751 device.
enum KeyenceConnectionStatus { disconnected, connecting, connected, error }

/// Result of an explicit KEYENCE communication handshake.
class KeyenceHandshakeResult {
  const KeyenceHandshakeResult({
    required this.success,
    this.model = '',
    this.firmwareVersion,
    this.serialNumber,
    this.rawResponse = '',
    this.connectTimeMs = 0,
    this.handshakeTimeMs = 0,
    this.totalTimeMs = 0,
    this.errorMessage,
  });

  final bool success;
  final String model;
  final String? firmwareVersion;
  final String? serialNumber;
  final String rawResponse;
  final int connectTimeMs;
  final int handshakeTimeMs;
  final int totalTimeMs;
  final String? errorMessage;

  factory KeyenceHandshakeResult.failure({
    required String errorMessage,
    int connectTimeMs = 0,
    int handshakeTimeMs = 0,
    int totalTimeMs = 0,
  }) {
    return KeyenceHandshakeResult(
      success: false,
      errorMessage: errorMessage,
      connectTimeMs: connectTimeMs,
      handshakeTimeMs: handshakeTimeMs,
      totalTimeMs: totalTimeMs,
    );
  }

  KeyenceHandshakeResult copyWith({
    bool? success,
    String? model,
    String? firmwareVersion,
    String? serialNumber,
    String? rawResponse,
    int? connectTimeMs,
    int? handshakeTimeMs,
    int? totalTimeMs,
    String? errorMessage,
  }) {
    return KeyenceHandshakeResult(
      success: success ?? this.success,
      model: model ?? this.model,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      serialNumber: serialNumber ?? this.serialNumber,
      rawResponse: rawResponse ?? this.rawResponse,
      connectTimeMs: connectTimeMs ?? this.connectTimeMs,
      handshakeTimeMs: handshakeTimeMs ?? this.handshakeTimeMs,
      totalTimeMs: totalTimeMs ?? this.totalTimeMs,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() =>
      'KeyenceHandshakeResult(success: $success, model: $model, total: ${totalTimeMs}ms)';
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

/// Turns a low-level connect failure into a message that names the real
/// transport (TCP over Ethernet, not a serial COM port) and the likely cause.
///
/// Error numbers: Linux/macOS (errno) and Windows (WSA) are both covered.
String describeKeyenceConnectionError(Object error, String host, int port) {
  final target = '$host:$port';
  if (error is TimeoutException) {
    return 'TCP connection to $target timed out. Check that the Ethernet '
        'cable is plugged in, the PC is on the same subnet as the reader, '
        'and the IP address is correct.';
  }
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    switch (code) {
      case 111: // ECONNREFUSED (Linux)
      case 61: // ECONNREFUSED (macOS)
      case 10061: // WSAECONNREFUSED
        return 'The reader at $target refused the TCP connection. The IP is '
            'reachable, but nothing is listening on port $port. Check the '
            'reader\'s Ethernet communication setting and port number.';
      case 110: // ETIMEDOUT (Linux)
      case 60: // ETIMEDOUT (macOS)
      case 10060: // WSAETIMEDOUT
        return 'TCP connection to $target timed out. Check that the Ethernet '
            'cable is plugged in, the PC is on the same subnet as the '
            'reader, and the IP address is correct.';
      case 113: // EHOSTUNREACH (Linux)
      case 65: // EHOSTUNREACH (macOS)
      case 10065: // WSAEHOSTUNREACH
        return 'No route to $host. Check the Ethernet cable and give this '
            'PC an IP address on the reader\'s subnet.';
      case 101: // ENETUNREACH (Linux)
      case 51: // ENETUNREACH (macOS)
      case 10051: // WSAENETUNREACH
        return 'Network unreachable for $host. The Ethernet link is down or '
            'this PC has no address on the reader\'s subnet.';
      case 104: // ECONNRESET (Linux)
      case 54: // ECONNRESET (macOS)
      case 10054: // WSAECONNRESET
        return 'The reader at $target reset the connection. Another client '
            'may already be connected to it.';
    }
    return 'TCP connection to $target failed: ${error.message}'
        '${error.osError == null ? '' : ' (${error.osError})'}';
  }
  return 'TCP connection to $target failed: $error';
}

/// A local IPv4 address and the interface that owns it.
class LocalIpv4Address {
  const LocalIpv4Address(this.interfaceName, this.address);
  final String interfaceName;
  final String address;
}

Future<List<LocalIpv4Address>> _listLocalIpv4Addresses() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  return [
    for (final iface in interfaces)
      for (final addr in iface.addresses)
        LocalIpv4Address(iface.name, addr.address),
  ];
}

/// True for failures that mean the SYN never got an answer (timeout, no route,
/// network unreachable), as opposed to a refusal from a reachable host.
bool isKeyenceReachabilityFailure(Object error) {
  if (error is TimeoutException) return true;
  if (error is SocketException) {
    switch (error.osError?.errorCode) {
      case 110: // ETIMEDOUT (Linux)
      case 60: // ETIMEDOUT (macOS)
      case 10060: // WSAETIMEDOUT
      case 113: // EHOSTUNREACH (Linux)
      case 65: // EHOSTUNREACH (macOS)
      case 10065: // WSAEHOSTUNREACH
      case 101: // ENETUNREACH (Linux)
      case 51: // ENETUNREACH (macOS)
      case 10051: // WSAENETUNREACH
        return true;
    }
  }
  return false;
}

/// Explains a likely local-addressing cause of a connect timeout.
///
/// The SR-750 factory network is 192.168.100.100 / 255.255.255.0. A PC with no
/// IPv4 address in the same /24 sends the SYN to its default gateway (or
/// nowhere), so the reader never sees it and no ARP entry ever appears. Dart
/// exposes no interface prefix length, so this compares the first three
/// octets, which matches the reader's documented factory mask. Returns null
/// when a local address shares the target's /24, when [host] is not an IPv4
/// literal, or when the interfaces cannot be listed. It never changes any
/// network setting.
Future<String?> describeKeyenceLocalSubnetMismatch(
  String host, {
  Future<List<LocalIpv4Address>> Function()? listAddresses,
}) async {
  final parsed = InternetAddress.tryParse(host);
  if (parsed == null || parsed.type != InternetAddressType.IPv4) return null;
  final targetParts = parsed.address.split('.');
  if (targetParts.length != 4) return null;
  final targetPrefix = targetParts.take(3).join('.');

  final List<LocalIpv4Address> local;
  try {
    local = await (listAddresses ?? _listLocalIpv4Addresses)();
  } catch (_) {
    return null;
  }
  final sameSubnet = local.any(
    (a) => a.address.split('.').take(3).join('.') == targetPrefix,
  );
  if (sameSubnet) return null;
  final found = local.isEmpty
      ? 'no active IPv4 interface found'
      : local.map((a) => '${a.interfaceName} ${a.address}').join(', ');
  return 'This PC has no IPv4 address in $targetPrefix.0/24 ($found). The '
      'reader\'s factory subnet mask is 255.255.255.0, so the wired interface '
      'needs an unused address in $targetPrefix.0/24, or the reader must be '
      'moved to this PC\'s subnet with AutoID Network Navigator.';
}

final RegExp _keyenceModelPattern = RegExp(
  r'^SR-\d{3,4}[A-Z0-9_-]*$',
  caseSensitive: false,
);

/// TCP/IP client interface for communicating with the KEYENCE SR-751 series
/// industrial code reader over Ethernet.
///
/// Incoming bytes are framed with [MessageFramer]. When [receiveTerminator] is
/// null the client accepts CR, LF or CRLF as a line ending; pass the delimiter
/// configured on the reader to switch to strict framing.
///
/// Connection recovery retries forever with exponential backoff
/// ([reconnectBaseDelay] doubling up to [reconnectMaxDelay], optionally
/// shortened by up to [reconnectJitter]) until [disconnect] or [dispose] is
/// called. A connection that drops again within [stableConnectionThreshold]
/// does not reset the backoff, so a reader that accepts and immediately closes
/// connections cannot cause a fast reconnect loop.
///
/// The timer, clock, socket opener and random source can be injected so the
/// reconnect behaviour can be tested deterministically.
class KeyenceSr751Client {
  KeyenceSr751Client({
    this.defaultHost = '192.168.100.100',
    this.defaultPort = 9004,
    this.handshakeCommand = 'KEYENCE',
    this.verifyIdentityOnConnect = false,
    this.allowedCommands,
    List<int>? receiveTerminator,
    this.reconnectBaseDelay = const Duration(seconds: 1),
    this.reconnectMaxDelay = const Duration(seconds: 16),
    this.reconnectJitter = 0,
    this.stableConnectionThreshold = const Duration(seconds: 10),
    Random? random,
    DateTime Function()? clock,
    Timer Function(Duration delay, void Function() callback)? timerFactory,
    Future<Socket> Function(String host, int port, Duration timeout)?
    socketFactory,
    Future<List<LocalIpv4Address>> Function()? localAddressLister,
  }) : host = defaultHost,
       port = defaultPort,
       _tolerantLineEndings = receiveTerminator == null,
       _framer = MessageFramer(terminator: receiveTerminator ?? const [0x0D]),
       _backoff = ReconnectBackoff(
         baseDelay: reconnectBaseDelay,
         maxDelay: reconnectMaxDelay,
         jitter: reconnectJitter,
         random: random,
       ),
       _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new,
       _localAddressLister = localAddressLister,
       _socketFactory =
           socketFactory ??
           ((host, port, timeout) =>
               Socket.connect(host, port, timeout: timeout));

  String host;
  int port;
  final String defaultHost;
  final int defaultPort;

  /// Documented SR-750/SR-751 model-identification command.
  /// The manual specifies the response as `OK, KEYENCE, SR-***, version`.
  final String handshakeCommand;

  /// Whether normal app connections must verify identity before
  /// being considered connected. Independent of command permissions.
  final bool verifyIdentityOnConnect;

  /// Command names this client may send (upper case, without arguments).
  /// null = no restriction. An empty set sends nothing (listen-only).
  /// When a set is supplied, each allowed command must match exactly; command
  /// arguments are rejected to keep the allow-list narrow.
  final Set<String>? allowedCommands;

  /// Names of commands refused by [allowedCommands] (first 50), for diagnostics.
  final List<String> blockedCommands = <String>[];

  /// True when the handshake command is permitted by the command allow-list.
  /// This does not mean identity verification is mandatory on connect.
  bool get canHandshake =>
      allowedCommands == null ||
      allowedCommands!.contains(_commandName(handshakeCommand));

  static String _commandName(String command) =>
      command.trim().split(',').first.trim().toUpperCase();
  final Duration reconnectBaseDelay;
  final Duration reconnectMaxDelay;

  /// Fraction (0..1) by which each reconnect delay may be randomly shortened.
  final double reconnectJitter;

  /// A connection must stay up this long before it counts as healthy and the
  /// backoff penalty from earlier quick drops is forgotten.
  final Duration stableConnectionThreshold;

  final ReconnectBackoff _backoff;
  final DateTime Function() _clock;
  final Timer Function(Duration delay, void Function() callback) _timerFactory;
  final Future<Socket> Function(String host, int port, Duration timeout)
  _socketFactory;
  final Future<List<LocalIpv4Address>> Function()? _localAddressLister;
  DateTime? _connectedAt;
  int _flapPenalty = 0;

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

  Completer<String>? _pendingQueryCompleter;
  String? _pendingUnexpectedQueryResponse;

  int _lastConnectTimeMs = 0;
  int get lastConnectTimeMs => _lastConnectTimeMs;

  int _lastHandshakeTimeMs = 0;
  int get lastHandshakeTimeMs => _lastHandshakeTimeMs;

  int _lastTotalConnectionTimeMs = 0;
  int get lastTotalConnectionTimeMs => _lastTotalConnectionTimeMs;

  String? _detectedModel;
  String? get detectedModel => _detectedModel;

  String? _detectedFirmware;
  String? get detectedFirmware => _detectedFirmware;

  String? _detectedSerial;
  String? get detectedSerial => _detectedSerial;

  Timer? _reconnectTimer;
  bool _explicitDisconnect = false;
  bool _disposed = false;
  bool _verificationRequired = false;
  int _connectGen = 0;

  /// True between "TCP socket open" and "reader answered the handshake". The
  /// public status stays `connecting` during this time.
  bool _awaitingVerification = false;

  bool get _canSend =>
      _socket != null &&
      (_status == KeyenceConnectionStatus.connected || _awaitingVerification);

  void _setStatus(KeyenceConnectionStatus s, [String? error]) {
    if (_disposed) return;
    // Listeners are notified once per real change, not once per call.
    if (s == _status && error == _lastError) return;
    _status = s;
    _lastError = error;
    _statusController.add(s);
  }

  /// Connects to the Keyence SR-751 reader over TCP.
  ///
  /// With [verifyPending] the status is left at `connecting` after the socket
  /// opens, so callers only see `connected` once [connectAndVerify] has
  /// confirmed that the reader answers.
  Future<bool> connect({
    String? targetHost,
    int? targetPort,
    Duration timeout = const Duration(seconds: 4),
    bool verifyPending = false,
  }) async {
    if (_disposed) return false;
    _awaitingVerification = false;
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
      socket = await _socketFactory(host, port, timeout);
    } catch (e) {
      if (gen != _connectGen) return false;
      debugPrint('[KEYENCE][TCP] Connection failed: $e');
      var message = describeKeyenceConnectionError(e, host, port);
      if (isKeyenceReachabilityFailure(e)) {
        final hint = await describeKeyenceLocalSubnetMismatch(
          host,
          listAddresses: _localAddressLister,
        );
        if (gen != _connectGen) return false;
        if (hint != null) message = '$message $hint';
      }
      _setStatus(KeyenceConnectionStatus.error, message);
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
    _connectedAt = _clock();
    final pendingVerification = verifyPending || _verificationRequired;
    _awaitingVerification = pendingVerification;
    if (!pendingVerification) {
      _setStatus(KeyenceConnectionStatus.connected);
    }

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
    _awaitingVerification = false;
    final connectedAt = _connectedAt;
    _connectedAt = null;
    if (connectedAt != null &&
        _clock().difference(connectedAt) >= stableConnectionThreshold) {
      _flapPenalty = 0;
    } else {
      _flapPenalty++;
    }
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
    // Quick drops after a successful connect keep growing the delay even
    // though [_reconnectAttempts] was reset by that connect.
    return _backoff.delayFor(_reconnectAttempts + _flapPenalty);
  }

  void _scheduleReconnect() {
    if (_disposed || _explicitDisconnect || !autoReconnect) return;
    if (_reconnectTimer != null) return;
    _reconnectAttempts++;
    final delay = _nextReconnectDelay();
    debugPrint(
      '[KEYENCE][TCP] Reconnect attempt $_reconnectAttempts in ${delay.inMilliseconds} ms...',
    );
    _reconnectTimer = _timerFactory(delay, () {
      _reconnectTimer = null;
      if (_disposed ||
          _explicitDisconnect ||
          _status == KeyenceConnectionStatus.connected) {
        return;
      }
      if (_verificationRequired) {
        unawaited(connectAndVerify(targetHost: host, targetPort: port));
      } else {
        unawaited(connect());
      }
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _closeSocketOnly() async {
    final pending = _pendingQueryCompleter;
    _pendingQueryCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(Exception('Socket closed'));
    }
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
    _verificationRequired = false;
    _awaitingVerification = false;
    _connectGen++;
    _cancelReconnectTimer();
    _flapPenalty = 0;
    _connectedAt = null;
    await _closeSocketOnly();
    if (_status != KeyenceConnectionStatus.disconnected) {
      _setStatus(KeyenceConnectionStatus.disconnected);
    }
  }

  /// Sends an ASCII command using the SR-750 protocol framing. The manual
  /// specifies no header and a CR command terminator by default; responses
  /// use the same framing.
  Future<bool> sendCommand(String command) async {
    final normalized = command.trim();
    // The allow-list is command-name based. Reject line breaks and control
    // bytes before checking it so an allowed command cannot smuggle a second
    // command into the same TCP write.
    if (normalized.isEmpty ||
        normalized.length > 256 ||
        normalized.contains('\r') ||
        normalized.contains('\n') ||
        normalized.codeUnits.any((b) => b < 0x20 || b > 0x7E)) {
      debugPrint('[KEYENCE][TX] BLOCKED, invalid command framing');
      return false;
    }

    final commandName = _commandName(normalized);
    final allowed = allowedCommands;
    if (allowed != null &&
        (!allowed.contains(commandName) || normalized != commandName)) {
      debugPrint(
        '[KEYENCE][TX] BLOCKED by the command allow-list: $commandName',
      );
      if (blockedCommands.length < 50) {
        blockedCommands.add(commandName);
      }
      return false;
    }
    final socket = _socket;
    if (socket == null || !_canSend) {
      return false;
    }

    try {
      socket.write('$normalized\r');
      await socket.flush();
      debugPrint('[KEYENCE][TX] $commandName');
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
  Future<bool> queryModel() => sendCommand(handshakeCommand);

  /// Connects to the Keyence reader and verifies communication with a KEYENCE handshake query.
  /// Measures elapsed time for TCP connection, handshake, and total readiness.
  Future<KeyenceHandshakeResult> connectAndVerify({
    String? targetHost,
    int? targetPort,
    Duration timeout = const Duration(seconds: 4),
    Duration handshakeTimeout = const Duration(milliseconds: 1500),
  }) async {
    _verificationRequired = true;
    final sw = Stopwatch()..start();
    final connected = await connect(
      targetHost: targetHost,
      targetPort: targetPort,
      timeout: timeout,
      verifyPending: true,
    );
    final connectTime = sw.elapsedMilliseconds;
    _lastConnectTimeMs = connectTime;

    if (!connected) {
      _lastTotalConnectionTimeMs = sw.elapsedMilliseconds;
      return KeyenceHandshakeResult.failure(
        errorMessage:
            _lastError ??
            describeKeyenceConnectionError(
              const SocketException('connection failed'),
              host,
              port,
            ),
        connectTimeMs: connectTime,
        totalTimeMs: _lastTotalConnectionTimeMs,
      );
    }

    // connect() just advanced the generation. Any later change means a
    // disconnect(), dispose() or newer connect() superseded this attempt.
    final gen = _connectGen;
    final handshakeSw = Stopwatch()..start();
    final info = await queryDeviceInfo(timeout: handshakeTimeout);
    final handshakeTime = handshakeSw.elapsedMilliseconds;
    _lastHandshakeTimeMs = handshakeTime;
    _lastTotalConnectionTimeMs = sw.elapsedMilliseconds;

    bool superseded() => gen != _connectGen || _disposed || _explicitDisconnect;

    if (superseded()) {
      // The newer owner of the connection state decides what is shown. Do not
      // overwrite it with a stale error.
      return info.success
          ? KeyenceHandshakeResult.failure(
              errorMessage: 'Connection attempt was cancelled',
              connectTimeMs: connectTime,
              handshakeTimeMs: handshakeTime,
              totalTimeMs: _lastTotalConnectionTimeMs,
            )
          : info.copyWith(
              connectTimeMs: connectTime,
              handshakeTimeMs: handshakeTime,
              totalTimeMs: _lastTotalConnectionTimeMs,
            );
    }

    if (!info.success) {
      debugPrint('[KEYENCE][HANDSHAKE] Handshake failed: ${info.errorMessage}');
      // Close this socket but do NOT call disconnect(): that marks an explicit
      // user disconnect and would stop reconnecting for good. A reader that is
      // still booting, busy, or briefly unresponsive must be retried. Count it
      // as a flap so a reader that accepts TCP but never answers backs off.
      _awaitingVerification = false;
      _connectedAt = null;
      _flapPenalty++;
      await _closeSocketOnly();
      if (!superseded()) {
        _setStatus(KeyenceConnectionStatus.error, info.errorMessage);
        _scheduleReconnect();
      }
      return info.copyWith(
        connectTimeMs: connectTime,
        handshakeTimeMs: handshakeTime,
        totalTimeMs: _lastTotalConnectionTimeMs,
      );
    }

    // Only now, with the reader's reply in hand, is the link "connected".
    _awaitingVerification = false;
    if (_socket != null) _setStatus(KeyenceConnectionStatus.connected);
    return info.copyWith(
      connectTimeMs: connectTime,
      handshakeTimeMs: handshakeTime,
      totalTimeMs: _lastTotalConnectionTimeMs,
    );
  }

  /// Queries the reader model and firmware using the KEYENCE command and awaits response.
  Future<KeyenceHandshakeResult> queryDeviceInfo({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final socket = _socket;
    if (socket == null || !_canSend) {
      return KeyenceHandshakeResult.failure(
        errorMessage: 'Scanner is not connected',
      );
    }

    if (_pendingQueryCompleter != null) {
      return KeyenceHandshakeResult.failure(
        errorMessage: 'Another reader query is already waiting for a response.',
      );
    }

    final completer = Completer<String>();
    _pendingUnexpectedQueryResponse = null;
    // Socket teardown may complete this with an error while sendCommand is
    // still flushing. Attach an error observer immediately; the original
    // future remains awaitable below and still propagates the failure.
    unawaited(completer.future.catchError((Object _) => ''));
    _pendingQueryCompleter = completer;

    final sent = await sendCommand(handshakeCommand);
    if (!sent) {
      if (identical(_pendingQueryCompleter, completer)) {
        _pendingQueryCompleter = null;
      }
      return KeyenceHandshakeResult.failure(
        errorMessage: 'Failed to transmit $handshakeCommand query',
      );
    }

    final String raw;
    try {
      raw = await completer.future.timeout(timeout);
    } catch (_) {
      if (identical(_pendingQueryCompleter, completer)) {
        _pendingQueryCompleter = null;
      }
      final unexpected = _pendingUnexpectedQueryResponse;
      _pendingUnexpectedQueryResponse = null;
      if (unexpected != null) {
        return KeyenceHandshakeResult.failure(
          errorMessage:
              'Unexpected device signature: "$unexpected". The endpoint '
              'responded to "$handshakeCommand", but did not return the '
              'documented KEYENCE identity response.',
        );
      }
      return KeyenceHandshakeResult.failure(
        errorMessage:
            'TCP connected to $host:$port, but the reader gave no reply to '
            '"$handshakeCommand" within ${timeout.inMilliseconds} ms. Check '
            'the command-port interface, port number, and documented reader '
            'command protocol.',
      );
    }

    _pendingUnexpectedQueryResponse = null;
    final trimmed = raw.trim();
    final parts = trimmed.split(',').map((part) => part.trim()).toList();
    if (parts.isNotEmpty &&
        (parts.first.toUpperCase().startsWith('ER') ||
            parts.first.toUpperCase().startsWith('ERROR'))) {
      return KeyenceHandshakeResult.failure(
        errorMessage:
            'The reader at $host:$port returned an error reply to the '
            '$handshakeCommand query and rejected it: $trimmed',
      );
    }

    // The SR-750 manual documents KEYENCE as an identity command and gives
    // this response shape: OK, KEYENCE, SR-***, main-unit-system-version.
    // Do not accept a generic TCP greeting or a bare occurrence of KEYENCE.
    final isDocumentedIdentityReply =
        parts.length == 4 &&
        parts[0].toUpperCase() == 'OK' &&
        parts[1].toUpperCase() == 'KEYENCE' &&
        _keyenceModelPattern.hasMatch(parts[2]) &&
        parts[3].isNotEmpty;
    if (!isDocumentedIdentityReply) {
      return KeyenceHandshakeResult.failure(
        errorMessage:
            'Unexpected device signature: "$trimmed". The endpoint did not return the documented KEYENCE identity response.',
      );
    }

    final model = _keyenceModelPattern.firstMatch(parts[2])!.group(0)!;
    final fw = parts[3].isEmpty ? null : parts[3];
    // The documented KEYENCE response does not include a serial number.
    const String? sn = null;

    _detectedModel = model;
    _detectedFirmware = fw;
    _detectedSerial = sn;

    return KeyenceHandshakeResult(
      success: true,
      model: model,
      firmwareVersion: fw,
      serialNumber: sn,
      rawResponse: trimmed,
    );
  }

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

    final pending = _pendingQueryCompleter;
    if (pending != null && !pending.isCompleted) {
      final parts = response.split(',').map((part) => part.trim()).toList();
      final isIdentityReply =
          parts.length == 4 &&
          parts[0].toUpperCase() == 'OK' &&
          parts[1].toUpperCase() == 'KEYENCE' &&
          _keyenceModelPattern.hasMatch(parts[2]) &&
          parts[3].isNotEmpty;
      final isIdentityError =
          parts.length >= 2 &&
          parts[0].toUpperCase() == 'ER' &&
          parts[1].toUpperCase() == 'KEYENCE';
      // A barcode or unrelated status line may arrive while the query is
      // pending. It must remain scan data and must not consume the handshake.
      if (isIdentityReply || isIdentityError) {
        pending.complete(response);
        _pendingQueryCompleter = null;
        _pendingUnexpectedQueryResponse = null;
        return;
      }

      // Retain the first non-identity line as handshake evidence, but keep
      // delivering it through the normal scan stream below.
      _pendingUnexpectedQueryResponse ??= response;
    }

    if (_scanController.isClosed) return;

    // Preserve raw protocol lines for the adapter/coordinator classifier.
    // KEYENCE `ER,...` replies are protocol errors, not decoded barcode data.
    final upper = response.toUpperCase();
    final isErr =
        upper.startsWith('ERROR') || upper == 'NG' || upper.startsWith('ER,');
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

/// Commands the app-wide client may send. These are the documented,
/// non-destructive identity/error queries and the user-invoked read trigger
/// controls. Configuration-changing and unverified commands remain blocked.
/// null = no restriction (tests only).
final keyenceAllowedCommandsProvider = Provider<Set<String>?>(
  (ref) => const <String>{'KEYENCE', 'ERRSTAT', 'LON', 'LOFF'},
);

final keyenceIdentityVerificationOnConnectProvider = Provider<bool>(
  (ref) => false,
);

final keyenceSr751ClientProvider = Provider<KeyenceSr751Client>((ref) {
  final client = KeyenceSr751Client(
    allowedCommands: ref.read(keyenceAllowedCommandsProvider),
    verifyIdentityOnConnect: ref.read(
      keyenceIdentityVerificationOnConnectProvider,
    ),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// A dedicated listen-only TCP client for Data Port 1 when it is configured
/// separately from the command port. Its empty allow-list guarantees that it
/// never sends commands to the reader.
final keyenceSr751DataClientProvider = Provider<KeyenceSr751Client>((ref) {
  final client = KeyenceSr751Client(allowedCommands: const <String>{});
  ref.onDispose(client.dispose);
  return client;
});
