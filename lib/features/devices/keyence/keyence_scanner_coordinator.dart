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
  bool get isDiscovering => discoveryStatus == DiscoveryStatus.discovering;

  KeyenceCoordinatorState copyWith({
    KeyenceConnectionStatus? status,
    DiscoveryStatus? discoveryStatus,
    String? discoveryMessage,
    double? discoveryProgress,
    List<DiscoveredKeyenceScanner>? discoveredScanners,
    String? host,
    int? port,
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
  final KeyenceScannerDiscoveryService _discoveryService =
      KeyenceScannerDiscoveryService();
  final KeyenceCommissioningService _commissioning =
      const KeyenceCommissioningService();

  final Sr751MessageClassifier _classifier = Sr751MessageClassifier(
    profile: const Sr751ReplyProfile.production(),
  );

  StreamSubscription<KeyenceConnectionStatus>? _statusSub;
  StreamSubscription<KeyenceScanResult>? _scanSub;
  StreamSubscription<ScannerDiscoveryEvent>? _discoverySub;

  @override
  KeyenceCoordinatorState build() {
    _statusSub?.cancel();
    _scanSub?.cancel();
    _discoverySub?.cancel();

    _statusSub = _client.statusStream.listen(_onClientStatusChanged);
    _scanSub = _client.scanStream.listen(_onBarcodeReceived);
    _discoverySub = _discoveryService.eventsStream.listen(_onDiscoveryEvent);

    ref.onDispose(() {
      _statusSub?.cancel();
      _scanSub?.cancel();
      _discoverySub?.cancel();
      _discoveryService.dispose();
    });

    // Schedule async initialization from persistent settings
    Future.microtask(_initFromStorage);

    return const KeyenceCoordinatorState();
  }

  Future<void> _initFromStorage() async {
    try {
      if (!ref.mounted) return;
      final sc = ref.read(configControllerProvider).scanner;
      final hasSavedHost = sc.hostSaved;
      final savedHost = sc.host;
      final savedPort = sc.port;
      final savedModel = sc.deviceLabel;
      final autoConnect = sc.autoConnect;
      final autoReconnect = sc.autoReconnect;

      _client.autoReconnect = autoReconnect;
      _discoveryService.addCandidateHost(savedHost);

      state = state.copyWith(
        host: savedHost,
        port: savedPort,
        model: savedModel,
        autoConnectOnStartup: autoConnect,
        autoReconnect: autoReconnect,
      );

      // Attempt fast automatic connection only if a saved host was persisted
      if (autoConnect &&
          hasSavedHost &&
          !state.isConnected &&
          !state.isConnecting) {
        debugPrint(
          '[KEYENCE][COORDINATOR] Auto-connecting to saved scanner at $savedHost:$savedPort...',
        );
        unawaited(
          connect(
            targetHost: savedHost,
            targetPort: savedPort,
            timeout: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('[KEYENCE][COORDINATOR] Error loading preferences: $e');
    }
  }

  void _onClientStatusChanged(KeyenceConnectionStatus status) {
    state = state.copyWith(
      status: status,
      lastError: _client.lastError,
      clearError: status == KeyenceConnectionStatus.connected,
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
  }) async {
    state = state.copyWith(
      discoveryStatus: DiscoveryStatus.discovering,
      discoveryMessage: 'Initiating scanner discovery...',
      discoveryProgress: 0.05,
    );

    final results = await _discoveryService.scanForScanners(
      includeSubnetSweep: deepSweep,
    );

    state = state.copyWith(
      discoveryStatus: DiscoveryStatus.completed,
      discoveredScanners: results,
      discoveryMessage:
          'Discovery finished. Found ${results.length} scanner(s).',
      discoveryProgress: 1.0,
    );

    // If an undiscovered scanner was found and we are currently disconnected, select it
    if (results.isNotEmpty && !state.isConnected) {
      final first = results.first;
      state = state.copyWith(
        host: first.identity.ipAddress ?? state.host,
        port: first.identity.port ?? state.port,
        model: first.identity.model,
        firmware: first.identity.firmwareVersion,
        serialNumber: first.identity.serialNumber,
      );
    }

    return results;
  }

  /// Fast-path connection (< 3-4 seconds) with explicit protocol handshake verification.
  Future<bool> connect({
    String? targetHost,
    int? targetPort,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final host = targetHost ?? state.host;
    final port = targetPort ?? state.port;

    state = state.copyWith(
      status: KeyenceConnectionStatus.connecting,
      host: host,
      port: port,
      clearError: true,
    );

    debugPrint(
      '[KEYENCE][COORDINATOR] Connecting to $host:$port (timeout: ${timeout.inSeconds}s)...',
    );

    final handshake = await _client.connectAndVerify(
      targetHost: host,
      targetPort: port,
      timeout: timeout,
    );

    if (!ref.mounted) return handshake.success;

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

      // Persist successful endpoint
      unawaited(_saveProfile(host, port, handshake.model));
      _discoveryService.addCandidateHost(host);
      return true;
    } else {
      debugPrint(
        '[KEYENCE][COORDINATOR] Connection failed: ${handshake.errorMessage}',
      );
      state = state.copyWith(
        status: KeyenceConnectionStatus.error,
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
    await _client.disconnect();
    if (!ref.mounted) return;
    state = state.copyWith(
      status: KeyenceConnectionStatus.disconnected,
      clearError: true,
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

  /// Hardware status check ('STAT').
  Future<bool> queryStatus() => _client.sendCommand('STAT');

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
    );

    state = state.copyWith(commissioningReport: report);
    return report;
  }

  Future<void> setAutoReconnect(bool enabled) async {
    _client.autoReconnect = enabled;
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

  Future<void> _saveProfile(String host, int port, String model) async {
    try {
      await ref.read(configControllerProvider.notifier).patch({
        'scanner': {
          'host': host,
          'port': port,
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
      final service = KeyenceScannerDiscoveryService();
      ref.onDispose(service.dispose);
      return service;
    });
