import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'link_crypto.dart';
import 'link_journal.dart';
import 'link_models.dart';
import 'link_pairing.dart';
import 'link_store.dart';

class PairRequest {
  PairRequest({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.appVersion,
  });
  final String deviceId;
  final String name;
  final String platform;
  final String appVersion;
}

class _HttpError implements Exception {
  _HttpError(this.status, this.code);
  final int status;
  final String code;
}

/// The desktop side. HTTPS with the pinned self-signed certificate.
/// Only private-network callers are served; every call except /v1/ping and
/// /v1/pair must carry a valid signature from a linked, non-revoked device.
class LinkServer {
  LinkServer({
    required this.store,
    required this.journal,
    required this.pairing,
    required this.approve,
    this.onEvent,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const int maxJson = 4 << 20;
  static const int maxBlob = 64 << 20;
  static const int _skewMs = 120000;

  final LinkStore store;
  final FileSyncStore journal;
  final PairingManager pairing;

  /// Asks the desktop owner. Return true to allow the new device.
  final Future<bool> Function(PairRequest request) approve;
  final void Function(String message)? onEvent;
  final DateTime Function() _clock;

  HttpServer? _server;
  final Map<String, int> _nonces = {};

  int get port => _server?.port ?? 0;
  bool get running => _server != null;

  Future<int> start({int preferredPort = 47821}) async {
    final id = store.identity;
    if (id == null) {
      throw LinkException('no_identity', 'Create the desktop identity first.');
    }
    final ctx = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(id.certPem))
      ..usePrivateKeyBytes(utf8.encode(id.keyPem));
    try {
      _server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        preferredPort,
        ctx,
      );
    } on SocketException {
      _server = await HttpServer.bindSecure(InternetAddress.anyIPv4, 0, ctx);
    }
    _server!.listen(
      (r) => unawaited(_handle(r)),
      onError: (Object e) => onEvent?.call('connection error: $e'),
    );
    return _server!.port;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      final remote = r.connectionInfo?.remoteAddress;
      if (remote == null || !isPrivateAddress(remote)) {
        throw _HttpError(403, 'forbidden');
      }
      await _route(r).timeout(const Duration(seconds: 150));
    } on _HttpError catch (e) {
      await _send(r, e.status, {'error': e.code});
    } catch (e) {
      onEvent?.call('request error: $e');
      await _send(r, 500, {'error': 'server_error'});
    }
  }

  Future<void> _send(HttpRequest r, int status, Object body) async {
    try {
      r.response.statusCode = status;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(body));
      await r.response.close();
    } catch (_) {}
  }

  Future<Uint8List> _readBody(HttpRequest r, int max) async {
    if (r.contentLength > max) throw _HttpError(413, 'too_large');
    final b = BytesBuilder(copy: false);
    var n = 0;
    await for (final c in r) {
      n += c.length;
      if (n > max) throw _HttpError(413, 'too_large');
      b.add(c);
    }
    return b.takeBytes();
  }

  Future<void> _route(HttpRequest r) async {
    final path = r.uri.path;
    final m = r.method;
    if (m == 'GET' && path == '/v1/ping') {
      return _send(r, 200, {'app': 'exalted', 'v': 1});
    }
    final body = await _readBody(
      r,
      path.startsWith('/v1/blob/') ? maxBlob : maxJson,
    );
    if (m == 'POST' && path == '/v1/pair') return _pair(r, body);

    final dev = _auth(r, body);
    if (dev == null) throw _HttpError(401, 'unauthorized');
    dev.lastSeen = _clock();

    if (m == 'GET' && path == '/v1/status') {
      return _send(r, 200, {
        'deviceId': store.deviceId,
        'name': store.deviceName,
        'lastSeq': journal.lastSeq,
      });
    }
    if (m == 'POST' && path == '/v1/blobs/missing') {
      final j = _jsonBody(body);
      final hashes = j['hashes'];
      if (hashes is! List || hashes.length > 1000) {
        throw _HttpError(400, 'bad_request');
      }
      final missing = <String>[];
      for (final h in hashes) {
        if (h is! String || !isSha256Hex(h)) throw _HttpError(400, 'bad_hash');
        if (!await journal.hasBlob(h)) missing.add(h);
      }
      return _send(r, 200, {'missing': missing});
    }
    if (m == 'POST' && path == '/v1/sync/push') return _push(r, dev, body);
    if (m == 'GET' && path == '/v1/sync/pull') return _pull(r, dev);
    if (path.startsWith('/v1/blob/')) {
      final sha = path.substring('/v1/blob/'.length);
      if (!isSha256Hex(sha)) throw _HttpError(400, 'bad_hash');
      if (m == 'PUT') {
        try {
          await journal.putBlob(sha, body);
        } on FormatException {
          throw _HttpError(400, 'hash_mismatch');
        }
        return _send(r, 200, {'ok': true});
      }
      if (m == 'GET') {
        final bytes = await journal.getBlob(sha);
        if (bytes == null) throw _HttpError(404, 'not_found');
        r.response.statusCode = 200;
        r.response.headers.contentType = ContentType.binary;
        r.response.add(bytes);
        await r.response.close();
        return;
      }
    }
    if (m == 'POST' && path == '/v1/unlink') {
      await store.revoke(dev.id);
      onEvent?.call('${dev.name} unlinked itself');
      return _send(r, 200, {'ok': true});
    }
    throw _HttpError(404, 'not_found');
  }

  Map<String, dynamic> _jsonBody(Uint8List body) {
    try {
      final j = jsonDecode(utf8.decode(body));
      if (j is Map<String, dynamic>) return j;
    } catch (_) {}
    throw _HttpError(400, 'bad_request');
  }

  Future<void> _pair(HttpRequest r, Uint8List body) async {
    final j = _jsonBody(body);
    final token = j['token'];
    final id = j['deviceId'];
    if (token is! String || id is! String || id.isEmpty || id.length > 100) {
      throw _HttpError(400, 'bad_request');
    }
    if (!pairing.consume(token)) {
      throw _HttpError(403, 'pairing_invalid_or_expired');
    }
    String cap(Object? v, int n) {
      final s = v is String ? v : '';
      return s.length > n ? s.substring(0, n) : s;
    }

    final req = PairRequest(
      deviceId: id,
      name: cap(j['name'], 60).isEmpty ? 'Device' : cap(j['name'], 60),
      platform: cap(j['platform'], 30),
      appVersion: cap(j['appVersion'], 30),
    );
    final ok = await approve(req)
        .timeout(const Duration(seconds: 90), onTimeout: () => false);
    if (!ok) throw _HttpError(403, 'rejected');
    final secret = randomBytes(32);
    await store.addDevice(
      LinkedDevice(
        id: req.deviceId,
        name: req.name,
        platform: req.platform,
        appVersion: req.appVersion,
        pairedAt: _clock(),
        secretB64: base64.encode(secret),
      ),
    );
    onEvent?.call('paired ${req.name}');
    await _send(r, 200, {
      'deviceId': store.deviceId,
      'name': store.deviceName,
      'secret': base64.encode(secret),
    });
  }

  LinkedDevice? _auth(HttpRequest r, Uint8List body) {
    final id = r.headers.value('x-exalted-device');
    final tsRaw = r.headers.value('x-exalted-ts');
    final nonce = r.headers.value('x-exalted-nonce');
    final sig = r.headers.value('x-exalted-sig');
    if (id == null || tsRaw == null || nonce == null || sig == null) {
      return null;
    }
    final ts = int.tryParse(tsRaw);
    if (ts == null || nonce.length < 8 || nonce.length > 64) return null;
    final now = _clock().millisecondsSinceEpoch;
    if ((now - ts).abs() > _skewMs) return null;
    final dev = store.deviceById(id);
    if (dev == null || dev.revoked) return null;
    final expected = signRequest(
      base64.decode(dev.secretB64),
      r.method,
      pathAndQuery(r.uri),
      ts,
      nonce,
      sha256Hex(body),
    );
    if (!constantTimeEquals(sig, expected)) return null;
    final key = '$id:$nonce';
    if (_nonces.containsKey(key)) return null;
    _nonces[key] = ts;
    if (_nonces.length > 5000) {
      _nonces.removeWhere((_, t) => (now - t).abs() > _skewMs);
    }
    return dev;
  }

  Future<void> _push(HttpRequest r, LinkedDevice dev, Uint8List body) async {
    final j = _jsonBody(body);
    final list = j['records'];
    if (list is! List || list.length > 500) {
      throw _HttpError(400, 'bad_request');
    }
    var added = 0, duplicate = 0, conflict = 0;
    final rejected = <String>[];
    for (final item in list) {
      final rec = SyncRecord.fromJson(item);
      if (rec == null) {
        rejected.add('invalid');
        continue;
      }
      // A device may only add records that it created itself.
      if (rec.originDeviceId != dev.id) {
        rejected.add(rec.id);
        continue;
      }
      var blobsOk = true;
      for (final b in rec.blobs) {
        if (!await journal.hasBlob(b)) blobsOk = false;
      }
      if (!blobsOk) {
        rejected.add(rec.id);
        continue;
      }
      switch (await journal.add(rec)) {
        case IngestResult.added:
          added++;
        case IngestResult.duplicate:
          duplicate++;
        case IngestResult.conflict:
          conflict++;
      }
    }
    dev.lastSync = _clock();
    await store.save();
    await _send(r, 200, {
      'added': added,
      'duplicate': duplicate,
      'conflict': conflict,
      'rejected': rejected,
    });
  }

  Future<void> _pull(HttpRequest r, LinkedDevice dev) async {
    final after = int.tryParse(r.uri.queryParameters['after'] ?? '') ?? 0;
    final limit = (int.tryParse(r.uri.queryParameters['limit'] ?? '') ?? 100)
        .clamp(1, 200);
    final page = journal.page(
      after: after < 0 ? 0 : after,
      limit: limit,
      excludeOrigin: dev.id,
    );
    await _send(r, 200, {
      'records': [for (final e in page.entries) e.rec.toJson()],
      'next': page.next,
      'more': page.more,
    });
  }
}
