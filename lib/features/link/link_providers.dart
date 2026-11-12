import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'link_client.dart';
import 'link_journal.dart';
import '../history/history_repository.dart';
import '../inspection/inspection_log.dart';
import '../ocr/services/ocr_history_repository.dart';
import '../../core/storage/image_storage_service.dart';
import '../../core/config/platform_secret_store.dart';
import '../history/history_controller.dart';
import '../devices/keyence/keyence_scanner_coordinator.dart';
import '../scanner/scanner_controller.dart';
import 'sync_bridge.dart';
import 'sync_importer.dart';
import 'link_models.dart';
import 'link_pairing.dart';
import 'link_server.dart';
import 'link_store.dart';
import 'companion_notifications.dart';

/// App version reported to the other device while pairing.
const String kLinkAppVersion = String.fromEnvironment(
  'EXALTED_VERSION',
  defaultValue: '1.0.0',
);

/// Checks an address typed for a linked desktop. Returns an error message, or
/// null when it is acceptable. Only local network IPv4 addresses are allowed,
/// which matches what the desktop service serves.
String? validatePeerAddress(String host, String port) {
  final address = InternetAddress.tryParse(host.trim());
  if (address == null || address.type != InternetAddressType.IPv4) {
    return 'Enter the IPv4 address of the desktop, for example 192.168.1.20.';
  }
  if (!isPrivateAddress(address)) {
    return 'Only local network addresses are allowed: 192.168.x.x, 10.x.x.x, '
        '172.16 to 172.31.x.x, or this computer.';
  }
  final number = int.tryParse(port.trim());
  if (number == null || number < 1 || number > 65535) {
    return 'The port must be a number from 1 to 65535.';
  }
  return null;
}

/// Folder holding all linking state. It is separate from the history
/// databases and is never deleted by this code.
final linkDirectoryProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}link');
});

/// Central provider for the link credential store.
final linkStoreProvider = FutureProvider<LinkStore>((ref) async {
  final dir = await ref.watch(linkDirectoryProvider.future);
  final store = LinkStore(dir, secretStore: ref.read(secretStoreProvider));
  await store.load();
  return store;
});

/// Central provider for the link sync journal.
final linkJournalProvider = FutureProvider<FileSyncStore>((ref) async {
  final dir = await ref.watch(linkDirectoryProvider.future);
  final journal = FileSyncStore(dir);
  await journal.open();
  return journal;
});

@immutable
class LinkUiState {
  const LinkUiState({
    this.ready = false,
    this.busy = false,
    this.syncing = false,
    this.deviceId = '',
    this.deviceName = '',
    this.serverPort = 0,
    this.payload,
    this.preview,
    this.pending,
    this.devices = const <LinkedDevice>[],
    this.peers = const <PeerDesktop>[],
    this.conflicts = const <SyncConflictCase>[],
    this.syncHistory = const <SyncSessionEntry>[],
    this.remoteCommands = const <Map<String, Object?>>[],
    this.companionConnected = false,
    this.companionStreaming = false,
    this.companionPeerId,
    this.companionSnapshot,
    this.companionHeartbeat,
    this.companionLatencyMs,
    this.companionError,
    this.progress,
    this.summary,
    this.error,
    this.notice,
  });

  final bool ready;
  final bool busy;
  final bool syncing;
  final String deviceId;
  final String deviceName;

  /// Port of the local service. 0 while it is not running.
  final int serverPort;

  /// Desktop: the pairing offer currently shown as a QR code.
  final PairingPayload? payload;

  /// Phone: a scanned or pasted code waiting for the user's confirmation.
  final PairingPayload? preview;

  /// Desktop: a device waiting for the owner's approval.
  final PairRequest? pending;

  final List<LinkedDevice> devices;
  final List<PeerDesktop> peers;
  final List<SyncConflictCase> conflicts;
  final List<SyncSessionEntry> syncHistory;
  final List<Map<String, Object?>> remoteCommands;
  final bool companionConnected;
  final bool companionStreaming;
  final String? companionPeerId;
  final CompanionSnapshot? companionSnapshot;
  final DateTime? companionHeartbeat;
  final int? companionLatencyMs;
  final String? companionError;
  final SyncProgress? progress;
  final SyncSummary? summary;
  final String? error;
  final String? notice;

  LinkUiState copyWith({
    bool? ready,
    bool? busy,
    bool? syncing,
    String? deviceId,
    String? deviceName,
    int? serverPort,
    PairingPayload? payload,
    bool clearPayload = false,
    PairingPayload? preview,
    bool clearPreview = false,
    PairRequest? pending,
    bool clearPending = false,
    List<LinkedDevice>? devices,
    List<PeerDesktop>? peers,
    List<SyncConflictCase>? conflicts,
    List<SyncSessionEntry>? syncHistory,
    List<Map<String, Object?>>? remoteCommands,
    bool? companionConnected,
    bool? companionStreaming,
    String? companionPeerId,
    bool clearCompanionPeerId = false,
    CompanionSnapshot? companionSnapshot,
    bool clearCompanionSnapshot = false,
    DateTime? companionHeartbeat,
    bool clearCompanionHeartbeat = false,
    int? companionLatencyMs,
    bool clearCompanionLatency = false,
    String? companionError,
    bool clearCompanionError = false,
    SyncProgress? progress,
    bool clearProgress = false,
    SyncSummary? summary,
    String? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
  }) {
    return LinkUiState(
      ready: ready ?? this.ready,
      busy: busy ?? this.busy,
      syncing: syncing ?? this.syncing,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      serverPort: serverPort ?? this.serverPort,
      payload: clearPayload ? null : (payload ?? this.payload),
      preview: clearPreview ? null : (preview ?? this.preview),
      pending: clearPending ? null : (pending ?? this.pending),
      devices: devices ?? this.devices,
      peers: peers ?? this.peers,
      conflicts: conflicts ?? this.conflicts,
      syncHistory: syncHistory ?? this.syncHistory,
      remoteCommands: remoteCommands ?? this.remoteCommands,
      companionConnected: companionConnected ?? this.companionConnected,
      companionStreaming: companionStreaming ?? this.companionStreaming,
      companionPeerId: clearCompanionPeerId
          ? null
          : (companionPeerId ?? this.companionPeerId),
      companionSnapshot: clearCompanionSnapshot
          ? null
          : (companionSnapshot ?? this.companionSnapshot),
      companionHeartbeat: clearCompanionHeartbeat
          ? null
          : (companionHeartbeat ?? this.companionHeartbeat),
      companionLatencyMs: clearCompanionLatency
          ? null
          : (companionLatencyMs ?? this.companionLatencyMs),
      companionError: clearCompanionError
          ? null
          : (companionError ?? this.companionError),
      progress: clearProgress ? null : (progress ?? this.progress),
      summary: summary ?? this.summary,
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }
}

final linkControllerProvider = NotifierProvider<LinkController, LinkUiState>(
  LinkController.new,
);

/// Whether this process hosts the desktop link service. Keeping the role in a
/// provider lets integration tests exercise the Android-side controller on a
/// desktop test runner.
final desktopLinkRoleProvider = Provider<bool>(
  (ref) => Platform.isLinux || Platform.isWindows,
);

/// A stream of sync journal change events. Emits an integer (the new journal
/// length) whenever records are added, so UI layers can refresh reactively.
final syncChangeStreamProvider = StreamProvider<int>((ref) async* {
  final store = ref.read(linkDirectoryProvider.future);
  final dir = await store;
  final journal = FileSyncStore(dir);
  await journal.open();
  yield* journal.changes;
});

// ===========================================================================
// Cross-network connection architecture (WhatsApp Web-style linking)
//
// Local-network pairing (HTTPS, pinned cert, private IP validation) is
// preserved. Cross-network adds: STUN discovery + direct connection
// + TURN relay fallback + signaling server. The relay only forwards
// end-to-end encrypted frames and cannot read payloads.
// ===========================================================================

/// Mode of the active link connection.
enum LinkConnectionMode { local, direct, relayed }

/// Result of STUN server discovery.
@immutable
class StunCandidate {
  const StunCandidate({required this.host, required this.port});
  final String host;
  final int port;
}

/// Configuration for cross-network linking. Deployed separately from the app.
@immutable
class CrossNetworkConfig {
  const CrossNetworkConfig({
    required this.stunServers,
    required this.turnServers,
    required this.signalingBaseUrl,
    this.enableRelay = false,
  });
  final List<StunCandidate> stunServers;
  final List<TurnServer> turnServers;
  final String signalingBaseUrl;
  final bool enableRelay;
}

/// A TURN server credential set.
@immutable
class TurnServer {
  const TurnServer({
    required this.host,
    required this.port,
    required this.username,
    required this.credential,
  });
  final String host;
  final int port;
  final String username;
  final String credential;
}

/// Default: no cross-network infrastructure. Local-network pairing preserved.
const CrossNetworkConfig kDefaultCrossNetworkConfig = CrossNetworkConfig(
  stunServers: <StunCandidate>[],
  turnServers: <TurnServer>[],
  signalingBaseUrl: '',
  enableRelay: false,
);

final crossNetworkConfigProvider = Provider<CrossNetworkConfig>((ref) {
  return kDefaultCrossNetworkConfig;
});

/// Connects the existing link backend (store, server, client, journal) to the
/// UI. It never reports a device as connected unless the backend completed an
/// authenticated pairing.
class LinkController extends Notifier<LinkUiState> {
  LinkStore? _store;
  FileSyncStore? _journal;
  LinkClient? _client;
  LinkServer? _server;
  PairingManager _pairing = PairingManager();
  Completer<bool>? _approval;
  Timer? _tick;
  String _lastSig = '';
  bool _disposed = false;
  bool _importing = false;
  bool _sweeping = false;
  bool _pollingCompanion = false;
  bool _drainingCompanionSync = false;
  PeerDesktop? _queuedCompanionSync;
  int _importedLen = -1;
  int _lastConflictCount = -1;
  int _companionFailures = 0;
  DateTime _nextCompanionPoll = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<CompanionStreamMessage>? _companionStream;
  String? _streamPeerId;
  bool _streamRunning = false;
  int _streamGeneration = 0;
  final Set<String> _companionEventIds = <String>{};
  DateTime _lastDesktopSweep = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<String> _resolvingConflicts = <String>{};

  bool get _isDesktop => ref.read(desktopLinkRoleProvider);

  @override
  LinkUiState build() {
    _disposed = false;
    _store = null;
    _journal = null;
    _client = null;
    _server = null;
    _pairing = PairingManager();
    _approval = null;
    _lastSig = '';
    _importedLen = -1;
    ref.onDispose(_shutdown);
    Future<void>.microtask(_init);
    return const LinkUiState();
  }

  void _update(LinkUiState Function(LinkUiState s) change) {
    if (_disposed) return;
    state = change(state);
  }

  String _msg(Object e) =>
      e is LinkException ? e.message : 'unexpected error (${e.runtimeType})';

  void _shutdown() {
    _disposed = true;
    _tick?.cancel();
    _tick = null;
    _streamGeneration++;
    _streamPeerId = null;
    _queuedCompanionSync = null;
    unawaited(_companionStream?.cancel());
    _companionStream = null;
    final a = _approval;
    if (a != null && !a.isCompleted) a.complete(false);
    final s = _server;
    _server = null;
    if (s != null) unawaited(s.stop());
  }

  Future<void> retryInit() async {
    _update((s) => s.copyWith(clearError: true));
    await _init();
  }

  Future<void> _init() async {
    _tick?.cancel();
    try {
      final dir = await ref.read(linkDirectoryProvider.future);
      if (_disposed) return;
      final store = LinkStore(dir, secretStore: ref.read(secretStoreProvider));
      await store.load();
      final journal = FileSyncStore(dir);
      await journal.open();
      if (_disposed) return;
      if (store.deviceName == 'Exalted') {
        store.deviceName = Platform.localHostname;
        await store.save();
      }
      _store = store;
      _journal = journal;
      _client = LinkClient(store: store, journal: journal);
      _update(
        (s) => s.copyWith(
          ready: true,
          deviceId: store.deviceId,
          deviceName: store.deviceName,
          clearError: true,
        ),
      );
      _refresh();
      await _refreshConflicts();
      _refreshSyncHistory();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
      if (!_isDesktop) {
        unawaited(_sweepNow());
        unawaited(_pollCompanion());
      }
    } catch (e) {
      _update(
        (s) => s.copyWith(
          error: 'Could not open the link storage (${e.runtimeType}).',
        ),
      );
      return;
    }
    final store = _store;
    if (store != null && _isDesktop && store.devices.any((d) => !d.revoked)) {
      try {
        await _ensureServer();
      } catch (e) {
        _update(
          (s) => s.copyWith(
            error: 'Could not start the local link service: ${_msg(e)}',
          ),
        );
      }
    }
  }

  String _sig() {
    final s = _store;
    if (s == null) return '';
    final b = StringBuffer();
    for (final d in s.devices) {
      b
        ..write(d.id)
        ..write(d.name)
        ..write(d.revoked)
        ..write(d.lastSeen?.millisecondsSinceEpoch)
        ..write(d.lastSync?.millisecondsSinceEpoch)
        ..write('|');
    }
    for (final p in s.peers) {
      b
        ..write(p.id)
        ..write(p.host)
        ..write(p.port)
        ..write(p.lastSync?.millisecondsSinceEpoch)
        ..write('|');
    }
    return b.toString();
  }

  void _refresh() {
    final s = _store;
    if (s == null) return;
    _lastSig = _sig();
    _update(
      (u) => u.copyWith(
        devices: List<LinkedDevice>.of(s.devices),
        peers: List<PeerDesktop>.of(s.peers),
        remoteCommands: _server?.recentRemoteCommands ?? state.remoteCommands,
      ),
    );
  }

  Future<void> _refreshConflicts() async {
    final journal = _journal;
    if (journal == null || _disposed) return;
    final conflicts = await journal.conflictCases();
    final count = journal.conflictCount;
    _lastConflictCount = count;
    _update((s) => s.copyWith(conflicts: conflicts));
    if (!_disposed && journal.conflictCount != count) {
      unawaited(_refreshConflicts());
    }
  }

  void _refreshSyncHistory() {
    final journal = _journal;
    if (journal == null || _disposed) return;
    _update((s) => s.copyWith(syncHistory: journal.syncSessions));
  }

  void _onTick() {
    if (_disposed) return;
    final p = state.payload;
    if (p != null && p.isExpired(DateTime.now())) {
      state = state.copyWith(clearPayload: true);
    }
    if (_sig() != _lastSig) _refresh();
    final conflictCount = _journal?.conflictCount;
    if (conflictCount != null && conflictCount != _lastConflictCount) {
      _lastConflictCount = conflictCount;
      unawaited(_refreshConflicts());
    }
    _maybeImport();
    final now = DateTime.now();
    if (_isDesktop &&
        (_server?.running ?? false) &&
        now.difference(_lastDesktopSweep) >= const Duration(seconds: 5)) {
      _lastDesktopSweep = now;
      unawaited(_sweepNow());
    } else if (!_isDesktop && !now.isBefore(_nextCompanionPoll)) {
      unawaited(_pollCompanion());
    }
  }

  Future<void> _pollCompanion() async {
    if (_disposed ||
        _pollingCompanion ||
        DateTime.now().isBefore(_nextCompanionPoll)) {
      return;
    }
    final client = _client;
    final peers = _store?.peers;
    if (client == null || peers == null) return;
    if (peers.isEmpty) {
      _stopCompanionStream();
      _companionFailures = 0;
      _nextCompanionPoll = DateTime.now().add(const Duration(seconds: 3));
      _update(
        (s) => s.copyWith(
          companionConnected: false,
          clearCompanionPeerId: true,
          clearCompanionSnapshot: true,
          clearCompanionHeartbeat: true,
          clearCompanionLatency: true,
          clearCompanionError: true,
        ),
      );
      return;
    }
    _pollingCompanion = true;
    final selectedId = state.companionPeerId;
    PeerDesktop? selected;
    for (final candidate in peers) {
      if (candidate.id == selectedId) selected = candidate;
    }
    final peer = selected ?? peers.first;
    final shouldCatchUp =
        !state.companionConnected || state.companionPeerId != peer.id;
    final timer = Stopwatch()..start();
    try {
      final snapshot = await client.fetchCompanionSnapshot(peer);
      timer.stop();
      if (_disposed) return;
      await CompanionNotifications.connectionTransition(peer.id, true);
      final newSnapshotEvents = await CompanionNotifications.observeSnapshot(
        peer.id,
        peer.pairedAt,
        snapshot.events,
      );
      final hardware = snapshot.hardware;
      for (final component in const ['camera', 'keyence']) {
        final value = hardware[component];
        if (value is Map && value['status'] is String) {
          await CompanionNotifications.hardwareTransition(
            peer.id,
            component,
            value['status'] as String,
          );
        }
      }
      final previousIds =
          state.companionSnapshot?.events.map((event) => event.id).toSet() ??
          const <String>{};
      for (final event in newSnapshotEvents) {
        if (!previousIds.contains(event.id)) {
          unawaited(CompanionNotifications.activity(event));
        }
      }
      _companionFailures = 0;
      _nextCompanionPoll = DateTime.now().add(const Duration(seconds: 3));
      _update(
        (s) => s.copyWith(
          companionConnected: true,
          companionPeerId: peer.id,
          companionSnapshot: snapshot,
          companionHeartbeat: DateTime.now().toUtc(),
          companionLatencyMs: timer.elapsedMilliseconds,
          clearCompanionError: true,
        ),
      );
      _startCompanionStream(peer);
      if (shouldCatchUp) _requestCompanionSync(peer);
    } catch (e) {
      if (!_disposed) {
        final wasConnected = state.companionConnected;
        if (wasConnected) {
          unawaited(
            CompanionNotifications.connectionTransition(peer.id, false),
          );
        }
        _companionFailures = (_companionFailures + 1).clamp(1, 5).toInt();
        final delaySeconds = (3 * (1 << (_companionFailures - 1)))
            .clamp(3, 30)
            .toInt();
        _nextCompanionPoll = DateTime.now().add(
          Duration(seconds: delaySeconds),
        );
        _update(
          (s) => s.copyWith(companionConnected: false, companionError: _msg(e)),
        );
      }
    } finally {
      _pollingCompanion = false;
    }
  }

  Future<void> refreshCompanion() {
    _nextCompanionPoll = DateTime.fromMillisecondsSinceEpoch(0);
    return _pollCompanion();
  }

  Future<void> sweepLocalRecords() => _sweepNow();

  Future<void> selectCompanionPeer(String id) async {
    PeerDesktop? peer;
    for (final candidate in _store?.peers ?? const <PeerDesktop>[]) {
      if (candidate.id == id) peer = candidate;
    }
    if (peer == null || peer.id == state.companionPeerId) return;
    _stopCompanionStream();
    _nextCompanionPoll = DateTime.fromMillisecondsSinceEpoch(0);
    _update(
      (s) => s.copyWith(
        companionPeerId: id,
        companionConnected: false,
        clearCompanionSnapshot: true,
        clearCompanionHeartbeat: true,
        clearCompanionLatency: true,
        clearCompanionError: true,
      ),
    );
    await _pollCompanion();
  }

  void _stopCompanionStream() {
    _streamGeneration++;
    _streamRunning = false;
    _streamPeerId = null;
    final subscription = _companionStream;
    _companionStream = null;
    if (subscription != null) unawaited(subscription.cancel());
    _update((s) => s.copyWith(companionStreaming: false));
  }

  void _startCompanionStream(PeerDesktop peer) {
    if (_disposed || (_streamRunning && _streamPeerId == peer.id)) {
      return;
    }
    _stopCompanionStream();
    final generation = _streamGeneration;
    _streamPeerId = peer.id;
    _streamRunning = true;
    unawaited(_runCompanionStream(peer, generation));
  }

  Future<void> _runCompanionStream(PeerDesktop peer, int generation) async {
    var failures = 0;
    while (!_disposed && generation == _streamGeneration) {
      final client = _client;
      if (client == null) return;
      final finished = Completer<void>();
      Object? streamError;
      final subscription = client
          .watchCompanionEvents(peer, after: peer.eventCursor)
          .listen(
            (message) => unawaited(
              _handleCompanionStreamMessage(peer, message, generation),
            ),
            onError: (Object error, StackTrace _) {
              streamError = error;
              if (!finished.isCompleted) finished.complete();
            },
            onDone: () {
              if (!finished.isCompleted) finished.complete();
            },
            cancelOnError: true,
          );
      _companionStream = subscription;
      await finished.future;
      if (generation != _streamGeneration || _disposed) return;
      await subscription.cancel();
      _companionStream = null;
      _streamPeerId = null;
      _update((s) => s.copyWith(companionStreaming: false));
      if (streamError != null) {
        failures = (failures + 1).clamp(1, 5).toInt();
        final seconds = (1 << (failures - 1)).clamp(1, 30).toInt();
        _nextCompanionPoll = DateTime.fromMillisecondsSinceEpoch(0);
        unawaited(_pollCompanion());
        await Future<void>.delayed(Duration(seconds: seconds));
      } else {
        failures = 0;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (generation == _streamGeneration) {
      _streamRunning = false;
      _streamPeerId = null;
    }
  }

  Future<void> _handleCompanionStreamMessage(
    PeerDesktop peer,
    CompanionStreamMessage message,
    int generation,
  ) async {
    if (_disposed ||
        generation != _streamGeneration ||
        peer.id != _streamPeerId) {
      return;
    }
    final now = DateTime.now().toUtc();
    var cursorChanged = false;
    if (message.cursor > peer.eventCursor) {
      peer.eventCursor = message.cursor;
      cursorChanged = true;
    }
    var snapshot = state.companionSnapshot;
    final event = message.event;
    if (event != null) unawaited(CompanionNotifications.activity(event));
    if (event != null && !_companionEventIds.contains(event.id)) {
      _companionEventIds.add(event.id);
      if (_companionEventIds.length > 512) {
        _companionEventIds.remove(_companionEventIds.first);
      }
      if (snapshot != null) {
        final events = <CompanionActivityEvent>[
          event,
          ...snapshot.events.where((old) => old.id != event.id),
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        snapshot = snapshot.copyWith(
          events: events.take(100).toList(growable: false),
          serverTime: message.serverTime ?? now,
        );
      }
    }
    if (cursorChanged) await _store?.save();
    _nextCompanionPoll = DateTime.now().add(const Duration(seconds: 15));
    _update(
      (s) => s.copyWith(
        companionConnected: true,
        companionStreaming: true,
        companionSnapshot: snapshot,
        companionHeartbeat: now,
        clearCompanionError: true,
      ),
    );
    if (event != null) _requestCompanionSync(peer);
  }

  /// Coalesces live events and reconnect catch-up into durable sync runs. If a
  /// user started a sync, the newest event waits and triggers one follow-up.
  void _requestCompanionSync(PeerDesktop peer) {
    _queuedCompanionSync = peer;
    if (_disposed || _drainingCompanionSync) return;
    _drainingCompanionSync = true;
    unawaited(() async {
      try {
        while (!_disposed) {
          final next = _queuedCompanionSync;
          if (next == null) break;
          while (!_disposed && state.syncing) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          if (_disposed) break;
          _queuedCompanionSync = null;
          if (!(_store?.peers.any((candidate) => candidate.id == next.id) ??
              false)) {
            continue;
          }
          await syncNow(next, automatic: true);
        }
      } finally {
        _drainingCompanionSync = false;
        final queued = _queuedCompanionSync;
        if (queued != null && !_disposed) _requestCompanionSync(queued);
      }
    }());
  }

  /// Adds records that arrived from linked devices to this device's History.
  /// Runs only when the journal has grown, one run at a time.
  void _maybeImport() {
    final j = _journal;
    final s = _store;
    if (j == null || s == null || _importing || s.deviceId.isEmpty) return;
    if (j.length == _importedLen) return;
    _importing = true;
    final target = j.length;
    unawaited(() async {
      try {
        final n = await SyncImporter(
          store: j,
          ownDeviceId: s.deviceId,
          history: ref.read(historyRepositoryProvider),
          ocr: ref.read(ocrHistoryRepositoryProvider),
          inspection: ref.read(inspectionLogProvider),
          saveImage: (bytes, prefix, ext) => ref
              .read(imageStorageServiceProvider)
              .saveImageBytes(bytes, prefix: prefix, ext: ext),
        ).importNew();
        if (n > 0 && !_disposed) {
          ref.invalidate(historyControllerProvider);
          _log('imported $n record(s) from linked devices');
        }
      } catch (e) {
        _log('import skipped: ${e.runtimeType}');
      } finally {
        _importedLen = target;
        _importing = false;
      }
    }());
  }

  void _log(String message) {
    debugPrint('[EXALTED][LINK] $message');
    final commands = _server?.recentRemoteCommands;
    if (commands != null) {
      _update((s) => s.copyWith(remoteCommands: commands));
    }
  }

  // ------------------------------------------------------------ desktop

  Future<void> _ensureServer() async {
    final store = _store;
    final journal = _journal;
    if (store == null || journal == null) {
      throw LinkException('not_ready', 'Link storage is not ready yet.');
    }
    if (_server?.running ?? false) return;
    await store.ensureIdentity();
    final server = LinkServer(
      store: store,
      journal: journal,
      pairing: _pairing,
      approve: _askApproval,
      onEvent: _log,
      readHardwareStatus: _readExistingHardwareStatus,
      executeRemoteCommand: _executeRemoteScannerCommand,
    );
    final port = await server.start();
    _server = server;
    _lastDesktopSweep = DateTime.fromMillisecondsSinceEpoch(0);
    unawaited(_sweepNow());
    _update(
      (s) => s.copyWith(
        serverPort: port,
        remoteCommands: server.recentRemoteCommands,
      ),
    );
  }

  Map<String, Object?> _readExistingHardwareStatus() {
    final hardware = <String, Object?>{};
    if (ref.exists(keyenceScannerCoordinatorProvider)) {
      final keyence = ref.read(keyenceScannerCoordinatorProvider);
      hardware['keyence'] = {
        'status': keyence.status.name,
        'model': keyence.model,
        'scanCount': keyence.scanCount,
        if (keyence.lastScanTime != null)
          'lastScanTime': keyence.lastScanTime!.toUtc().toIso8601String(),
      };
    }
    if (ref.exists(scannerControllerProvider)) {
      final camera = ref.read(scannerControllerProvider);
      hardware['camera'] = {'status': camera.status.name};
    }
    return {'available': hardware.isNotEmpty, ...hardware};
  }

  Future<Map<String, Object?>> _executeRemoteScannerCommand(
    String action,
  ) async {
    final scanner = ref.read(scannerControllerProvider.notifier);
    switch (action) {
      case 'start':
        await scanner.start();
        final current = ref.read(scannerControllerProvider);
        if (current.status.name != 'ready' || current.camera == null) {
          return {
            'success': false,
            'message': 'No usable desktop camera is ready.',
          };
        }
        return {'success': true, 'message': 'Desktop scanning started.'};
      case 'stop':
        await scanner.stop();
        return ref.read(scannerControllerProvider).status.name == 'idle'
            ? {'success': true, 'message': 'Desktop scanning stopped.'}
            : {'success': false, 'message': 'Scanner did not stop.'};
      case 'pause':
        var current = ref.read(scannerControllerProvider);
        if (current.camera == null || current.status.name != 'ready') {
          return {
            'success': false,
            'message': 'Desktop scanner is unavailable.',
          };
        }
        if (!current.paused) await scanner.togglePause();
        current = ref.read(scannerControllerProvider);
        return current.paused
            ? {'success': true, 'message': 'Desktop scanning paused.'}
            : {'success': false, 'message': 'Scanner did not pause.'};
      case 'resume':
        var current = ref.read(scannerControllerProvider);
        if (current.camera == null || current.status.name != 'ready') {
          return {
            'success': false,
            'message': 'Desktop scanner is unavailable.',
          };
        }
        if (current.paused) await scanner.resumeScanning();
        current = ref.read(scannerControllerProvider);
        return !current.paused
            ? {'success': true, 'message': 'Desktop scanning resumed.'}
            : {'success': false, 'message': 'Scanner did not resume.'};
      default:
        return {'success': false, 'message': 'Unsupported scanner command.'};
    }
  }

  Future<bool> _askApproval(PairRequest request) {
    final old = _approval;
    if (old != null && !old.isCompleted) old.complete(false);
    final c = Completer<bool>();
    _approval = c;
    _update((s) => s.copyWith(pending: request));
    return c.future
        .timeout(const Duration(seconds: 90), onTimeout: () => false)
        .whenComplete(() {
          if (identical(_approval, c)) {
            _approval = null;
            _update((s) => s.copyWith(clearPending: true));
          }
        });
  }

  /// The owner's answer to a pending pairing request.
  void respondToPairing(bool allow) {
    final c = _approval;
    if (c != null && !c.isCompleted) c.complete(allow);
  }

  /// Opens the local service (if needed) and creates a one-time offer.
  /// [hosts] exists for tests; the app discovers its own addresses.
  Future<void> startPairing({List<String>? hosts}) async {
    final store = _store;
    if (store == null) return;
    _update((s) => s.copyWith(busy: true, clearError: true, clearNotice: true));
    try {
      await _ensureServer();
      final addresses = hosts ?? await localIPv4Addresses();
      if (addresses.isEmpty) {
        _update(
          (s) => s.copyWith(
            busy: false,
            error:
                'No local network address was found. Connect this computer '
                'to Wi-Fi or Ethernet and try again.',
          ),
        );
        return;
      }
      final offer = _pairing.create();
      final payload = PairingPayload(
        hosts: addresses,
        port: _server!.port,
        fingerprint: store.identity!.fingerprint,
        token: offer.token,
        expiresAt: offer.expiresAt,
        desktopName: store.deviceName,
      );
      _update((s) => s.copyWith(busy: false, payload: payload));
    } catch (e) {
      _update(
        (s) => s.copyWith(
          busy: false,
          error: 'Could not start pairing: ${_msg(e)}',
        ),
      );
    }
  }

  void cancelPairing() {
    _pairing.cancelAll();
    _update((s) => s.copyWith(clearPayload: true));
  }

  Future<void> revokeDevice(String id) async {
    final store = _store;
    if (store == null) return;
    await store.revoke(id);
    _refresh();
    _update((s) => s.copyWith(notice: 'Device access was revoked.'));
  }

  Future<void> setRemoteControlAuthorization(String id, bool allowed) async {
    final store = _store;
    if (store == null || !_isDesktop) return;
    await store.setRemoteControlAuthorization(id, allowed);
    _refresh();
  }

  Future<RemoteCommandResult> issueRemoteScannerCommand(
    PeerDesktop peer,
    String action,
  ) async {
    final client = _client;
    if (client == null || _isDesktop) {
      throw LinkException('not_ready', 'Remote controls are unavailable.');
    }
    final result = await client.remoteScannerCommand(peer, action);
    unawaited(CompanionNotifications.commandResult(result));
    unawaited(refreshCompanion());
    return result;
  }

  // -------------------------------------------------------------- phone

  /// Step 1: read a pairing code and show the desktop's identity. Nothing is
  /// sent to the network yet.
  void previewCode(String raw) {
    try {
      final p = PairingPayload.parse(raw.trim());
      if (p.isExpired(DateTime.now())) {
        throw LinkException(
          'expired',
          'This pairing code has expired. Create a new one on the desktop.',
        );
      }
      _update(
        (s) => s.copyWith(preview: p, clearError: true, clearNotice: true),
      );
    } on LinkException catch (e) {
      _update((s) => s.copyWith(clearPreview: true, error: e.message));
    }
  }

  void discardPreview() => _update((s) => s.copyWith(clearPreview: true));

  /// Step 2: the user confirmed the desktop. Pairing is complete only when
  /// the backend returns an authenticated peer.
  Future<void> confirmPair() async {
    final p = state.preview;
    final client = _client;
    if (p == null || client == null) return;
    _update((s) => s.copyWith(busy: true, clearError: true));
    try {
      final peer = await client.pair(
        p,
        platform: Platform.operatingSystem,
        appVersion: kLinkAppVersion,
      );
      _refresh();
      _update(
        (s) => s.copyWith(
          busy: false,
          clearPreview: true,
          notice: 'Linked to ${peer.name}.',
        ),
      );
    } catch (e) {
      _update((s) => s.copyWith(busy: false, error: _msg(e)));
    }
  }

  Future<void> syncNow(PeerDesktop peer, {bool automatic = false}) async {
    final client = _client;
    if (client == null || state.syncing) return;
    final startedAt = DateTime.now().toUtc();
    _update(
      (s) => s.copyWith(
        syncing: true,
        clearError: true,
        clearNotice: true,
        clearProgress: true,
      ),
    );
    try {
      // Journal every local record the journal does not have yet. A failure
      // here must not stop the sync itself.
      try {
        final ls = _store;
        final lj = _journal;
        if (ls != null && lj != null && ls.deviceId.isNotEmpty) {
          await SyncBridge(store: lj, deviceId: ls.deviceId).sweep(
            history: await ref.read(historyRepositoryProvider).loadAll(),
            ocr: await ref.read(ocrHistoryRepositoryProvider).loadAll(),
            inspection: await ref.read(inspectionLogProvider).loadAll(),
          );
        }
      } catch (e) {
        _log('sweep skipped: ${e.runtimeType}');
      }
      final summary = await client.syncNow(
        peer,
        onProgress: (p) => _update((s) => s.copyWith(progress: p)),
      );
      _maybeImport();
      unawaited(
        CompanionNotifications.syncResult(
          'sync:${peer.id}:${peer.lastSync?.toUtc().microsecondsSinceEpoch ?? DateTime.now().toUtc().microsecondsSinceEpoch}',
          success: true,
        ),
      );
      try {
        await _recordSyncSession(peer, startedAt, summary: summary);
      } catch (e) {
        _log('could not persist sync history: ${e.runtimeType}');
      }
      _refresh();
      await _refreshConflicts();
      _update(
        (s) => s.copyWith(
          syncing: false,
          clearProgress: true,
          summary: summary,
          notice: automatic ? null : 'Sync finished.',
        ),
      );
    } catch (e) {
      unawaited(
        CompanionNotifications.syncResult(
          'sync-failed:${peer.id}:${DateTime.now().toUtc().microsecondsSinceEpoch}',
          success: false,
        ),
      );
      try {
        await _recordSyncSession(peer, startedAt, error: _msg(e));
      } catch (historyError) {
        _log(
          'could not persist failed sync history: ${historyError.runtimeType}',
        );
      }
      await _refreshConflicts();
      _update(
        (s) => s.copyWith(
          syncing: false,
          clearProgress: true,
          error: 'Sync failed: ${_msg(e)}',
        ),
      );
    }
  }

  Future<void> _recordSyncSession(
    PeerDesktop peer,
    DateTime startedAt, {
    SyncSummary? summary,
    String? error,
  }) async {
    final journal = _journal;
    if (journal == null) return;
    await journal.recordSyncSession(
      SyncSessionEntry(
        peerId: peer.id,
        peerName: peer.name,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        succeeded: error == null,
        pushed: summary?.pushed ?? 0,
        pulled: summary?.pulled ?? 0,
        duplicates: summary?.duplicates ?? 0,
        conflicts: summary?.conflicts ?? 0,
        blobsUp: summary?.blobsUp ?? 0,
        blobsDown: summary?.blobsDown ?? 0,
        error: error,
      ),
    );
    _refreshSyncHistory();
  }

  /// Resolve a journal conflict without removing or rewriting either source
  /// record. The incoming variant can be kept as a separate local History row.
  Future<void> resolveConflict(
    SyncConflictCase conflict, {
    required bool saveIncomingCopy,
  }) async {
    final journal = _journal;
    final store = _store;
    if (journal == null || store == null) return;
    final key = '${conflict.incoming.id}:${conflict.incoming.contentHash}';
    if (!_resolvingConflicts.add(key)) return;
    try {
      if (saveIncomingCopy) {
        final copyId = await SyncImporter(
          store: journal,
          ownDeviceId: store.deviceId,
          history: ref.read(historyRepositoryProvider),
          ocr: ref.read(ocrHistoryRepositoryProvider),
          inspection: ref.read(inspectionLogProvider),
          saveImage: (bytes, prefix, ext) => ref
              .read(imageStorageServiceProvider)
              .saveImageBytes(bytes, prefix: prefix, ext: ext),
        ).saveConflictCopy(conflict.incoming);
        if (copyId == null) {
          _update(
            (s) => s.copyWith(error: 'This record type cannot be copied.'),
          );
          return;
        }
        await journal.resolveConflict(conflict.incoming, 'save_incoming_copy');
        ref.invalidate(historyControllerProvider);
        await _refreshConflicts();
        _update(
          (s) => s.copyWith(notice: 'Incoming version saved as $copyId.'),
        );
      } else {
        await journal.resolveConflict(conflict.incoming, 'keep_current');
        await _refreshConflicts();
        _update((s) => s.copyWith(notice: 'Current version kept.'));
      }
    } catch (e) {
      _update(
        (s) => s.copyWith(error: 'Could not resolve conflict: ${_msg(e)}'),
      );
    } finally {
      _resolvingConflicts.remove(key);
    }
  }

  Future<void> unlink(PeerDesktop peer) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.unlink(peer);
      _refresh();
      _update((s) => s.copyWith(notice: 'Unlinked from ${peer.name}.'));
    } catch (e) {
      _update(
        (s) => s.copyWith(
          error:
              'Could not reach the desktop to unlink: ${_msg(e)} '
              'You can remove it from this phone only.',
        ),
      );
    }
  }

  /// Removes the desktop from this phone without contacting it. Local records
  /// are kept.
  Future<void> removePeerLocally(String id) async {
    final store = _store;
    if (store == null) return;
    await store.removePeer(id);
    _refresh();
  }

  /// Changes where a linked desktop is reached, for example after its network
  /// address changed. Only the stored address changes. The pairing secret and
  /// the pinned certificate fingerprint stay as they are, so only the same
  /// desktop is accepted at the new address. Returns an error message, or null.
  Future<String?> updatePeerAddress(String id, String host, String port) async {
    final problem = validatePeerAddress(host, port);
    if (problem != null) return problem;
    final store = _store;
    if (store == null) return 'Link storage is not ready yet.';
    PeerDesktop? peer;
    for (final p in store.peers) {
      if (p.id == id) peer = p;
    }
    if (peer == null) return 'This desktop is no longer linked.';
    peer.host = host.trim();
    peer.port = int.parse(port.trim());
    await store.save();
    _refresh();
    _update((s) => s.copyWith(notice: 'Address updated. Try Sync now.'));
    return null;
  }

  /// Number of records waiting to be sent to [peer].
  int pendingFor(PeerDesktop peer) {
    final j = _journal;
    final s = _store;
    if (j == null || s == null || s.deviceId.isEmpty) return 0;
    return pendingCount(j, s.deviceId, peer.pushCursor);
  }

  /// Journals every local record not yet in the journal (phone only), so the
  /// waiting count is right. Never throws.
  Future<void> _sweepNow() async {
    if (_sweeping || _disposed) return;
    _sweeping = true;
    try {
      final ls = _store;
      final lj = _journal;
      if (ls == null || lj == null || ls.deviceId.isEmpty) return;
      await SyncBridge(store: lj, deviceId: ls.deviceId).sweep(
        history: await ref.read(historyRepositoryProvider).loadAll(),
        ocr: await ref.read(ocrHistoryRepositoryProvider).loadAll(),
        inspection: await ref.read(inspectionLogProvider).loadAll(),
      );
      _update((s) => s.copyWith());
    } catch (e) {
      _log('startup sweep skipped: ${e.runtimeType}');
    } finally {
      _sweeping = false;
    }
  }

  void clearMessages() =>
      _update((s) => s.copyWith(clearError: true, clearNotice: true));
}

/// Parses a STUN Binding success response and returns the public address the
/// server saw (XOR-MAPPED-ADDRESS, IPv4). Returns null for anything that is not
/// a valid response to the request that used transaction id [txn].
StunCandidate? parseStunBindingResponse(Uint8List data, Uint8List txn) {
  if (data.length < 20 || txn.length != 12) return null;
  final view = ByteData.sublistView(data);
  if (view.getUint16(0) != 0x0101) return null; // Binding success
  if (view.getUint32(4) != 0x2112A442) return null; // magic cookie
  for (var i = 0; i < 12; i++) {
    if (data[8 + i] != txn[i]) return null;
  }
  final end = math.min(20 + view.getUint16(2), data.length);
  const cookie = <int>[0x21, 0x12, 0xA4, 0x42];
  var offset = 20;
  while (offset + 4 <= end) {
    final type = view.getUint16(offset);
    final length = view.getUint16(offset + 2);
    final value = offset + 4;
    if (value + length > end) return null;
    if (type == 0x0020 && length >= 8 && data[value + 1] == 0x01) {
      final port = view.getUint16(value + 2) ^ 0x2112;
      final host = [for (var i = 0; i < 4; i++) data[value + 4 + i] ^ cookie[i]]
          .join('.');
      return StunCandidate(host: host, port: port);
    }
    offset = value + ((length + 3) & ~3);
  }
  return null;
}

/// Cross-network connection manager.
///
/// Today this only discovers this device's public address through STUN. No
/// peer transport (signaling, hole punching, TURN relay) exists yet, so it
/// never reports a connection: [connected] is false and [mode] is null until a
/// real transport is implemented and verified.
class CrossNetworkLinker {
  CrossNetworkLinker({
    required this.config,
    required this.store,
    required this.journal,
    required this.deviceId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CrossNetworkConfig config;
  final LinkStore store;
  final FileSyncStore journal;
  final String deviceId;
  final DateTime Function() _clock;

  StunCandidate? _publicCandidate;
  DateTime? _discoveredAt;
  String? _lastAttemptPeerId;

  /// Whether cross-network infrastructure is configured.
  bool get isAvailable =>
      config.enableRelay &&
      (config.stunServers.isNotEmpty ||
          config.turnServers.isNotEmpty ||
          config.signalingBaseUrl.isNotEmpty);

  /// No peer transport exists yet, so this is always false.
  bool get connected => false;

  LinkConnectionMode? get mode => null;

  /// Public address learned from the last successful STUN discovery.
  StunCandidate? get publicCandidate => _publicCandidate;
  DateTime? get discoveredAt => _discoveredAt;
  String? get lastAttemptPeerId => _lastAttemptPeerId;

  /// Asks each configured STUN server for this device's public address.
  Future<StunCandidate?> discoverStun() async {
    for (final server in config.stunServers) {
      RawDatagramSocket? socket;
      try {
        final targets = await InternetAddress.lookup(
          server.host,
          type: InternetAddressType.IPv4,
        );
        if (targets.isEmpty) continue;
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        final rng = math.Random.secure();
        final txn = Uint8List.fromList(
          List<int>.generate(12, (_) => rng.nextInt(256)),
        );
        final request = Uint8List(20);
        final view = ByteData.sublistView(request);
        view.setUint16(0, 0x0001); // Binding request
        view.setUint16(2, 0); // no attributes
        view.setUint32(4, 0x2112A442); // magic cookie
        request.setRange(8, 20, txn);
        final response = _awaitStunResponse(socket, txn);
        socket.send(request, targets.first, server.port);
        final mapped = await response.timeout(const Duration(seconds: 3));
        if (mapped != null) return mapped;
      } catch (_) {
        continue;
      } finally {
        socket?.close();
      }
    }
    return null;
  }

  Future<StunCandidate?> _awaitStunResponse(
    RawDatagramSocket socket,
    Uint8List txn,
  ) {
    final done = Completer<StunCandidate?>();
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final mapped = parseStunBindingResponse(datagram.data, txn);
        if (mapped != null && !done.isCompleted) done.complete(mapped);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(null);
      },
    );
    return done.future;
  }

  /// Runs STUN discovery for [peer]. Returns false: discovery alone does not
  /// connect to a peer, and no relay or hole-punching transport exists yet.
  Future<bool> connectPeer(PeerDesktop peer) async {
    _lastAttemptPeerId = peer.id;
    if (!isAvailable) return false;
    _publicCandidate = await discoverStun();
    _discoveredAt = _clock();
    return false;
  }

  void disconnect() {
    _publicCandidate = null;
    _discoveredAt = null;
    _lastAttemptPeerId = null;
  }
}

/// Provider for the cross-network linker. The stores load asynchronously, so
/// this is a FutureProvider.
final crossNetworkLinkerProvider = FutureProvider<CrossNetworkLinker>((
  ref,
) async {
  final config = ref.watch(crossNetworkConfigProvider);
  final store = await ref.watch(linkStoreProvider.future);
  final journal = await ref.watch(linkJournalProvider.future);
  return CrossNetworkLinker(
    config: config,
    store: store,
    journal: journal,
    deviceId: store.deviceId,
  );
});
