import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../scanner/scanner_controller.dart';
import 'keyence_commissioning_service.dart';
import 'keyence_ftp_receiver.dart';
import 'keyence_scanner_discovery_service.dart';
import 'keyence_sr751_client.dart';
import 'sr751_message_classifier.dart';
import '../../../core/config/config_controller.dart';

enum DiscoveryStatus { idle, discovering, completed }

/// State of the unified KEYENCE SR-751 scanner communication engine.
class KeyenceCoordinatorState {
  const KeyenceCoordinatorState({
    this.status = KeyenceConnectionStatus.disconnected,
    this.discoveryStatus = DiscoveryStatus.idle,
    this.discoveryMessage = '',
    this.discoveryProgress = 0.0,
    this.discoveredScanners = const [],
    this.host = '192.168.100.100',
    this.port = 9004,
    this.dataPort = 9004,
    this.dataChannelStatus = KeyenceConnectionStatus.disconnected,
    this.model = 'SR-751',
    this.firmware,
    this.serialNumber,
    this.connectTimeMs = 0,
    this.handshakeTimeMs = 0,
    this.totalConnectionTimeMs = 0,
    this.lastScan,
    this.lastScanTime,
    this.scanCount = 0,
    this.lastError,
    this.dataChannelError,
    this.autoReconnect = true,
    this.autoConnectOnStartup = true,
    this.commissioningReport,
  });

  final KeyenceConnectionStatus status;
  final DiscoveryStatus discoveryStatus;
  final String discoveryMessage;
  final double discoveryProgress;
  final List<DiscoveredKeyenceScanner> discoveredScanners;
  final String host;
  final int port;

  /// Effective Data Port 1. It equals [port] when the reader shares one port.
  final int dataPort;
  final KeyenceConnectionStatus dataChannelStatus;
  final String? dataChannelError;
  final String model;
  final String? firmware;
  final String? serialNumber;
  final int connectTimeMs;
  final int handshakeTimeMs;
  final int totalConnectionTimeMs;
  final String? lastScan;
  final DateTime? lastScanTime;
  final int scanCount;
  final String? lastError;
  final bool autoReconnect;
  final bool autoConnectOnStartup;
  final CommissioningReport? commissioningReport;

  bool get isConnected => status == KeyenceConnectionStatus.connected;
  bool get isConnecting => status == KeyenceConnectionStatus.connecting;
  bool get dataChannelConnected => dataPort == port
      ? isConnected
      : dataChannelStatus == KeyenceConnectionStatus.connected;
  bool get isDiscovering => discoveryStatus == DiscoveryStatus.discovering;

  KeyenceCoordinatorState copyWith({
    KeyenceConnectionStatus? status,
    DiscoveryStatus? discoveryStatus,
    String? discoveryMessage,
    double? discoveryProgress,
    List<DiscoveredKeyenceScanner>? discoveredScanners,
    String? host,
    int? port,
    int? dataPort,
    KeyenceConnectionStatus? dataChannelStatus,
    String? dataChannelError,
    bool clearDataChannelError = false,
    String? model,
    String? firmware,
    bool clearFirmware = false,
    String? serialNumber,
    bool clearSerial = false,
    int? connectTimeMs,
    int? handshakeTimeMs,
    int? totalConnectionTimeMs,
    String? lastScan,
    DateTime? lastScanTime,
    int? scanCount,
    String? lastError,
    bool clearError = false,
    bool? autoReconnect,
    bool? autoConnectOnStartup,
    CommissioningReport? commissioningReport,
    bool clearCommissioning = false,
  }) {
    return KeyenceCoordinatorState(
      status: status ?? this.status,
      discoveryStatus: discoveryStatus ?? this.discoveryStatus,
      discoveryMessage: discoveryMessage ?? this.discoveryMessage,
      discoveryProgress: discoveryProgress ?? this.discoveryProgress,
      discoveredScanners: discoveredScanners ?? this.discoveredScanners,
      host: host ?? this.host,
      port: port ?? this.port,
      dataPort: dataPort ?? this.dataPort,
      dataChannelStatus: dataChannelStatus ?? this.dataChannelStatus,
      dataChannelError: clearDataChannelError
          ? null
          : (dataChannelError ?? this.dataChannelError),
      model: model ?? this.model,
      firmware: clearFirmware ? null : (firmware ?? this.firmware),
      serialNumber: clearSerial ? null : (serialNumber ?? this.serialNumber),
      connectTimeMs: connectTimeMs ?? this.connectTimeMs,
      handshakeTimeMs: handshakeTimeMs ?? this.handshakeTimeMs,
      totalConnectionTimeMs:
          totalConnectionTimeMs ?? this.totalConnectionTimeMs,
      lastScan: lastScan ?? this.lastScan,
      lastScanTime: lastScanTime ?? this.lastScanTime,
      scanCount: scanCount ?? this.scanCount,
      lastError: clearError ? null : (lastError ?? this.lastError),
      autoReconnect: autoReconnect ?? this.autoReconnect,
      autoConnectOnStartup: autoConnectOnStartup ?? this.autoConnectOnStartup,
      commissioningReport: clearCommissioning
          ? null
          : (commissioningReport ?? this.commissioningReport),
    );
  }
}

/// Central unified coordinator for the KEYENCE SR-751 industrial scanner.
///
/// Integrates:
/// - Fast 3-4s connection with explicit protocol handshake verification.
/// - Automatic local network scanner discovery.
/// - Persistent device profile and startup auto-connection.
/// - Direct feeding into [ScannerController] and Exalted's primary core pipeline.
/// - Non-destructive automated commissioning checks.
class KeyenceScannerCoordinator extends Notifier<KeyenceCoordinatorState> {
  KeyenceSr751Client get _client => ref.read(keyenceSr751ClientProvider);
  KeyenceSr751Client get _dataClient =>
      ref.read(keyenceSr751DataClientProvider);
  final KeyenceScannerDiscoveryService _discoveryService =
      KeyenceScannerDiscoveryService(probeEnabled: false);
  final KeyenceCommissioningService _commissioning =
      const KeyenceCommissioningService();

  final Sr751MessageClassifier _classifier = Sr751MessageClassifier(
    profile: const Sr751ReplyProfile.production(),
  );

  StreamSubscription<KeyenceConnectionStatus>? _statusSub;
  StreamSubscription<KeyenceConnectionStatus>? _dataStatusSub;
  StreamSubscription<KeyenceScanResult>? _scanSub;
  StreamSubscription<KeyenceScanResult>? _dataScanSub;
  StreamSubscription<ScannerDiscoveryEvent>? _discoverySub;

  // User-driven connection actions supersede asynchronous startup hydration,
  // discovery, and connection attempts.
  int _userConnectionActionGeneration = 0;

  @override
  KeyenceCoordinatorState build() {
    _statusSub?.cancel();
    _dataStatusSub?.cancel();
    _scanSub?.cancel();
    _dataScanSub?.cancel();
    _discoverySub?.cancel();

    _statusSub = _client.statusStream.listen(_onClientStatusChanged);
    _dataStatusSub = _dataClient.statusStream.listen(
      _onDataClientStatusChanged,
    );
    _scanSub = _client.scanStream.listen(_onBarcodeReceived);
    _dataScanSub = _dataClient.scanStream.listen(_onBarcodeReceived);
    _discoverySub = _discoveryService.eventsStream.listen(_onDiscoveryEvent);

    ref.onDispose(() {
      _statusSub?.cancel();
      _dataStatusSub?.cancel();
      _scanSub?.cancel();
      _dataScanSub?.cancel();
      _discoverySub?.cancel();
      _discoveryService.dispose();
    });

    // Capture the action generation now, not when the microtask executes.
    // A user can select/connect an endpoint before that microtask gets a turn.
    final startupGeneration = _userConnectionActionGeneration;
    Future.microtask(() => _initFromStorage(startupGeneration));

    return const KeyenceCoordinatorState();
  }

  Future<void> _initFromStorage(int startupGeneration) async {
    try {
      if (!ref.mounted ||
          startupGeneration != _userConnectionActionGeneration) {
        return;
      }
      final sc = ref.read(configControllerProvider).scanner;
      final hasSavedHost = sc.hostSaved;
      final savedHost = sc.host;
      final savedPort = sc.port;
      final savedDataPort = sc.dataPort ?? savedPort;
      final savedModel = sc.deviceLabel;
      final autoConnect = sc.autoConnect;
      final autoReconnect = sc.autoReconnect;

      // A user action may have superseded startup before persisted settings
      // are applied. Never let storage overwrite that newer endpoint.
      if (!ref.mounted ||
          startupGeneration != _userConnectionActionGeneration) {
        return;
      }

      _client.autoReconnect = autoReconnect;
      _dataClient.autoReconnect = autoReconnect;
      // The app allow-list contains the documented read-only KEYENCE identity
      // command, so discovery can verify candidates rather than trusting an
      // open TCP port. An explicitly empty allow-list keeps listen-only mode.
      _discoveryService.probeEnabled = _client.verifyIdentityOnConnect;
      _discoveryService.setDefaultPort(savedPort);
      _discoveryService.addCandidateHost(savedHost, port: savedPort);

      state = state.copyWith(
        host: savedHost,
        port: savedPort,
        dataPort: savedDataPort,
        dataChannelStatus: KeyenceConnectionStatus.disconnected,
        model: savedModel,
        autoConnectOnStartup: autoConnect,
        autoReconnect: autoReconnect,
      );

      if (!autoConnect || state.isConnected || state.isConnecting) return;

      // First verify the user's saved endpoint with the documented read-only
      // identity query. If absent/unreachable, search the local Ethernet link.
      if (hasSavedHost) {
        debugPrint(
          '[KEYENCE][COORDINATOR] Auto-connecting to saved endpoint $savedHost:$savedPort with documented KEYENCE identity verification...',
        );
        final connected = await connect(
          targetHost: savedHost,
          targetPort: savedPort,
          targetDataPort: savedDataPort,
          timeout: const Duration(seconds: 3),
          expectedActionGeneration: startupGeneration,
        );
        if (connected ||
            !ref.mounted ||
            startupGeneration != _userConnectionActionGeneration) {
          return;
        }
      }

      debugPrint(
        '[KEYENCE][COORDINATOR] No saved endpoint verified; starting automatic KEYENCE protocol discovery...',
      );
      await discoverScanners(startupInvocation: true);
    } catch (e) {
      debugPrint('[KEYENCE][COORDINATOR] Error loading preferences: $e');
    }
  }

  void _onClientStatusChanged(KeyenceConnectionStatus status) {
    state = state.copyWith(
      status: status,
      lastError: _client.lastError,
      clearError: status == KeyenceConnectionStatus.connected,
      dataChannelStatus: state.dataPort == state.port
          ? status
          : state.dataChannelStatus,
      dataChannelError: state.dataPort == state.port
          ? _client.lastError
          : state.dataChannelError,
      clearDataChannelError:
          state.dataPort == state.port &&
          status == KeyenceConnectionStatus.connected,
    );
  }

  void _onDataClientStatusChanged(KeyenceConnectionStatus status) {
    if (state.dataPort == state.port) return;
    state = state.copyWith(
      dataChannelStatus: status,
      dataChannelError: _dataClient.lastError,
      clearDataChannelError: status == KeyenceConnectionStatus.connected,
    );
  }

  Future<void> _connectDataChannel({
    required String host,
    required int commandPort,
    required int dataPort,
    required Duration timeout,
  }) async {
    if (dataPort == commandPort) {
      await _dataClient.disconnect();
      if (!ref.mounted) return;
      state = state.copyWith(
        dataChannelStatus: _client.status,
        dataChannelError: _client.lastError,
        clearDataChannelError:
            _client.status == KeyenceConnectionStatus.connected,
      );
      return;
    }

    _dataClient.autoReconnect = state.autoReconnect;
    final connected = await _dataClient.connect(
      targetHost: host,
      targetPort: dataPort,
      timeout: timeout,
    );
    if (!ref.mounted) return;
    state = state.copyWith(
      dataChannelStatus: connected
          ? KeyenceConnectionStatus.connected
          : _dataClient.status,
      dataChannelError: connected
          ? null
          : (_dataClient.lastError ??
                'Could not open the Data Port 1 TCP connection at $host:$dataPort.'),
      clearDataChannelError: connected,
    );
  }

  void _onBarcodeReceived(KeyenceScanResult scan) {
    if (scan.isError) {
      debugPrint('[KEYENCE][COORDINATOR] Read failure: ${scan.errorMessage}');
      state = state.copyWith(lastError: scan.errorMessage);
      return;
    }

    final raw = scan.rawResponse.isNotEmpty ? scan.rawResponse : scan.data;
    final classification = _classifier.classify(raw);

    if (classification.kind != Sr751MessageKind.barcode) {
      debugPrint(
        '[KEYENCE][COORDINATOR] Filtered non-barcode message: $raw (${classification.kind})',
      );
      return;
    }

    final payload = classification.payload.isNotEmpty
        ? classification.payload
        : scan.data;
    final now = DateTime.now();

    state = state.copyWith(
      lastScan: payload,
      lastScanTime: now,
      scanCount: state.scanCount + 1,
    );

    // Dispatch directly to Exalted's main ScannerController
    try {
      ref
          .read(scannerControllerProvider.notifier)
          .presentIndustrialScan(
            text: payload,
            format: 'Keyence ${state.model}',
          );
    } catch (e) {
      debugPrint(
        '[KEYENCE][COORDINATOR] Dispatch to scanner controller skipped: $e',
      );
    }
  }

  void _onDiscoveryEvent(ScannerDiscoveryEvent event) {
    state = state.copyWith(
      discoveryMessage: event.message,
      discoveryProgress: event.progress,
    );
  }

  /// Runs automatic scanner discovery across local interfaces.
  Future<List<DiscoveredKeyenceScanner>> discoverScanners({
    bool deepSweep = false,
    bool startupInvocation = false,
  }) async {
    if (!startupInvocation) _userConnectionActionGeneration++;
    final actionGeneration = _userConnectionActionGeneration;
    // Keep discovery mode aligned with the active client's allow-list even
    // when the user starts discovery before persisted settings finish loading.
    _discoveryService.probeEnabled = _client.verifyIdentityOnConnect;
    state = state.copyWith(
      discoveryStatus: DiscoveryStatus.discovering,
      discoveryMessage: 'Initiating scanner discovery...',
      discoveryProgress: 0.05,
    );

    final configuredTimeoutMs = ref
        .read(configControllerProvider)
        .scanner
        .discoveryTimeoutMs;
    final timeoutMs = deepSweep && configuredTimeoutMs < 15000
        ? 15000
        : configuredTimeoutMs;
    final results = await _discoveryService.scanForScanners(
      overallTimeout: Duration(milliseconds: timeoutMs),
      // Direct Ethernet connections often have no ARP entry until the first
      // packet. Always include the Ethernet subnet candidate sweep.
      includeSubnetSweep: true,
    );

    if (!ref.mounted || actionGeneration != _userConnectionActionGeneration) {
      return results;
    }

    final discoveryTimedOut = _discoveryService.lastScanTimedOut;
    state = state.copyWith(
      discoveryStatus: DiscoveryStatus.completed,
      discoveredScanners: results,
      discoveryMessage: discoveryTimedOut
          ? 'Discovery time limit reached. Found ${results.length} scanner(s); run a deeper scan or verify the saved endpoint.'
          : 'Discovery finished. Found ${results.length} scanner(s).',
      discoveryProgress: 1.0,
    );

    // Automatically connect to the first candidate that passed the exact
    // documented KEYENCE identity response check (or connect-only when the
    // app is explicitly configured with an empty command allow-list).
    if (results.isNotEmpty && !state.isConnected && !state.isConnecting) {
      final first = results.first;
      final host = first.identity.ipAddress;
      final port = first.identity.port;
      if (host != null && port != null) {
        state = state.copyWith(
          host: host,
          port: port,
          model: first.identity.model,
          firmware: first.identity.firmwareVersion,
          serialNumber: first.identity.serialNumber,
        );
        final connected = await connect(
          targetHost: host,
          targetPort: port,
          timeout: const Duration(seconds: 3),
          expectedActionGeneration: actionGeneration,
        );
        if (!ref.mounted ||
            actionGeneration != _userConnectionActionGeneration) {
          return results;
        }
        if (connected && !_client.verifyIdentityOnConnect) {
          state = state.copyWith(
            discoveryMessage:
                'TCP connected to $host:$port. Device identity is unverified; no commands were sent.',
          );
        }
      }
    }

    return results;
  }

  /// Fast-path connection (< 3-4 seconds) with explicit protocol handshake verification.
  Future<bool> connect({
    String? targetHost,
    int? targetPort,
    int? targetDataPort,
    Duration timeout = const Duration(seconds: 4),
    int? expectedActionGeneration,
  }) async {
    if (expectedActionGeneration == null) {
      _userConnectionActionGeneration++;
    }
    final actionGeneration =
        expectedActionGeneration ?? _userConnectionActionGeneration;
    final host = targetHost ?? state.host;
    final port = targetPort ?? state.port;
    // When the previous configuration shared one port, follow a newly
    // selected command port. An explicitly separate Data Port 1 is retained.
    final dataPort =
        targetDataPort ??
        (state.dataPort == state.port ? port : state.dataPort);

    state = state.copyWith(
      status: KeyenceConnectionStatus.connecting,
      host: host,
      port: port,
      dataPort: dataPort,
      dataChannelStatus: KeyenceConnectionStatus.connecting,
      clearError: true,
      clearDataChannelError: true,
    );

    debugPrint(
      '[KEYENCE][COORDINATOR] Connecting to $host:$port (timeout: ${timeout.inSeconds}s)...',
    );

    if (!_client.verifyIdentityOnConnect) {
      // Listen-only: open the TCP connection and send nothing. The reader is
      // not verified, so this endpoint is not saved as a verified profile.
      debugPrint(
        '[KEYENCE][COORDINATOR] Listen-only: no commands are sent to $host:$port',
      );
      final connected = await _client.connect(
        targetHost: host,
        targetPort: port,
        timeout: timeout,
      );
      if (!ref.mounted || actionGeneration != _userConnectionActionGeneration) {
        return false;
      }
      if (connected) {
        await _connectDataChannel(
          host: host,
          commandPort: port,
          dataPort: dataPort,
          timeout: timeout,
        );
      } else {
        await _dataClient.disconnect();
      }
      return connected && actionGeneration == _userConnectionActionGeneration;
    }

    final handshake = await _client.connectAndVerify(
      targetHost: host,
      targetPort: port,
      timeout: timeout,
    );

    if (!ref.mounted || actionGeneration != _userConnectionActionGeneration) {
      return handshake.success;
    }

    if (handshake.success) {
      debugPrint(
        '[KEYENCE][COORDINATOR] Connected and verified in ${handshake.totalTimeMs} ms '
        '(TCP: ${handshake.connectTimeMs}ms, Handshake: ${handshake.handshakeTimeMs}ms). '
        'Model: ${handshake.model}, FW: ${handshake.firmwareVersion}, SN: ${handshake.serialNumber}',
      );

      state = state.copyWith(
        status: KeyenceConnectionStatus.connected,
        model: handshake.model,
        firmware: handshake.firmwareVersion,
        serialNumber: handshake.serialNumber,
        connectTimeMs: handshake.connectTimeMs,
        handshakeTimeMs: handshake.handshakeTimeMs,
        totalConnectionTimeMs: handshake.totalTimeMs,
        clearError: true,
      );

      await _connectDataChannel(
        host: host,
        commandPort: port,
        dataPort: dataPort,
        timeout: timeout,
      );
      if (!ref.mounted || actionGeneration != _userConnectionActionGeneration) {
        return false;
      }

      // Persist successful endpoint
      unawaited(_saveProfile(host, port, dataPort, handshake.model));
      _discoveryService.addCandidateHost(host);
      return true;
    } else {
      await _dataClient.disconnect();
      if (!ref.mounted || actionGeneration != _userConnectionActionGeneration) {
        return false;
      }
      debugPrint(
        '[KEYENCE][COORDINATOR] Connection failed: ${handshake.errorMessage}',
      );
      state = state.copyWith(
        status: KeyenceConnectionStatus.error,
        dataChannelStatus: KeyenceConnectionStatus.disconnected,
        lastError: handshake.errorMessage,
        connectTimeMs: handshake.connectTimeMs,
        handshakeTimeMs: handshake.handshakeTimeMs,
        totalConnectionTimeMs: handshake.totalTimeMs,
      );
      return false;
    }
  }

  /// Disconnects from the scanner.
  Future<void> disconnect() async {
    _userConnectionActionGeneration++;
    await Future.wait([_client.disconnect(), _dataClient.disconnect()]);
    if (!ref.mounted) return;
    state = state.copyWith(
      status: KeyenceConnectionStatus.disconnected,
      dataChannelStatus: KeyenceConnectionStatus.disconnected,
      clearError: true,
      clearDataChannelError: true,
    );
  }

  /// Re-establishes connection to the current host and port.
  Future<bool> reconnect() async {
    await disconnect();
    if (!ref.mounted) return false;
    return connect();
  }

  /// Hardware trigger read ('LON').
  Future<bool> triggerRead() => _client.triggerRead();

  /// Hardware stop read ('LOFF').
  Future<bool> stopRead() => _client.stopRead();

  /// Hardware test mode 1 ('T1').
  Future<bool> triggerT1() => _client.triggerT1();

  /// Triggers buzzer beep ('BEEP').
  Future<bool> beep() => _client.beep();

  /// Read-only reader error-status query documented by KEYENCE.
  Future<bool> queryStatus() => _client.sendCommand('ERRSTAT');

  /// Requests FTP image upload ('FTPOUT').
  Future<bool> requestFtpImage() => _client.requestFtpImage();

  /// Runs full readiness assessment / commissioning check.
  Future<CommissioningReport> runCommissioning({
    String? targetHost,
    int? targetPort,
  }) async {
    final host = targetHost ?? state.host;
    final port = targetPort ?? state.port;
    final ftp = ref.read(keyenceFtpReceiverProvider);

    final report = await _commissioning.runReadinessAssessment(
      host: host,
      port: port,
      existingClient: state.isConnected ? _client : null,
      ftpReceiver: ftp,
      sendCommands: _client.canHandshake,
      allowedCommands: _client.allowedCommands,
    );

    state = state.copyWith(commissioningReport: report);
    return report;
  }

  Future<void> setAutoReconnect(bool enabled) async {
    _client.autoReconnect = enabled;
    _dataClient.autoReconnect = enabled;
    state = state.copyWith(autoReconnect: enabled);
    await ref.read(configControllerProvider.notifier).patch({
      'scanner': {'autoReconnect': enabled},
    });
  }

  Future<void> setAutoConnectOnStartup(bool enabled) async {
    state = state.copyWith(autoConnectOnStartup: enabled);
    await ref.read(configControllerProvider.notifier).patch({
      'scanner': {'autoConnect': enabled},
    });
  }

  Future<void> _saveProfile(
    String host,
    int port,
    int dataPort,
    String model,
  ) async {
    try {
      await ref.read(configControllerProvider.notifier).patch({
        'scanner': {
          'host': host,
          'port': port,
          'dataPort': dataPort == port ? null : dataPort,
          'deviceLabel': model,
          'hostSaved': true,
        },
      });
    } catch (_) {}
  }
}

final keyenceScannerCoordinatorProvider =
    NotifierProvider<KeyenceScannerCoordinator, KeyenceCoordinatorState>(
      KeyenceScannerCoordinator.new,
    );

final keyenceScannerDiscoveryServiceProvider =
    Provider<KeyenceScannerDiscoveryService>((ref) {
      final service = KeyenceScannerDiscoveryService(
        probeEnabled: ref
            .read(keyenceSr751ClientProvider)
            .verifyIdentityOnConnect,
      );
      ref.onDispose(service.dispose);
      return service;
    });
