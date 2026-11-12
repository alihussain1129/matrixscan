import 'dart:convert';

import 'link_crypto.dart';

class LinkException implements Exception {
  LinkException(this.code, this.message, {this.retryable = false});
  final String code;
  final String message;
  final bool retryable;
  @override
  String toString() => 'LinkException($code): $message';
}

DateTime? _dt(Object? v) => v is String ? DateTime.tryParse(v) : null;

enum SyncKind { decoder, ocr, inspection, image }

/// One immutable piece of evidence. The hash covers every field, so a changed
/// or damaged record is detected and rejected.
class SyncRecord {
  SyncRecord._(
    this.id,
    this.kind,
    this.originDeviceId,
    this.createdAt,
    this.payload,
    this.blobs,
    this.contentHash,
  );

  factory SyncRecord({
    required String id,
    required SyncKind kind,
    required String originDeviceId,
    required DateTime createdAt,
    required Map<String, Object?> payload,
    List<String> blobs = const <String>[],
  }) {
    final core = _core(id, kind, originDeviceId, createdAt, payload, blobs);
    return SyncRecord._(
      id,
      kind,
      originDeviceId,
      createdAt,
      payload,
      blobs,
      sha256Hex(utf8.encode(canonicalJson(core))),
    );
  }

  final String id;
  final SyncKind kind;
  final String originDeviceId;
  final DateTime createdAt;
  final Map<String, Object?> payload;

  /// SHA-256 of original image files stored beside the journal.
  final List<String> blobs;
  final String contentHash;

  static Map<String, Object?> _core(
    String id,
    SyncKind kind,
    String origin,
    DateTime createdAt,
    Map<String, Object?> payload,
    List<String> blobs,
  ) => {
    'id': id,
    'kind': kind.name,
    'origin': origin,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'payload': payload,
    'blobs': blobs,
  };

  Map<String, Object?> toJson() => {
    ..._core(id, kind, originDeviceId, createdAt, payload, blobs),
    'hash': contentHash,
  };

  static SyncRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final origin = j['origin'];
    final created = _dt(j['createdAt']);
    final payload = j['payload'];
    final blobs = j['blobs'];
    final hash = j['hash'];
    if (id is! String || id.isEmpty || id.length > 200) return null;
    if (origin is! String || origin.isEmpty || origin.length > 100) {
      return null;
    }
    if (created == null || payload is! Map || blobs is! List) return null;
    if (hash is! String) return null;
    SyncKind? kind;
    for (final k in SyncKind.values) {
      if (k.name == j['kind']) kind = k;
    }
    if (kind == null) return null;
    final blobList = <String>[];
    for (final b in blobs) {
      if (b is! String || !isSha256Hex(b)) return null;
      blobList.add(b);
    }
    final rec = SyncRecord(
      id: id,
      kind: kind,
      originDeviceId: origin,
      createdAt: created,
      payload: Map<String, Object?>.from(payload),
      blobs: blobList,
    );
    return rec.contentHash == hash ? rec : null;
  }
}

/// A phone that this desktop trusts (stored on the desktop).
class LinkedDevice {
  LinkedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.pairedAt,
    required this.secretB64,
    this.lastSeen,
    this.lastSync,
    this.remoteControlAuthorized = false,
    this.revoked = false,
  });

  final String id;
  String name;
  final String platform;
  String appVersion;
  final DateTime pairedAt;
  final String secretB64;
  DateTime? lastSeen;
  DateTime? lastSync;
  bool revoked;
  bool remoteControlAuthorized;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'appVersion': appVersion,
    'pairedAt': pairedAt.toIso8601String(),
    'secret': secretB64,
    'lastSeen': lastSeen?.toIso8601String(),
    'lastSync': lastSync?.toIso8601String(),
    'revoked': revoked,
    'remoteControlAuthorized': remoteControlAuthorized,
  };

  static LinkedDevice? fromJson(Object? j) {
    if (j is! Map) return null;
    final paired = _dt(j['pairedAt']);
    if (j['id'] is! String || j['secret'] is! String || paired == null) {
      return null;
    }
    return LinkedDevice(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Device',
      platform: (j['platform'] as String?) ?? 'unknown',
      appVersion: (j['appVersion'] as String?) ?? '',
      pairedAt: paired,
      secretB64: j['secret'] as String,
      lastSeen: _dt(j['lastSeen']),
      lastSync: _dt(j['lastSync']),
      revoked: j['revoked'] == true,
      remoteControlAuthorized: j['remoteControlAuthorized'] == true,
    );
  }
}

/// A desktop that this phone is linked to (stored on the phone).
class PeerDesktop {
  PeerDesktop({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.secretB64,
    required this.pairedAt,
    this.pushCursor = 0,
    this.pullCursor = 0,
    this.eventCursor = 0,
    this.lastSync,
  });

  final String id;
  String name;

  /// IPv4 address. The user can change it by hand if the desktop moves.
  String host;
  int port;
  final String fingerprint;
  final String secretB64;
  final DateTime pairedAt;
  int pushCursor;
  int pullCursor;
  int eventCursor;
  DateTime? lastSync;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'fp': fingerprint,
    'secret': secretB64,
    'pairedAt': pairedAt.toIso8601String(),
    'pushCursor': pushCursor,
    'pullCursor': pullCursor,
    'eventCursor': eventCursor,
    'lastSync': lastSync?.toIso8601String(),
  };

  static PeerDesktop? fromJson(Object? j) {
    if (j is! Map) return null;
    final paired = _dt(j['pairedAt']);
    if (j['id'] is! String ||
        j['host'] is! String ||
        j['port'] is! int ||
        j['fp'] is! String ||
        j['secret'] is! String ||
        paired == null) {
      return null;
    }
    return PeerDesktop(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Desktop',
      host: j['host'] as String,
      port: j['port'] as int,
      fingerprint: j['fp'] as String,
      secretB64: j['secret'] as String,
      pairedAt: paired,
      pushCursor: (j['pushCursor'] as int?) ?? 0,
      pullCursor: (j['pullCursor'] as int?) ?? 0,
      eventCursor: (j['eventCursor'] as int?) ?? 0,
      lastSync: _dt(j['lastSync']),
    );
  }
}

class SyncProgress {
  const SyncProgress(this.phase, this.done, this.total);
  final String phase;
  final int done;
  final int total;
}

/// Structured desktop state returned only to an authenticated paired client.
/// Timestamps remain server supplied so the phone can label stale snapshots.
class CompanionActivityEvent {
  const CompanionActivityEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    required this.sourceDeviceId,
    required this.createdAt,
    this.sourceDeviceName,
    this.status,
  });

  final String id;
  final String type;
  final String title;
  final String detail;
  final String sourceDeviceId;
  final DateTime createdAt;
  final String? sourceDeviceName;
  final String? status;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'detail': detail,
    'sourceDeviceId': sourceDeviceId,
    if (sourceDeviceName != null) 'sourceDeviceName': sourceDeviceName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (status != null) 'status': status,
  };

  static CompanionActivityEvent? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final type = value['type'];
    final title = value['title'];
    final detail = value['detail'];
    final source = value['sourceDeviceId'];
    final createdAt = _dt(value['createdAt']);
    if (id is! String ||
        type is! String ||
        title is! String ||
        detail is! String ||
        source is! String ||
        createdAt == null) {
      return null;
    }
    return CompanionActivityEvent(
      id: id,
      type: type,
      title: title,
      detail: detail,
      sourceDeviceId: source,
      createdAt: createdAt,
      sourceDeviceName: value['sourceDeviceName'] is String
          ? value['sourceDeviceName'] as String
          : null,
      status: value['status'] is String ? value['status'] as String : null,
    );
  }
}

/// Authenticated WebSocket frame. Cursor messages let the client persist
/// ordering and recover missed events after a reconnect.
class CompanionStreamMessage {
  const CompanionStreamMessage({
    required this.kind,
    required this.cursor,
    this.event,
    this.serverTime,
  });

  final String kind;
  final int cursor;
  final CompanionActivityEvent? event;
  final DateTime? serverTime;

  static CompanionStreamMessage? fromJson(Object? value) {
    if (value is! Map || value['kind'] is! String || value['cursor'] is! int) {
      return null;
    }
    final kind = value['kind'] as String;
    final serverTime = _dt(value['serverTime']);
    if (kind == 'event') {
      final event = CompanionActivityEvent.fromJson(value['event']);
      if (event == null || value['eventId'] != event.id) return null;
      return CompanionStreamMessage(
        kind: kind,
        cursor: value['cursor'] as int,
        event: event,
        serverTime: serverTime,
      );
    }
    if ((kind == 'ready' || kind == 'heartbeat') && serverTime != null) {
      return CompanionStreamMessage(
        kind: kind,
        cursor: value['cursor'] as int,
        serverTime: serverTime,
      );
    }
    return null;
  }
}

class RemoteCommandResult {
  const RemoteCommandResult({
    required this.commandId,
    required this.action,
    required this.state,
    required this.message,
  });

  final String commandId;
  final String action;
  final String state;
  final String message;

  bool get completed => state == 'completed';
  bool get terminal =>
      const {'completed', 'rejected', 'failed', 'timed_out'}.contains(state);
}

/// A live, authenticated snapshot. The phone refreshes this periodically and
/// keeps the last successful copy marked stale when the desktop is unreachable.
class CompanionSnapshot {
  const CompanionSnapshot({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.serverTime,
    required this.todayScans,
    required this.todayOcr,
    required this.todayInspections,
    required this.passedInspections,
    required this.failedInspections,
    required this.reviewInspections,
    required this.activeLinkedDevices,
    required this.hardware,
    required this.events,
  });

  final String deviceId;
  final String name;
  final String platform;
  final DateTime serverTime;
  final int todayScans;
  final int todayOcr;
  final int todayInspections;
  final int passedInspections;
  final int failedInspections;
  final int reviewInspections;
  final int activeLinkedDevices;
  final Map<String, Object?> hardware;
  final List<CompanionActivityEvent> events;

  CompanionSnapshot copyWith({
    List<CompanionActivityEvent>? events,
    DateTime? serverTime,
  }) => CompanionSnapshot(
    deviceId: deviceId,
    name: name,
    platform: platform,
    serverTime: serverTime ?? this.serverTime,
    todayScans: todayScans,
    todayOcr: todayOcr,
    todayInspections: todayInspections,
    passedInspections: passedInspections,
    failedInspections: failedInspections,
    reviewInspections: reviewInspections,
    activeLinkedDevices: activeLinkedDevices,
    hardware: hardware,
    events: List.unmodifiable(events ?? this.events),
  );

  static CompanionSnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    final deviceId = value['deviceId'];
    final name = value['name'];
    final platform = value['platform'];
    final serverTime = _dt(value['serverTime']);
    final rawEvents = value['events'];
    if (deviceId is! String ||
        name is! String ||
        platform is! String ||
        serverTime == null ||
        rawEvents is! List) {
      return null;
    }
    int number(String key) => (value[key] as num?)?.toInt() ?? 0;
    final hardware = value['hardware'] is Map
        ? Map<String, Object?>.from(value['hardware'] as Map)
        : const <String, Object?>{};
    final events = <CompanionActivityEvent>[];
    for (final item in rawEvents.take(100)) {
      final event = CompanionActivityEvent.fromJson(item);
      if (event != null) events.add(event);
    }
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return CompanionSnapshot(
      deviceId: deviceId,
      name: name,
      platform: platform,
      serverTime: serverTime,
      todayScans: number('todayScans'),
      todayOcr: number('todayOcr'),
      todayInspections: number('todayInspections'),
      passedInspections: number('passedInspections'),
      failedInspections: number('failedInspections'),
      reviewInspections: number('reviewInspections'),
      activeLinkedDevices: number('activeLinkedDevices'),
      hardware: hardware,
      events: List.unmodifiable(events),
    );
  }
}

class SyncSessionEntry {
  const SyncSessionEntry({
    required this.peerId,
    required this.peerName,
    required this.startedAt,
    required this.finishedAt,
    required this.succeeded,
    this.pushed = 0,
    this.pulled = 0,
    this.duplicates = 0,
    this.conflicts = 0,
    this.blobsUp = 0,
    this.blobsDown = 0,
    this.error,
  });

  final String peerId;
  final String peerName;
  final DateTime startedAt;
  final DateTime finishedAt;
  final bool succeeded;
  final int pushed;
  final int pulled;
  final int duplicates;
  final int conflicts;
  final int blobsUp;
  final int blobsDown;
  final String? error;

  Map<String, Object?> toJson() => {
    'peerId': peerId,
    'peerName': peerName,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'succeeded': succeeded,
    'pushed': pushed,
    'pulled': pulled,
    'duplicates': duplicates,
    'conflicts': conflicts,
    'blobsUp': blobsUp,
    'blobsDown': blobsDown,
    if (error != null) 'error': error,
  };

  static SyncSessionEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final peerId = value['peerId'];
    final peerName = value['peerName'];
    final started = _dt(value['startedAt']);
    final finished = _dt(value['finishedAt']);
    final succeeded = value['succeeded'];
    if (peerId is! String ||
        peerName is! String ||
        started == null ||
        finished == null ||
        succeeded is! bool) {
      return null;
    }
    int number(String key) => (value[key] as num?)?.toInt() ?? 0;
    return SyncSessionEntry(
      peerId: peerId,
      peerName: peerName,
      startedAt: started,
      finishedAt: finished,
      succeeded: succeeded,
      pushed: number('pushed'),
      pulled: number('pulled'),
      duplicates: number('duplicates'),
      conflicts: number('conflicts'),
      blobsUp: number('blobsUp'),
      blobsDown: number('blobsDown'),
      error: value['error'] as String?,
    );
  }
}

class SyncSummary {
  int pushed = 0;
  int pulled = 0;
  int duplicates = 0;
  int conflicts = 0;
  int blobsUp = 0;
  int blobsDown = 0;
  @override
  String toString() =>
      'pushed=$pushed pulled=$pulled duplicates=$duplicates '
      'conflicts=$conflicts blobsUp=$blobsUp blobsDown=$blobsDown';
}
