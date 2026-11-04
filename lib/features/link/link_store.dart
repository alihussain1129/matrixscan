import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'link_cert.dart';
import 'link_crypto.dart';
import 'link_models.dart';

/// Linking state in its own file. It never touches the history databases.
class LinkStore {
  LinkStore(this.dir);

  final Directory dir;
  String deviceId = '';
  String deviceName = 'Exalted';
  LinkIdentity? identity;
  final List<LinkedDevice> devices = [];
  final List<PeerDesktop> peers = [];

  Future<void> _queue = Future<void>.value();

  File get _file =>
      File('${dir.path}${Platform.pathSeparator}link_state.json');

  Future<void> load() async {
    await dir.create(recursive: true);
    if (await _file.exists()) {
      try {
        final j = jsonDecode(await _file.readAsString());
        if (j is Map) {
          deviceId = (j['deviceId'] as String?) ?? '';
          deviceName = (j['deviceName'] as String?) ?? deviceName;
          final id = j['identity'];
          if (id is Map && id['cert'] is String && id['key'] is String) {
            identity = LinkIdentity(id['cert'] as String, id['key'] as String);
          }
          for (final d in (j['devices'] as List? ?? const [])) {
            final x = LinkedDevice.fromJson(d);
            if (x != null) devices.add(x);
          }
          for (final p in (j['peers'] as List? ?? const [])) {
            final x = PeerDesktop.fromJson(p);
            if (x != null) peers.add(x);
          }
        }
      } catch (_) {
        try {
          await _file.copy('${_file.path}.corrupt');
        } catch (_) {}
      }
    }
    if (deviceId.isEmpty) {
      deviceId = randomToken(12);
      await save();
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
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'deviceId': deviceId,
        'deviceName': deviceName,
        'identity': identity == null
            ? null
            : {'cert': identity!.certPem, 'key': identity!.keyPem},
        'devices': [for (final d in devices) d.toJson()],
        'peers': [for (final p in peers) p.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
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
