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
    this.readHardwareStatus,
    this.executeRemoteCommand,
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
  final Map<String, Object?> Function()? readHardwareStatus;
  final Future<Map<String, Object?>> Function(String action)?
  executeRemoteCommand;
  final DateTime Function() _clock;

  HttpServer? _server;
  final Map<String, int> _nonces = {};
  final Map<String, WebSocket> _streams = {};
  final Map<String, Map<String, Object?>> _commandHistory = {};
  final Map<String, Future<Map<String, Object?>>> _commandTasks = {};
  Future<void> _auditQueue = Future<void>.value();

  File get _commandLog =>
      File('${store.dir.path}${Platform.pathSeparator}remote_commands.jsonl');

  int get port => _server?.port ?? 0;
  bool get running => _server != null;
  List<Map<String, Object?>> get recentRemoteCommands {
    final values = _commandHistory.values.toList()
      ..sort(
        (a, b) => (b['updatedAt'] as String? ?? '').compareTo(
          a['updatedAt'] as String? ?? '',
        ),
      );
    return values.take(50).map(Map<String, Object?>.of).toList(growable: false);
  }

  Future<int> start({int preferredPort = 47821}) async {
    final id = store.identity;
    if (id == null) {
      throw LinkException('no_identity', 'Create the desktop identity first.');
    }
    await _loadCommandHistory();
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
    final streams = _streams.values.toList(growable: false);
    _streams.clear();
    for (final stream in streams) {
      try {
        await stream.close(WebSocketStatus.goingAway, 'desktop stopping');
      } catch (_) {}
    }
    await s?.close(force: true);
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      final remote = r.connectionInfo?.remoteAddress;
      if (remote == null || !isPrivateAddress(remote)) {
        throw _HttpError(403, 'forbidden');
      }
      final route = _route(r);
      if (r.uri.path == '/v1/companion/events') {
        await route;
      } else {
        await route.timeout(const Duration(seconds: 150));
      }
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
    if (m == 'GET' && path == '/v1/companion/snapshot') {
      await store.save();
      return _send(r, 200, _companionSnapshot());
    }
    if (m == 'POST' && path == '/v1/companion/commands') {
      return _remoteCommand(r, dev, body);
    }
    if (m == 'GET' && path == '/v1/companion/events') {
      if (!WebSocketTransformer.isUpgradeRequest(r)) {
        throw _HttpError(400, 'websocket_required');
      }
      final after = int.tryParse(r.uri.queryParameters['after'] ?? '');
      if (after == null || after < 0 || after > journal.lastSeq) {
        throw _HttpError(400, 'bad_event_cursor');
      }
      return _streamEvents(r, dev, after);
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

  Future<void> _loadCommandHistory() async {
    _commandHistory.clear();
    _commandTasks.clear();
    if (!await _commandLog.exists()) return;
    final lines = await _commandLog.readAsLines();
    for (final line in lines) {
      try {
        final value = jsonDecode(line);
        if (value is Map && value['id'] is String) {
          final entry = Map<String, Object?>.from(value);
          _commandHistory[entry['id'] as String] = entry;
        }
      } catch (_) {
        // Keep malformed lines for audit; later valid entries remain usable.
      }
    }
    final interrupted = <Map<String, Object?>>[];
    for (final entry in _commandHistory.values) {
      if (entry['state'] == 'accepted' || entry['state'] == 'executing') {
        entry['state'] = 'failed';
        entry['message'] = 'Desktop restarted before confirmation.';
        entry['updatedAt'] = _clock().toUtc().toIso8601String();
        interrupted.add(entry);
      }
    }
    for (final value in interrupted) {
      await _appendCommand(value);
    }
  }

  Future<void> _appendCommand(Map<String, Object?> command) {
    final next = _auditQueue.then((_) async {
      await _commandLog.parent.create(recursive: true);
      var prefix = '';
      if (await _commandLog.exists() && await _commandLog.length() > 0) {
        final reader = await _commandLog.open(mode: FileMode.read);
        try {
          await reader.setPosition(await _commandLog.length() - 1);
          if (await reader.readByte() != 10) prefix = '\n';
        } finally {
          await reader.close();
        }
      }
      await _commandLog.writeAsString(
        '$prefix${jsonEncode(command)}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
    _auditQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _recordCommand(Map<String, Object?> command) async {
    command['updatedAt'] = _clock().toUtc().toIso8601String();
    _commandHistory[command['id'] as String] = command;
    await _appendCommand(command);
    onEvent?.call('remote command ${command['state']}: ${command['action']}');
  }

  Future<void> _remoteCommand(
    HttpRequest request,
    LinkedDevice device,
    Uint8List body,
  ) async {
    if (!device.remoteControlAuthorized) {
      throw _HttpError(403, 'remote_control_disabled');
    }
    final value = _jsonBody(body);
    final id = value['commandId'];
    final action = value['action'];
    const actions = {'start', 'stop', 'pause', 'resume'};
    if (id is! String ||
        id.length < 16 ||
        id.length > 128 ||
        action is! String ||
        !actions.contains(action) ||
        value.length != 2) {
      throw _HttpError(400, 'bad_command');
    }
    final inFlight = _commandTasks[id];
    if (inFlight != null) {
      return _send(request, 200, await inFlight);
    }
    final existing = _commandHistory[id];
    if (existing != null) {
      if (existing['deviceId'] != device.id || existing['action'] != action) {
        throw _HttpError(409, 'command_id_conflict');
      }
      return _send(request, 200, existing);
    }
    final task = _commandTasks.putIfAbsent(
      id,
      () => _executeRemoteCommand(id, device, action),
    );
    final result = await task;
    _commandTasks.remove(id);
    return _send(request, 200, result);
  }

  Future<Map<String, Object?>> _executeRemoteCommand(
    String id,
    LinkedDevice device,
    String action,
  ) async {
    final now = _clock().toUtc().toIso8601String();
    final command = <String, Object?>{
      'id': id,
      'deviceId': device.id,
      'action': action,
      'state': 'accepted',
      'createdAt': now,
      'updatedAt': now,
      'message': 'Command accepted by the desktop.',
    };
    await _recordCommand(command);
    if (store.deviceById(device.id)?.revoked != false) {
      command['state'] = 'rejected';
      command['message'] = 'Device authorization was revoked.';
      await _recordCommand(command);
      return Map<String, Object?>.of(command);
    }
    command['state'] = 'executing';
    command['message'] = 'Executing on the desktop scanner.';
    await _recordCommand(command);
    try {
      final execute = executeRemoteCommand;
      if (execute == null) throw StateError('remote scanner unavailable');
      final result = await execute(action).timeout(const Duration(seconds: 30));
      command.addAll(result);
      command['state'] = result['success'] == true ? 'completed' : 'failed';
      command['message'] = result['message'] ?? 'Scanner command failed.';
    } on TimeoutException {
      command['state'] = 'timed_out';
      command['message'] = 'Scanner did not confirm the command in time.';
    } catch (_) {
      command['state'] = 'failed';
      command['message'] =
          'The desktop scanner could not execute this command.';
    }
    await _recordCommand(command);
    return Map<String, Object?>.of(command);
  }

  Map<String, Object?> _companionSnapshot() {
    final now = _clock();
    final records = journal.allRecords();
    final ownToday = records
        .where((record) {
          final local = record.createdAt.toLocal();
          final today = now.toLocal();
          return record.originDeviceId == store.deviceId &&
              local.year == today.year &&
              local.month == today.month &&
              local.day == today.day;
        })
        .toList(growable: false);
    int count(SyncKind kind) =>
        ownToday.where((record) => record.kind == kind).length;

    final inspections = ownToday
        .where((record) => record.kind == SyncKind.inspection)
        .toList(growable: false);
    final events = records.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    String textValue(SyncRecord record, List<String> keys) {
      for (final key in keys) {
        final value = record.payload[key];
        if (value is String && value.trim().isNotEmpty) {
          final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
          return normalized.length > 240
              ? '${normalized.substring(0, 237)}…'
              : normalized;
        }
      }
      return 'Record saved';
    }

    String sourceName(String id) {
      if (id == store.deviceId) return store.deviceName;
      for (final device in store.devices) {
        if (device.id == id && !device.revoked) return device.name;
      }
      return 'Linked device';
    }

    final recentEvents = events
        .take(100)
        .map((record) {
          final format = record.payload['format'];
          final status = switch (record.kind) {
            SyncKind.inspection => record.payload['status'] as String?,
            SyncKind.ocr =>
              record.payload['ocvPassed'] == true
                  ? 'pass'
                  : record.payload['ocvPassed'] == false
                  ? 'fail'
                  : null,
            _ => 'success',
          };
          final title = switch (record.kind) {
            SyncKind.decoder =>
              format is String && format.isNotEmpty
                  ? format
                  : 'Barcode decoded',
            SyncKind.ocr => 'OCR completed',
            SyncKind.inspection => 'Inspection ${status ?? 'recorded'}',
            SyncKind.image => 'Image received',
          };
          return <String, Object?>{
            'id': record.id,
            'type': record.kind.name,
            'title': title,
            'detail': textValue(record, ['text', 'raw', 'ocrText']),
            'sourceDeviceId': record.originDeviceId,
            'sourceDeviceName': sourceName(record.originDeviceId),
            'createdAt': record.createdAt.toUtc().toIso8601String(),
            'status': status,
          };
        })
        .toList(growable: false);
    final passed = inspections
        .where((record) => record.payload['status'] == 'pass')
        .length;
    final failed = inspections
        .where((record) => record.payload['status'] == 'fail')
        .length;
    final review = inspections
        .where((record) => record.payload['status'] == 'review')
        .length;
    final onlineDevices = store.devices.where((device) {
      final lastSeen = device.lastSeen;
      return !device.revoked &&
          lastSeen != null &&
          now.difference(lastSeen).abs() <= const Duration(seconds: 45);
    }).length;

    Map<String, Object?> hardware;
    try {
      hardware = readHardwareStatus?.call() ?? const {'available': false};
    } catch (_) {
      hardware = const {'available': false};
    }

    return {
      'deviceId': store.deviceId,
      'name': store.deviceName,
      'platform': Platform.operatingSystem,
      'serverTime': now.toUtc().toIso8601String(),
      'todayScans': count(SyncKind.decoder),
      'todayOcr': count(SyncKind.ocr),
      'todayInspections': inspections.length,
      'passedInspections': passed,
      'failedInspections': failed,
      'reviewInspections': review,
      'activeLinkedDevices': onlineDevices,
      'hardware': hardware,
      'events': recentEvents,
    };
  }

  Future<void> _streamEvents(
    HttpRequest request,
    LinkedDevice device,
    int after,
  ) async {
    if (_streams.length >= 32 && !_streams.containsKey(device.id)) {
      throw _HttpError(503, 'too_many_streams');
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final previous = _streams[device.id];
    _streams[device.id] = socket;
    if (previous != null && !identical(previous, socket)) {
      unawaited(previous.close(4001, 'replaced by a newer connection'));
    }
    socket.pingInterval = const Duration(seconds: 15);
    device.lastSeen = _clock();
    unawaited(store.save());

    var cursor = after;
    var publishing = false;
    var lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);

    Future<void> publish() async {
      if (publishing || socket.closeCode != null) return;
      publishing = true;
      try {
        while (socket.closeCode == null) {
          final page = journal.page(
            after: cursor,
            limit: 100,
            excludeOrigin: device.id,
          );
          if (page.entries.isEmpty) break;
          for (final entry in page.entries) {
            final event = _activityEvent(entry.rec);
            socket.add(
              jsonEncode({
                'kind': 'event',
                'eventId': event.id,
                'cursor': entry.seq,
                'serverTime': _clock().toUtc().toIso8601String(),
                'event': event.toJson(),
              }),
            );
            cursor = entry.seq;
          }
          if (!page.more) break;
        }
        final now = _clock();
        if (now.difference(lastHeartbeat) >= const Duration(seconds: 10)) {
          lastHeartbeat = now;
          device.lastSeen = now;
          socket.add(
            jsonEncode({
              'kind': 'heartbeat',
              'cursor': cursor,
              'serverTime': now.toUtc().toIso8601String(),
            }),
          );
        }
      } catch (error) {
        onEvent?.call('companion stream stopped (${error.runtimeType})');
        try {
          await socket.close(WebSocketStatus.internalServerError);
        } catch (_) {}
      } finally {
        publishing = false;
      }
    }

    socket.add(
      jsonEncode({
        'kind': 'ready',
        'cursor': cursor,
        'serverTime': _clock().toUtc().toIso8601String(),
      }),
    );
    final changes = journal.changes.listen((_) => unawaited(publish()));
    await publish();
    // The journal stream wakes delivery immediately. This timer only supplies
    // the required heartbeat and stale-connection detection.
    final timer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(publish());
    });
    try {
      await socket.done;
    } catch (_) {
      // Network disconnects are normal; the client reconnects with its cursor.
    } finally {
      timer.cancel();
      await changes.cancel();
      if (identical(_streams[device.id], socket)) _streams.remove(device.id);
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  CompanionActivityEvent _activityEvent(SyncRecord record) {
    final format = record.payload['format'];
    final status = switch (record.kind) {
      SyncKind.inspection => record.payload['status'] as String?,
      SyncKind.ocr =>
        record.payload['ocvPassed'] == true
            ? 'pass'
            : record.payload['ocvPassed'] == false
            ? 'fail'
            : null,
      _ => 'success',
    };
    final title = switch (record.kind) {
      SyncKind.decoder =>
        format is String && format.isNotEmpty ? format : 'Barcode decoded',
      SyncKind.ocr => 'OCR completed',
      SyncKind.inspection => 'Inspection ${status ?? 'recorded'}',
      SyncKind.image => 'Image received',
    };
    var detail = 'Record saved';
    for (final key in const ['text', 'raw', 'ocrText']) {
      final value = record.payload[key];
      if (value is String && value.trim().isNotEmpty) {
        final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
        detail = normalized.length > 240
            ? '${normalized.substring(0, 237)}…'
            : normalized;
        break;
      }
    }
    var sourceName = 'Linked device';
    if (record.originDeviceId == store.deviceId) {
      sourceName = store.deviceName;
    } else {
      for (final linked in store.devices) {
        if (linked.id == record.originDeviceId && !linked.revoked) {
          sourceName = linked.name;
          break;
        }
      }
    }
    return CompanionActivityEvent(
      id: record.id,
      type: record.kind.name,
      title: title,
      detail: detail,
      sourceDeviceId: record.originDeviceId,
      sourceDeviceName: sourceName,
      createdAt: record.createdAt,
      status: status,
    );
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
      'lastSeq': journal.lastSeq,
      'serverTime': _clock().toUtc().toIso8601String(),
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
