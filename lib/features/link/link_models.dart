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
