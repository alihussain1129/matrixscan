import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/config/app_config.dart';
import 'link_cert.dart';
import 'link_crypto.dart';
import 'link_models.dart';

/// In-memory credential vault for deterministic unit tests only. Production
/// construction supplies the operating system-backed secret store.
class InMemoryLinkSecretStore implements SecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// Linking state in its own file. It never touches the history databases.
class LinkStore {
  // Keep the public `secretStore:` argument stable while storing it privately.
  LinkStore(this.dir, {required SecretStore secretStore})
    // ignore: prefer_initializing_formals
    : _secretStore = secretStore;

  static const _format = 3;
  static const _vaultKey = 'exalted.link.credentials.v1';

  final Directory dir;
  final SecretStore _secretStore;
  String deviceId = '';
  String deviceName = 'Exalted';
  LinkIdentity? identity;
  final List<LinkedDevice> devices = [];
  final List<PeerDesktop> peers = [];

  Future<void> _queue = Future<void>.value();

  File get _file => File('${dir.path}${Platform.pathSeparator}link_state.json');

  Future<void> load() async {
    await dir.create(recursive: true);
    await _restrictDirectory();
    if (await _file.exists()) {
      try {
        final raw = jsonDecode(await _file.readAsString());
        if (raw is! Map) throw const FormatException('state is not an object');
        if (raw['format'] == _format) {
          await _loadProtected(raw, '$_vaultKey.${raw['secretDigest']}');
          final retired = await _cleanupRetiredKeys(raw);
          await _persistRetiredKeys(retired);
        } else if (raw['format'] == 2) {
          // Read the original protected format so existing installations can
          // upgrade transactionally on their next save.
          await _loadProtected(raw, _vaultKey);
          await _write();
        } else {
          await _migrateLegacy(raw);
        }
      } catch (_) {
        await _preserveCorruptState();
        rethrow;
      }
    }
    if (deviceId.isEmpty) {
      deviceId = randomToken(12);
      await save();
    }
  }

  Future<void> _loadProtected(Map raw, String vaultKey) async {
    final stored = await _secretStore.read(vaultKey);
    if (stored == null) {
      throw const FormatException('link credentials unavailable');
    }
    final secret = jsonDecode(stored);
    if (secret is! Map ||
        raw['secretDigest'] is! String ||
        !constantTimeEquals(
          raw['secretDigest'] as String,
          sha256Hex(utf8.encode(canonicalJson(secret))),
        )) {
      throw const FormatException('link credential integrity check failed');
    }
    _readState(raw, secret);
  }

  Future<List<String>> _cleanupRetiredKeys(Map raw) async {
    final keys = raw['retiredSecretKeys'];
    if (keys is! List) return const [];
    final remaining = <String>[];
    for (final key in keys.whereType<String>()) {
      if (key != '$_vaultKey.${raw['secretDigest']}') {
        try {
          await _secretStore.delete(key);
        } catch (_) {
          // The current credential generation is already committed. Keep the
          // public retirement list so cleanup can be retried next launch.
          remaining.add(key);
        }
      }
    }
    return remaining;
  }

  Future<void> _persistRetiredKeys(List<String> keys) async {
    try {
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! Map) return;
      raw['retiredSecretKeys'] = keys;
      final tmp = File('${_file.path}.cleanup.tmp');
      await tmp.writeAsString(jsonEncode(raw), flush: true);
      await _restrictFile(tmp);
      await tmp.rename(_file.path);
      await _restrictFile(_file);
    } catch (_) {
      // Cleanup metadata is advisory. The committed current vault entry stays
      // valid, and any remaining old keys will be retried on the next load.
    }
  }

  Future<void> _migrateLegacy(Map raw) async {
    final secret = _secretsFromLegacy(raw);
    _readState(raw, secret);
    final backup = File(
      '${_file.path}.legacy-${DateTime.now().toUtc().millisecondsSinceEpoch}.json',
    );
    await _file.copy(backup.path);
    await _restrictFile(backup);
    await _write();
  }

  Map<String, Object?> _secretsFromLegacy(Map raw) {
    final deviceSecrets = <String, String>{};
    final peerSecrets = <String, String>{};
    for (final value in raw['devices'] as List? ?? const []) {
      if (value is Map && value['id'] is String && value['secret'] is String) {
        deviceSecrets[value['id'] as String] = value['secret'] as String;
      }
    }
    for (final value in raw['peers'] as List? ?? const []) {
      if (value is Map && value['id'] is String && value['secret'] is String) {
        peerSecrets[value['id'] as String] = value['secret'] as String;
      }
    }
    return <String, Object?>{
      'identity': raw['identity'],
      'deviceSecrets': deviceSecrets,
      'peerSecrets': peerSecrets,
    };
  }

  void _readState(Map raw, Map secret) {
    deviceId = (raw['deviceId'] as String?) ?? '';
    deviceName = (raw['deviceName'] as String?) ?? deviceName;
    final id = secret['identity'];
    if (id is Map && id['cert'] is String && id['key'] is String) {
      identity = LinkIdentity(id['cert'] as String, id['key'] as String);
    }
    final deviceSecrets = secret['deviceSecrets'];
    final peerSecrets = secret['peerSecrets'];
    for (final value in raw['devices'] as List? ?? const []) {
      if (value is! Map || value['id'] is! String || deviceSecrets is! Map) {
        continue;
      }
      final hidden = deviceSecrets[value['id']];
      final parsed = hidden is String
          ? LinkedDevice.fromJson({...value, 'secret': hidden})
          : null;
      if (parsed != null) devices.add(parsed);
    }
    for (final value in raw['peers'] as List? ?? const []) {
      if (value is! Map || value['id'] is! String || peerSecrets is! Map) {
        continue;
      }
      final hidden = peerSecrets[value['id']];
      final parsed = hidden is String
          ? PeerDesktop.fromJson({...value, 'secret': hidden})
          : null;
      if (parsed != null) peers.add(parsed);
    }
  }

  Future<void> ensureIdentity() async {
    if (identity != null) return;
    identity = await generateLinkIdentity(deviceName);
    await save();
  }

  Future<void> save() {
    final next = _queue.then((_) => _write());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write() async {
    final secret = <String, Object?>{
      'identity': identity == null
          ? null
          : {'cert': identity!.certPem, 'key': identity!.keyPem},
      'deviceSecrets': {for (final d in devices) d.id: d.secretB64},
      'peerSecrets': {for (final p in peers) p.id: p.secretB64},
    };
    final secretJson = jsonEncode(secret);
    final digest = sha256Hex(utf8.encode(canonicalJson(secret)));
    final nextVaultKey = '$_vaultKey.$digest';
    final retiredKeys = <String>{};
    if (await _file.exists()) {
      try {
        final previous = jsonDecode(await _file.readAsString());
        if (previous is Map) {
          final oldDigest = previous['secretDigest'];
          if (previous['format'] == _format && oldDigest is String) {
            retiredKeys.add('$_vaultKey.$oldDigest');
          } else if (previous['format'] == 2) {
            retiredKeys.add(_vaultKey);
          }
          final oldRetired = previous['retiredSecretKeys'];
          if (oldRetired is List) {
            retiredKeys.addAll(oldRetired.whereType<String>());
          }
        }
      } on FormatException {
        // The caller's load/migration path reports malformed state before a
        // normal save can occur. A new state has no prior vault generation.
      }
    }
    retiredKeys.remove(nextVaultKey);
    await _secretStore.write(nextVaultKey, secretJson);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'format': _format,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'secretDigest': digest,
        'retiredSecretKeys': retiredKeys.toList()..sort(),
        'devices': [for (final d in devices) _publicDevice(d)],
        'peers': [for (final p in peers) _publicPeer(p)],
      }),
      flush: true,
    );
    await _restrictFile(tmp);
    await tmp.rename(_file.path);
    await _restrictFile(_file);
    final remainingRetired = await _cleanupRetiredKeys({
      'secretDigest': digest,
      'retiredSecretKeys': retiredKeys.toList(),
    });
    await _persistRetiredKeys(remainingRetired);
  }

  Map<String, Object?> _publicDevice(LinkedDevice d) {
    final value = d.toJson();
    value.remove('secret');
    return value;
  }

  Map<String, Object?> _publicPeer(PeerDesktop p) {
    final value = p.toJson();
    value.remove('secret');
    return value;
  }

  Future<void> _restrictDirectory() async {
    if (!Platform.isWindows) {
      await _chmod('700', dir.path);
    }
  }

  Future<void> _restrictFile(File file) async {
    if (!Platform.isWindows) {
      await _chmod('600', file.path);
    }
  }

  /// Dart does not expose chmod. On POSIX targets this is an explicit security
  /// requirement, so a failure is surfaced instead of leaving a wider mode.
  Future<void> _chmod(String mode, String path) async {
    final result = await Process.run('chmod', <String>[mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not restrict link state permissions',
        path,
      );
    }
  }

  Future<void> _preserveCorruptState() async {
    try {
      await _file.copy(
        '${_file.path}.corrupt-${DateTime.now().toUtc().millisecondsSinceEpoch}',
      );
    } catch (_) {}
  }

  LinkedDevice? deviceById(String id) {
    for (final d in devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> addDevice(LinkedDevice d) async {
    devices.removeWhere((x) => x.id == d.id);
    devices.add(d);
    await save();
  }

  /// After this, the device can no longer sign in. Its records stay.
  Future<void> revoke(String id) async {
    final d = deviceById(id);
    if (d == null) return;
    d.revoked = true;
    await save();
  }

  /// Explicit desktop-owner opt-in for remote scanner actions from one phone.
  Future<void> setRemoteControlAuthorization(String id, bool allowed) async {
    final device = deviceById(id);
    if (device == null || device.revoked) return;
    device.remoteControlAuthorized = allowed;
    await save();
  }

  Future<void> addPeer(PeerDesktop p) async {
    peers.removeWhere((x) => x.id == p.id);
    peers.add(p);
    await save();
  }

  Future<void> removePeer(String id) async {
    peers.removeWhere((x) => x.id == id);
    await save();
  }
}
