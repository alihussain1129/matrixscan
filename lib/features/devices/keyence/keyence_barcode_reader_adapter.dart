import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/device_adapter.dart';
import '../core/device_backend_factory.dart';
import '../core/device_exception.dart';
import '../core/device_models.dart';
import 'keyence_sr751_client.dart';
import 'sr751_message_classifier.dart';

/// Documented default, offered as a suggestion only. The real port is
/// whatever the reader is configured to use.
const int kKeyenceSuggestedTcpPort = 9004;

const Set<DeviceCapability> kKeyenceSr751Capabilities = {
  DeviceCapability.decodedReads,
  DeviceCapability.commandResponses,
  DeviceCapability.softwareTrigger,
  DeviceCapability.connectionMonitoring,
  DeviceCapability.diagnostics,
};

DeviceIdentity keyenceSr751Identity({
  required String host,
  required int port,
  String? displayName,
}) {
  return DeviceIdentity.create(
    manufacturer: 'KEYENCE',
    model: 'SR-751',
    interfaceType: DeviceInterfaceType.ethernet,
    transport: DeviceTransport.tcp,
    ipAddress: host,
    port: port,
    displayName: displayName,
  );
}

/// Reads the optional `receiveTerminator` setting: CR, LF or CRLF. Anything
/// else keeps the client's tolerant default (CR, LF or CRLF all accepted).
List<int>? keyenceTerminatorFromConfiguration(
  DeviceConfiguration configuration,
) {
  switch (configuration.values['receiveTerminator']) {
    case 'CR':
      return const [0x0D];
    case 'LF':
      return const [0x0A];
    case 'CRLF':
      return const [0x0D, 0x0A];
    default:
      return null;
  }
}

/// A SR-751 whose address and port the user has configured.
class KeyenceConfiguredDeviceSource implements DeviceDiscoverySource {
  KeyenceConfiguredDeviceSource(Iterable<DeviceIdentity> devices)
    : _devices = List<DeviceIdentity>.of(devices);

  final List<DeviceIdentity> _devices;

  @override
  String get id => 'keyence-configured';

  @override
  Future<List<DeviceIdentity>> discover() async =>
      List<DeviceIdentity>.of(_devices);
}

/// The KEYENCE SR-751 as a barcode reader, on top of the existing
/// [KeyenceSr751Client]. It is not a camera: it has no frames.
///
/// Limits, stated plainly:
/// * Connecting cannot be aborted (the client uses a plain socket connect),
///   so [supportsCancellation] is false and a cancelled connect ends at the
///   connect timeout.
/// * Which lines are barcodes depends on the [Sr751ReplyProfile]. The default
///   keeps the client's behaviour; command replies are not separated until
///   verified reply formats are configured.
/// * Image (FTP) retrieval is not part of this adapter yet.
class KeyenceSr751ReaderAdapter
    implements
        DeviceAdapter,
        ReadEventSource,
        CommandResponseSource,
        SoftwareTriggerable {
  KeyenceSr751ReaderAdapter(
    this._client, {
    required this.host,
    required this.port,
    Sr751MessageClassifier? classifier,
    this.connectTimeout = const Duration(seconds: 4),
    this.ownsClient = true,
    DateTime Function()? clock,
  }) : _classifier = classifier ?? Sr751MessageClassifier(),
       _clock = clock ?? DateTime.now {
    _scanSub = _client.scanStream.listen(_onScan);
    _statusSub = _client.statusStream.listen(_onStatus);
  }

  final KeyenceSr751Client _client;
  final String host;
  final int port;
  final Duration connectTimeout;

  /// When true, [dispose] disposes the client too.
  final bool ownsClient;
  final Sr751MessageClassifier _classifier;
  final DateTime Function() _clock;

  final StreamController<DeviceReadEvent> _reads =
      StreamController<DeviceReadEvent>.broadcast();
  final StreamController<DeviceCommandResponse> _responses =
      StreamController<DeviceCommandResponse>.broadcast();
  final StreamController<DeviceLinkEvent> _links =
      StreamController<DeviceLinkEvent>.broadcast();
  StreamSubscription<KeyenceScanResult>? _scanSub;
  StreamSubscription<KeyenceConnectionStatus>? _statusSub;

  bool _disposed = false;
  bool _established = false;
  bool _linkUp = false;

  int _barcodeCount = 0;
  int _failureCount = 0;
  int _responseCount = 0;
  int _statusCount = 0;
  int _unknownCount = 0;
  final List<String> _recentUnknown = <String>[];

  @override
  String get backendId => 'keyence-sr751';

  @override
  Set<DeviceCapability> get capabilities => kKeyenceSr751Capabilities;

  @override
  bool get supportsCancellation => false;

  @override
  bool get reconnectsAutomatically => _client.autoReconnect;

  @override
  Stream<DeviceLinkEvent> get linkEvents => _links.stream;

  @override
  Stream<DeviceReadEvent> get reads => _reads.stream;

  @override
  Stream<DeviceCommandResponse> get commandResponses => _responses.stream;

  @override
  Future<void> connect(CancelToken cancel) async {
    _ensureOpen();
    _throwIfCancelled(cancel);
    final connected = await _client.connect(
      targetHost: host,
      targetPort: port,
      timeout: connectTimeout,
    );
    if (!connected) {
      final reason = _client.lastError;
      // The hub decides what happens after a failed connect, so stop the
      // client's own endless retry loop.
      await _client.disconnect();
      throw DeviceException(
        DeviceFailureKind.connectionFailed,
        'Could not connect to $host:$port'
        '${reason == null ? '' : ': $reason'}',
      );
    }
    if (cancel.isCancelled) {
      await _client.disconnect();
      _throwIfCancelled(cancel);
    }
    _established = true;
    _linkUp = true;
  }

  @override
  Future<void> disconnect() async {
    _established = false;
    _linkUp = false;
    _classifier.clearPending();
    await _client.disconnect();
  }

  /// Sends a raw command and remembers it so its reply can be matched.
  Future<bool> sendCommand(String command) async {
    _ensureOpen();
    _classifier.noteCommandSent(command.trim());
    final sent = await _client.sendCommand(command);
    if (!sent) _classifier.clearPending();
    return sent;
  }

  @override
  Future<void> triggerSoftware() async {
    if (!await sendCommand('LON')) {
      throw const DeviceException(
        DeviceFailureKind.connectionFailed,
        'The reader is not connected',
      );
    }
  }

  @override
  Future<Map<String, Object?>> diagnostics() async => {
    'backend': backendId,
    'host': host,
    'port': port,
    'clientStatus': _client.status.name,
    'linkUp': _linkUp,
    'reconnectAttempts': _client.reconnectAttempts,
    'lastError': _client.lastError,
    'replyProfile': _classifier.profileName,
    'barcodeReads': _barcodeCount,
    'readFailures': _failureCount,
    'commandResponses': _responseCount,
    'statusMessages': _statusCount,
    'unknownMessages': _unknownCount,
    'recentUnknown': List<String>.of(_recentUnknown),
  };

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _established = false;
    _linkUp = false;
    await _scanSub?.cancel();
    await _statusSub?.cancel();
    if (ownsClient) {
      _client.dispose();
    } else {
      await _client.disconnect();
    }
    await _reads.close();
    await _responses.close();
    await _links.close();
  }

  void _onStatus(KeyenceConnectionStatus status) {
    if (_disposed || !_established || _links.isClosed) return;
    switch (status) {
      case KeyenceConnectionStatus.connected:
        if (!_linkUp) {
          _linkUp = true;
          _links.add(const DeviceLinkEvent.up());
        }
      case KeyenceConnectionStatus.error:
      case KeyenceConnectionStatus.disconnected:
        if (_linkUp) {
          _linkUp = false;
          _links.add(DeviceLinkEvent.down(_client.lastError));
        }
      case KeyenceConnectionStatus.connecting:
        break;
    }
  }

  void _onScan(KeyenceScanResult result) {
    if (_disposed) return;
    final raw = result.rawResponse.isNotEmpty
        ? result.rawResponse
        : result.data;
    final c = _classifier.classify(raw);
    final now = _clock();
    switch (c.kind) {
      case Sr751MessageKind.barcode:
        _barcodeCount++;
        if (!_reads.isClosed) {
          _reads.add(
            DeviceReadEvent(data: c.payload, timestamp: now, raw: raw),
          );
        }
      case Sr751MessageKind.readFailure:
        _failureCount++;
        if (!_reads.isClosed) {
          _reads.add(
            DeviceReadEvent(
              data: '',
              timestamp: now,
              success: false,
              errorMessage: c.detail,
              raw: raw,
            ),
          );
        }
      case Sr751MessageKind.commandResponse:
        _responseCount++;
        if (!_responses.isClosed) {
          _responses.add(
            DeviceCommandResponse(
              response: raw,
              timestamp: now,
              command: c.command ?? '',
            ),
          );
        }
      case Sr751MessageKind.status:
        _statusCount++;
        if (!_responses.isClosed) {
          _responses.add(DeviceCommandResponse(response: raw, timestamp: now));
        }
      case Sr751MessageKind.unknown:
        _unknownCount++;
        final safe = _safeText(raw);
        _recentUnknown.add(safe);
        if (_recentUnknown.length > 20) _recentUnknown.removeAt(0);
        debugPrint('[KEYENCE][CLASSIFY] unknown message: $safe');
      case Sr751MessageKind.ignored:
        break;
    }
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const DeviceException(
        DeviceFailureKind.disposed,
        'KEYENCE reader adapter is disposed',
      );
    }
  }

  void _throwIfCancelled(CancelToken cancel) {
    if (cancel.isCancelled) {
      throw const DeviceException(
        DeviceFailureKind.cancelled,
        'Operation cancelled',
      );
    }
  }

  /// Printable ASCII only and bounded, so an odd line cannot corrupt a log or
  /// the diagnostics panel.
  static String _safeText(String text, {int maxChars = 80}) {
    final out = StringBuffer();
    var count = 0;
    for (final rune in text.runes) {
      if (count >= maxChars) {
        out.write('...');
        break;
      }
      if (rune >= 0x20 && rune < 0x7F) {
        out.writeCharCode(rune);
      } else {
        out.write('\\u{${rune.toRadixString(16)}}');
      }
      count++;
    }
    return out.toString();
  }
}

bool _supportsSr751(DeviceIdentity identity) {
  final host = identity.ipAddress;
  return identity.transport == DeviceTransport.tcp &&
      identity.manufacturer.trim().toLowerCase() == 'keyence' &&
      RegExp(
        r'^sr-?7\d\d$',
        caseSensitive: false,
      ).hasMatch(identity.model.trim()) &&
      host != null &&
      host.trim().isNotEmpty &&
      identity.port != null;
}

/// Registers the SR-751 reader backend. The address and port always come from
/// the device identity, never from a built-in default.
BackendRegistration keyenceSr751Registration({
  Sr751ReplyProfile profile = const Sr751ReplyProfile.legacy(),
  Duration connectTimeout = const Duration(seconds: 4),
  bool ownsClient = true,
  KeyenceSr751Client Function(
    DeviceIdentity identity,
    DeviceConfiguration configuration,
  )?
  clientFactory,
}) {
  return BackendRegistration(
    backendId: 'keyence-sr751',
    capabilities: kKeyenceSr751Capabilities,
    supports: _supportsSr751,
    create: (identity, configuration) {
      final host = identity.ipAddress!;
      final port = identity.port!;
      final client =
          clientFactory?.call(identity, configuration) ??
          KeyenceSr751Client(
            defaultHost: host,
            defaultPort: port,
            receiveTerminator: keyenceTerminatorFromConfiguration(
              configuration,
            ),
          );
      return KeyenceSr751ReaderAdapter(
        client,
        host: host,
        port: port,
        classifier: Sr751MessageClassifier(profile: profile),
        connectTimeout: connectTimeout,
        ownsClient: ownsClient,
      );
    },
  );
}
