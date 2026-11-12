import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'link_crypto.dart';
import 'link_journal.dart';
import 'link_models.dart';
import 'link_pairing.dart';
import 'link_store.dart';

class _Resp {
  _Resp(this.status, this.body);
  final int status;
  final Uint8List body;
}

/// The phone side. Trusts only the desktop whose certificate fingerprint it
/// got from the QR code.
class LinkClient {
  LinkClient({
    required this.store,
    required this.journal,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LinkStore store;
  final FileSyncStore journal;
  final DateTime Function() _clock;

  HttpClient _newHttp(String fingerprint) {
    final c = HttpClient(context: SecurityContext(withTrustedRoots: false));
    c.badCertificateCallback = (X509Certificate cert, String host, int port) =>
        sha256Hex(cert.der) == fingerprint;
    c.connectionTimeout = const Duration(seconds: 6);
    return c;
  }

  static String _friendly(String code) {
    switch (code) {
      case 'pairing_invalid_or_expired':
        return 'The pairing code is expired or was already used. Create a new one on the desktop.';
      case 'rejected':
        return 'The desktop owner did not approve this device.';
      case 'unauthorized':
        return 'This desktop no longer trusts this device. Link it again.';
      case 'remote_control_disabled':
        return 'The desktop owner has not authorized scanner control for this phone.';
      case 'command_id_conflict':
        return 'This command identifier was already used for another action.';
      case 'bad_command':
        return 'The desktop rejected an invalid scanner command.';
      case 'too_large':
        return 'The data was too large for one request.';
      default:
        return 'The desktop reported an error ($code).';
    }
  }

  Future<_Resp> _send(
    HttpClient http,
    String method,
    Uri uri, {
    List<int> body = const <int>[],
    PeerDesktop? sign,
    bool binary = false,
    Duration timeout = const Duration(seconds: 30),
    int maxBytes = 80 << 20,
  }) async {
    try {
      final req = await http.openUrl(method, uri);
      if (sign != null) {
        final ts = _clock().millisecondsSinceEpoch;
        final nonce = randomToken(12);
        final sig = signRequest(
          base64.decode(sign.secretB64),
          method,
          pathAndQuery(uri),
          ts,
          nonce,
          sha256Hex(body),
        );
        req.headers
          ..set('x-exalted-device', store.deviceId)
          ..set('x-exalted-ts', '$ts')
          ..set('x-exalted-nonce', nonce)
          ..set('x-exalted-sig', sig);
      }
      if (body.isNotEmpty) {
        req.headers.contentType = binary
            ? ContentType.binary
            : ContentType.json;
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(timeout);
      final bb = BytesBuilder(copy: false);
      var n = 0;
      await for (final chunk in res.timeout(timeout)) {
        n += chunk.length;
        if (n > maxBytes) {
          throw LinkException('too_large', 'The reply was too large.');
        }
        bb.add(chunk);
      }
      return _Resp(res.statusCode, bb.takeBytes());
    } on TimeoutException {
      throw LinkException(
        'timeout',
        'The desktop did not answer in time.',
        retryable: true,
      );
    } on TlsException {
      throw LinkException(
        'untrusted_desktop',
        'Security check failed. This is not the desktop you paired with.',
      );
    } on SocketException catch (e) {
      throw LinkException(
        'network',
        'Cannot reach the desktop: ${e.message}',
        retryable: true,
      );
    } on HttpException catch (e) {
      throw LinkException(
        'network',
        'Connection problem: ${e.message}',
        retryable: true,
      );
    }
  }

  Map<String, dynamic> _decode(_Resp r) {
    Object? j;
    try {
      j = jsonDecode(utf8.decode(r.body));
    } catch (_) {}
    if (r.status == 200 && j is Map<String, dynamic>) return j;
    final code = j is Map && j['error'] is String
        ? j['error'] as String
        : 'http_${r.status}';
    throw LinkException(code, _friendly(code), retryable: r.status >= 500);
  }

  Future<Map<String, dynamic>> _json(
    HttpClient http,
    PeerDesktop peer,
    String method,
    String target, {
    Object? body,
  }) async {
    final uri = Uri.parse('https://${peer.host}:${peer.port}$target');
    final res = await _send(
      http,
      method,
      uri,
      body: body == null ? const <int>[] : utf8.encode(jsonEncode(body)),
      sign: peer,
    );
    return _decode(res);
  }

  Future<T> _retry<T>(Future<T> Function() f) async {
    var delay = const Duration(milliseconds: 400);
    for (var i = 0; ; i++) {
      try {
        return await f();
      } on LinkException catch (e) {
        if (!e.retryable || i >= 2) rethrow;
        await Future<void>.delayed(delay);
        delay *= 3;
      }
    }
  }

  /// Pairs with a desktop from the scanned (or pasted) pairing code.
  Future<PeerDesktop> pair(
    PairingPayload p, {
    required String platform,
    required String appVersion,
  }) async {
    if (p.isExpired(_clock())) {
      throw LinkException(
        'expired',
        'This pairing code has expired. Create a new one on the desktop.',
      );
    }
    final http = _newHttp(p.fingerprint);
    try {
      LinkException? last;
      for (final host in p.hosts) {
        try {
          final uri = Uri.parse('https://$host:${p.port}/v1/pair');
          final res = await _send(
            http,
            'POST',
            uri,
            body: utf8.encode(
              jsonEncode({
                'token': p.token,
                'deviceId': store.deviceId,
                'name': store.deviceName,
                'platform': platform,
                'appVersion': appVersion,
              }),
            ),
            timeout: const Duration(seconds: 100),
          );
          final j = _decode(res);
          final secret = j['secret'];
          final id = j['deviceId'];
          if (secret is! String ||
              id is! String ||
              base64.decode(secret).length != 32) {
            throw LinkException(
              'bad_reply',
              'The desktop sent an invalid reply.',
            );
          }
          final peer = PeerDesktop(
            id: id,
            name: (j['name'] as String?) ?? p.desktopName,
            host: host,
            port: p.port,
            fingerprint: p.fingerprint,
            secretB64: secret,
            pairedAt:
                DateTime.tryParse(j['serverTime'] as String? ?? '') ?? _clock(),
            eventCursor: (j['lastSeq'] as num?)?.toInt() ?? 0,
          );
          await store.addPeer(peer);
          return peer;
        } on LinkException catch (e) {
          if (!e.retryable) rethrow;
          last = e;
        }
      }
      throw last ?? LinkException('network', 'Cannot reach the desktop.');
    } finally {
      http.close(force: true);
    }
  }

  /// Fetches the authenticated live companion snapshot from a paired desktop.
  /// A successful reply is the heartbeat; pairing alone does not mean online.
  Future<CompanionSnapshot> fetchCompanionSnapshot(PeerDesktop peer) async {
    final http = _newHttp(peer.fingerprint);
    try {
      final body = await _json(http, peer, 'GET', '/v1/companion/snapshot');
      final snapshot = CompanionSnapshot.fromJson(body);
      if (snapshot == null || snapshot.deviceId != peer.id) {
        throw LinkException(
          'bad_companion_snapshot',
          'The linked desktop returned invalid status data.',
        );
      }
      return snapshot;
    } finally {
      http.close(force: true);
    }
  }

  /// Sends one idempotent scanner command over the existing pinned, signed
  /// channel. Commands are never queued locally for offline execution.
  Future<RemoteCommandResult> remoteScannerCommand(
    PeerDesktop peer,
    String action, {
    String? commandId,
  }) async {
    const actions = {'start', 'stop', 'pause', 'resume'};
    if (!actions.contains(action)) {
      throw LinkException('bad_command', 'Unsupported scanner command.');
    }
    final id = commandId ?? randomToken(18);
    final http = _newHttp(peer.fingerprint);
    try {
      final value = await _json(
        http,
        peer,
        'POST',
        '/v1/companion/commands',
        body: {'commandId': id, 'action': action},
      );
      if (value['id'] != id ||
          value['action'] != action ||
          value['state'] is! String ||
          value['message'] is! String) {
        throw LinkException(
          'bad_reply',
          'Invalid command result from desktop.',
        );
      }
      return RemoteCommandResult(
        commandId: id,
        action: action,
        state: value['state'] as String,
        message: value['message'] as String,
      );
    } finally {
      http.close(force: true);
    }
  }

  /// Opens the pinned-TLS, HMAC-authenticated event stream. Event cursors are
  /// included in the signed URL so reconnects replay anything not yet stored.
  Stream<CompanionStreamMessage> watchCompanionEvents(
    PeerDesktop peer, {
    required int after,
  }) async* {
    final http = _newHttp(peer.fingerprint);
    WebSocket? socket;
    try {
      final uri = Uri(
        scheme: 'wss',
        host: peer.host,
        port: peer.port,
        path: '/v1/companion/events',
        queryParameters: {'after': '$after'},
      );
      final ts = _clock().millisecondsSinceEpoch;
      final nonce = randomToken(12);
      final signature = signRequest(
        base64.decode(peer.secretB64),
        'GET',
        pathAndQuery(uri),
        ts,
        nonce,
        sha256Hex(const <int>[]),
      );
      socket = await WebSocket.connect(
        uri.toString(),
        customClient: http,
        headers: {
          'x-exalted-device': store.deviceId,
          'x-exalted-ts': '$ts',
          'x-exalted-nonce': nonce,
          'x-exalted-sig': signature,
        },
        maxPayloadLength: 1 << 20,
      ).timeout(const Duration(seconds: 10));
      socket.pingInterval = const Duration(seconds: 15);
      await for (final frame in socket.timeout(const Duration(seconds: 35))) {
        if (frame is! String || frame.length > (1 << 20)) {
          throw LinkException('bad_stream_message', 'Invalid event frame.');
        }
        Object? decoded;
        try {
          decoded = jsonDecode(frame);
        } catch (_) {
          throw LinkException('bad_stream_message', 'Invalid event frame.');
        }
        final message = CompanionStreamMessage.fromJson(decoded);
        if (message == null || message.cursor < after) {
          throw LinkException('bad_stream_message', 'Invalid event frame.');
        }
        yield message;
      }
      throw LinkException(
        'stream_closed',
        'The desktop event stream closed.',
        retryable: true,
      );
    } on LinkException {
      rethrow;
    } on TimeoutException {
      throw LinkException(
        'stream_timeout',
        'The desktop event stream timed out.',
        retryable: true,
      );
    } on TlsException {
      throw LinkException(
        'untrusted_desktop',
        'Security check failed. This is not the desktop you paired with.',
      );
    } on SocketException {
      throw LinkException(
        'network',
        'Cannot reach the desktop event stream.',
        retryable: true,
      );
    } on WebSocketException {
      throw LinkException(
        'stream_unavailable',
        'The desktop event stream is unavailable.',
        retryable: true,
      );
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
      http.close(force: true);
    }
  }

  /// Push own new records, then pull new records from the desktop.
  /// Safe to repeat and safe to interrupt: cursors move only after a page is
  /// fully stored, and nothing local is ever deleted.
  Future<SyncSummary> syncNow(
    PeerDesktop peer, {
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final http = _newHttp(peer.fingerprint);
    final s = SyncSummary();
    try {
      await _pushAll(http, peer, s, onProgress);
      await _pullAll(http, peer, s, onProgress);
      peer.lastSync = _clock();
      await store.save();
      return s;
    } finally {
      http.close(force: true);
    }
  }

  Future<void> _pushAll(
    HttpClient http,
    PeerDesktop peer,
    SyncSummary s,
    void Function(SyncProgress)? onProgress,
  ) async {
    var imagesUploaded = 0;
    var recordsProcessed = 0;
    while (true) {
      final page = journal.page(
        after: peer.pushCursor,
        limit: 100,
        onlyOrigin: store.deviceId,
      );
      if (page.entries.isNotEmpty) {
        final hashes = <String>{for (final e in page.entries) ...e.rec.blobs}
            .toList();
        if (hashes.isNotEmpty) {
          final res = await _retry(
            () => _json(
              http,
              peer,
              'POST',
              '/v1/blobs/missing',
              body: {'hashes': hashes},
            ),
          );
          final missing = (res['missing'] as List? ?? const []).cast<String>();
          for (final h in missing) {
            final bytes = await journal.getBlob(h);
            if (bytes == null) {
              throw LinkException(
                'local_image_missing',
                'A local original image is missing: $h',
              );
            }
            final uri = Uri.parse(
              'https://${peer.host}:${peer.port}/v1/blob/$h',
            );
            await _retry(() async {
              final r = await _send(
                http,
                'PUT',
                uri,
                body: bytes,
                sign: peer,
                binary: true,
                timeout: const Duration(seconds: 120),
              );
              _decode(r);
            });
            s.blobsUp++;
            imagesUploaded++;
            onProgress?.call(
              SyncProgress('Uploading images', imagesUploaded, 0),
            );
          }
        }
        final res = await _retry(
          () => _json(
            http,
            peer,
            'POST',
            '/v1/sync/push',
            body: {
              'records': [for (final e in page.entries) e.rec.toJson()],
            },
          ),
        );
        final rejected = (res['rejected'] as List? ?? const []);
        if (rejected.isNotEmpty) {
          throw LinkException(
            'push_rejected',
            'The desktop rejected ${rejected.length} record(s).',
          );
        }
        s.pushed += (res['added'] as int? ?? 0);
        s.duplicates += (res['duplicate'] as int? ?? 0);
        s.conflicts += (res['conflict'] as int? ?? 0);
        recordsProcessed += page.entries.length;
        onProgress?.call(
          SyncProgress('Uploading records', recordsProcessed, 0),
        );
      }
      peer.pushCursor = page.next;
      await store.save();
      if (!page.more) break;
    }
  }

  Future<void> _pullAll(
    HttpClient http,
    PeerDesktop peer,
    SyncSummary s,
    void Function(SyncProgress)? onProgress,
  ) async {
    var recordsProcessed = 0;
    while (true) {
      final res = await _retry(
        () => _json(
          http,
          peer,
          'GET',
          '/v1/sync/pull?after=${peer.pullCursor}&limit=100',
        ),
      );
      final list = res['records'] as List? ?? const [];
      for (final item in list) {
        final rec = SyncRecord.fromJson(item);
        if (rec == null) {
          throw LinkException(
            'bad_record',
            'The desktop sent a damaged record.',
          );
        }
        for (final b in rec.blobs) {
          if (await journal.hasBlob(b)) continue;
          final uri = Uri.parse('https://${peer.host}:${peer.port}/v1/blob/$b');
          final bytes = await _retry(() async {
            final r = await _send(
              http,
              'GET',
              uri,
              sign: peer,
              timeout: const Duration(seconds: 120),
            );
            if (r.status != 200) _decode(r);
            return r.body;
          });
          try {
            await journal.putBlob(b, bytes);
          } on FormatException {
            throw LinkException(
              'integrity',
              'An image failed its hash check and was discarded.',
            );
          }
          s.blobsDown++;
        }
        switch (await journal.add(rec)) {
          case IngestResult.added:
            s.pulled++;
          case IngestResult.duplicate:
            s.duplicates++;
          case IngestResult.conflict:
            s.conflicts++;
        }
        recordsProcessed++;
      }
      onProgress?.call(
        SyncProgress('Downloading records', recordsProcessed, 0),
      );
      final next = res['next'];
      if (next is! int) {
        throw LinkException('bad_reply', 'Invalid reply from desktop.');
      }
      peer.pullCursor = next;
      await store.save();
      if (res['more'] != true) break;
    }
  }

  /// Best-effort notice to the desktop, then forget it locally.
  Future<void> unlink(PeerDesktop peer) async {
    final http = _newHttp(peer.fingerprint);
    try {
      await _json(http, peer, 'POST', '/v1/unlink', body: {});
    } catch (_) {
      // The desktop may be offline. Local unlink still happens.
    } finally {
      http.close(force: true);
    }
    await store.removePeer(peer.id);
  }
}
