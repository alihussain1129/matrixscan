import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/link/link_client.dart';
import 'package:exalted/features/link/link_crypto.dart';
import 'package:exalted/features/link/link_journal.dart';
import 'package:exalted/features/link/link_models.dart';
import 'package:exalted/features/link/link_pairing.dart';
import 'package:exalted/features/link/link_server.dart';
import 'package:exalted/features/link/link_store.dart';

class _Node {
  _Node(this.store, this.journal);
  final LinkStore store;
  final FileSyncStore journal;
}

final _vaults = <String, InMemoryLinkSecretStore>{};

Future<_Node> _makeNode(
  Directory root,
  String name, {
  bool identity = false,
}) async {
  final dir = Directory('${root.path}${Platform.pathSeparator}$name');
  final store = LinkStore(
    dir,
    secretStore: _vaults.putIfAbsent(dir.path, InMemoryLinkSecretStore.new),
  )..deviceName = name;
  await store.load();
  if (identity) await store.ensureIdentity();
  final journal = FileSyncStore(dir);
  await journal.open();
  return _Node(store, journal);
}

SyncRecord _rec(
  String origin,
  String id, {
  Map<String, Object?>? payload,
  List<String> blobs = const [],
  SyncKind kind = SyncKind.ocr,
  DateTime? createdAt,
}) => SyncRecord(
  id: '$origin:$id',
  kind: kind,
  originDeviceId: origin,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 4, 12),
  payload: payload ?? {'text': 'hello $id'},
  blobs: blobs,
);

Matcher _code(String code) =>
    throwsA(isA<LinkException>().having((e) => e.code, 'code', code));

void main() {
  group('pairing tokens', () {
    test('a token works once', () {
      final m = PairingManager();
      final o = m.create();
      expect(m.consume(o.token), isTrue);
      expect(m.consume(o.token), isFalse);
    });
    test('an expired token is rejected', () {
      var now = DateTime(2026, 11, 4);
      final m = PairingManager(
        ttl: const Duration(seconds: 30),
        clock: () => now,
      );
      final o = m.create();
      now = now.add(const Duration(seconds: 31));
      expect(m.consume(o.token), isFalse);
    });
    test('many wrong tokens lock pairing, even for a real token', () {
      var now = DateTime(2026, 11, 4);
      final m = PairingManager(clock: () => now);
      final o = m.create();
      for (var i = 0; i < 8; i++) {
        expect(m.consume('wrong-$i'), isFalse);
      }
      expect(m.consume(o.token), isFalse);
      now = now.add(const Duration(minutes: 1, seconds: 1));
      expect(m.consume(m.create().token), isTrue);
    });
    test('QR payload round trip and validation', () {
      final p = PairingPayload(
        hosts: ['192.168.1.20'],
        port: 47821,
        fingerprint: 'a' * 64,
        token: randomToken(),
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        desktopName: 'Desk',
      );
      final back = PairingPayload.parse(p.encode());
      expect(back.hosts, ['192.168.1.20']);
      expect(back.token, p.token);
      expect(() => PairingPayload.parse('nonsense'), _code('bad_qr'));
      expect(
        () => PairingPayload.parse('{"app":"other","v":1}'),
        _code('bad_qr'),
      );
    });
    test('private address check', () {
      expect(isPrivateAddress(InternetAddress('192.168.0.5')), isTrue);
      expect(isPrivateAddress(InternetAddress('10.1.2.3')), isTrue);
      expect(isPrivateAddress(InternetAddress('172.20.0.1')), isTrue);
      expect(isPrivateAddress(InternetAddress('8.8.8.8')), isFalse);
      expect(isPrivateAddress(InternetAddress('172.32.0.1')), isFalse);
    });
  });

  group('records and journal', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('exalted_journal_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('a tampered record is rejected', () {
      final j = _rec('a', '1').toJson();
      expect(SyncRecord.fromJson(j), isNotNull);
      j['payload'] = {'text': 'changed'};
      expect(SyncRecord.fromJson(j), isNull);
    });
    test('same record twice is stored once', () async {
      final n = await _makeNode(root, 'n');
      expect(await n.journal.add(_rec('a', '1')), IngestResult.added);
      expect(await n.journal.add(_rec('a', '1')), IngestResult.duplicate);
      expect(n.journal.length, 1);
    });
    test('conflicting versions are both kept', () async {
      final n = await _makeNode(root, 'n');
      await n.journal.add(_rec('a', '1'));
      expect(
        await n.journal.add(_rec('a', '1', payload: {'text': 'other'})),
        IngestResult.conflict,
      );
      expect(n.journal.length, 1);
      expect((await n.journal.conflicts()).length, 1);
    });
    test('conflict decisions are recorded and survive a restart', () async {
      final n = await _makeNode(root, 'n');
      final current = _rec('peer', 'shared', payload: {'text': 'current'});
      final incoming = _rec('peer', 'shared', payload: {'text': 'incoming'});
      await n.journal.add(current);
      expect(await n.journal.add(incoming), IngestResult.conflict);

      var cases = await n.journal.conflictCases();
      expect(cases, hasLength(1));
      expect(cases.single.current.payload['text'], 'current');
      expect(cases.single.incoming.payload['text'], 'incoming');
      expect(cases.single.resolved, isFalse);

      await n.journal.resolveConflict(incoming, 'keep_current');
      await n.journal.resolveConflict(incoming, 'save_incoming_copy');
      cases = await n.journal.conflictCases();
      expect(cases.single.resolution, 'keep_current');

      final again = await _makeNode(root, 'n');
      final persisted = await again.journal.conflictCases();
      expect(persisted.single.resolution, 'keep_current');
      expect(persisted.single.current.payload['text'], 'current');
      expect(persisted.single.incoming.payload['text'], 'incoming');
    });
    test('sync session history is durable and newest first', () async {
      final n = await _makeNode(root, 'n');
      final started = DateTime.utc(2026, 11, 11, 10);
      final completed = started.add(const Duration(seconds: 2));
      await n.journal.recordSyncSession(
        SyncSessionEntry(
          peerId: 'peer-id',
          peerName: 'Line 4',
          startedAt: started,
          finishedAt: completed,
          succeeded: false,
          pushed: 1,
          error: 'Connection timed out',
        ),
      );
      await n.journal.recordSyncSession(
        SyncSessionEntry(
          peerId: 'peer-id',
          peerName: 'Line 4',
          startedAt: completed,
          finishedAt: completed.add(const Duration(seconds: 1)),
          succeeded: true,
          pulled: 2,
        ),
      );

      final again = await _makeNode(root, 'n');
      expect(again.journal.syncSessions, hasLength(2));
      expect(again.journal.syncSessions.first.succeeded, isTrue);
      expect(again.journal.syncSessions.last.error, 'Connection timed out');
    });
    test('journal survives a restart', () async {
      final n = await _makeNode(root, 'n');
      await n.journal.add(_rec('a', '1'));
      await n.journal.add(_rec('a', '2'));
      final again = await _makeNode(root, 'n');
      expect(again.journal.length, 2);
      expect(again.journal.lastSeq, 2);
    });
    test('image hash is verified', () async {
      final n = await _makeNode(root, 'n');
      final bytes = Uint8List.fromList(List.generate(500, (i) => i % 200));
      final sha = await n.journal.storeBlob(bytes);
      expect(await n.journal.getBlob(sha), bytes);
      await expectLater(
        n.journal.putBlob('0' * 64, [1, 2, 3]),
        throwsFormatException,
      );
    });
    test('paging uses a cursor', () async {
      final n = await _makeNode(root, 'n');
      for (var i = 0; i < 5; i++) {
        await n.journal.add(_rec('a', '$i'));
      }
      final p1 = n.journal.page(after: 0, limit: 2);
      expect(p1.entries.length, 2);
      expect(p1.more, isTrue);
      final p2 = n.journal.page(after: p1.next, limit: 10);
      expect(p2.entries.length, 3);
      expect(p2.more, isFalse);
    });
  });

  group('end to end over TLS on loopback', () {
    late Directory root;
    late _Node desk;
    late _Node phone1;
    late _Node phone2;
    late PairingManager pairing;
    late LinkServer server;
    late LinkClient c1;
    late LinkClient c2;
    var approveNext = true;
    var remoteExecutions = 0;
    PeerDesktop? peer1;
    PeerDesktop? peer2;

    PairingPayload offer({DateTime? expires}) {
      final o = pairing.create();
      return PairingPayload(
        hosts: ['127.0.0.1'],
        port: server.port,
        fingerprint: desk.store.identity!.fingerprint,
        token: o.token,
        expiresAt: expires ?? o.expiresAt,
        desktopName: 'desktop',
      );
    }

    setUpAll(() async {
      root = Directory.systemTemp.createTempSync('exalted_link_');
      desk = await _makeNode(root, 'desktop', identity: true);
      phone1 = await _makeNode(root, 'phone1');
      phone2 = await _makeNode(root, 'phone2');
      pairing = PairingManager();
      server = LinkServer(
        store: desk.store,
        journal: desk.journal,
        pairing: pairing,
        approve: (_) async => approveNext,
        readHardwareStatus: () => const {
          'available': true,
          'keyence': {'status': 'connected', 'model': 'SR-751'},
        },
        executeRemoteCommand: (action) async {
          remoteExecutions++;
          return {'success': true, 'message': 'confirmed $action'};
        },
      );
      await server.start(preferredPort: 0);
      c1 = LinkClient(store: phone1.store, journal: phone1.journal);
      c2 = LinkClient(store: phone2.store, journal: phone2.journal);
    });

    tearDownAll(() async {
      await server.stop();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('pairing needs approval', () async {
      approveNext = false;
      await expectLater(
        c1.pair(offer(), platform: 'android', appVersion: '1'),
        _code('rejected'),
      );
      expect(desk.store.devices, isEmpty);
      approveNext = true;
    });

    test('an expired code is refused by the phone', () async {
      final p = offer(
        expires: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      await expectLater(
        c1.pair(p, platform: 'android', appVersion: '1'),
        _code('expired'),
      );
    });

    test('pairing works once and a reused code fails', () async {
      final p = offer();
      peer1 = await c1.pair(p, platform: 'android', appVersion: '1');
      expect(desk.store.deviceById(phone1.store.deviceId), isNotNull);
      await expectLater(
        c2.pair(p, platform: 'android', appVersion: '1'),
        _code('pairing_invalid_or_expired'),
      );
    });

    test('a phone with the wrong certificate fingerprint is refused', () async {
      final p = offer();
      final wrong = PairingPayload(
        hosts: p.hosts,
        port: p.port,
        fingerprint: 'b' * 64,
        token: p.token,
        expiresAt: p.expiresAt,
        desktopName: 'x',
      );
      await expectLater(
        c2.pair(wrong, platform: 'android', appVersion: '1'),
        _code('untrusted_desktop'),
      );
    });

    test(
      'upload with an original image, then repeat without duplicates',
      () async {
        final bytes = Uint8List.fromList(
          List.generate(4000, (i) => (i * 7) % 251),
        );
        final sha = await phone1.journal.storeBlob(bytes);
        await phone1.journal.add(
          _rec(
            phone1.store.deviceId,
            'scan1',
            blobs: [sha],
            kind: SyncKind.inspection,
          ),
        );
        final progress = <SyncProgress>[];
        final s1 = await c1.syncNow(peer1!, onProgress: progress.add);
        expect(s1.pushed, 1);
        expect(s1.blobsUp, 1);
        expect(desk.journal.length, 1);
        expect(await desk.journal.getBlob(sha), bytes);
        expect(
          progress,
          containsAll([
            predicate<SyncProgress>(
              (p) =>
                  p.phase == 'Uploading images' && p.done == 1 && p.total == 0,
            ),
            predicate<SyncProgress>(
              (p) =>
                  p.phase == 'Uploading records' && p.done == 1 && p.total == 0,
            ),
          ]),
        );
        final s2 = await c1.syncNow(peer1!);
        expect(s2.pushed, 0);
        expect(s2.blobsUp, 0);
        expect(desk.journal.length, 1);
      },
    );

    test('download from the desktop', () async {
      await desk.journal.add(_rec(desk.store.deviceId, 'deskscan'));
      final s = await c1.syncNow(peer1!);
      expect(s.pulled, 1);
      expect(phone1.journal.length, 2);
      final again = await c1.syncNow(peer1!);
      expect(again.pulled, 0);
      expect(phone1.journal.length, 2);
    });

    test(
      'companion snapshot is authenticated and reflects saved records',
      () async {
        await desk.journal.add(
          _rec(
            desk.store.deviceId,
            'live-companion-scan',
            kind: SyncKind.decoder,
            createdAt: DateTime.now(),
            payload: {'text': 'LIVE-123', 'format': 'Data Matrix'},
          ),
        );
        final snapshot = await c1.fetchCompanionSnapshot(peer1!);
        expect(snapshot.deviceId, desk.store.deviceId);
        expect(snapshot.name, 'desktop');
        expect(snapshot.hardware['available'], isTrue);
        expect((snapshot.hardware['keyence'] as Map)['model'], 'SR-751');
        expect(snapshot.todayScans, 1);
        expect(snapshot.activeLinkedDevices, greaterThanOrEqualTo(1));
        expect(
          snapshot.events.any(
            (event) =>
                event.id.endsWith('live-companion-scan') &&
                event.title == 'Data Matrix' &&
                event.detail == 'LIVE-123',
          ),
          isTrue,
        );
      },
    );

    test(
      'authenticated event stream delivers new desktop records live',
      () async {
        final received = Completer<CompanionStreamMessage>();
        final subscription = c1
            .watchCompanionEvents(peer1!, after: peer1!.eventCursor)
            .listen((message) {
              if (message.event?.id.endsWith('streamed-live-scan') == true &&
                  !received.isCompleted) {
                received.complete(message);
              }
            });
        try {
          await desk.journal.add(
            _rec(
              desk.store.deviceId,
              'streamed-live-scan',
              kind: SyncKind.decoder,
              payload: {'text': 'STREAM-42', 'format': 'Data Matrix'},
              createdAt: DateTime.now(),
            ),
          );
          final message = await received.future.timeout(
            const Duration(seconds: 5),
          );
          expect(message.kind, 'event');
          expect(message.event!.detail, 'STREAM-42');
          expect(message.cursor, greaterThan(peer1!.eventCursor));
        } finally {
          await subscription.cancel();
        }
      },
    );

    test('remote commands require host opt-in and replay IDs execute once', () async {
      const commandId = 'remote-command-test-0001';
      final before = remoteExecutions;
      await expectLater(
        c1.remoteScannerCommand(peer1!, 'start', commandId: commandId),
        _code('remote_control_disabled'),
      );
      await desk.store.setRemoteControlAuthorization(
        phone1.store.deviceId,
        true,
      );
      final first = await c1.remoteScannerCommand(
        peer1!,
        'start',
        commandId: commandId,
      );
      expect(first.state, 'completed');
      expect(first.message, 'confirmed start');
      final replay = await c1.remoteScannerCommand(
        peer1!,
        'start',
        commandId: commandId,
      );
      expect(replay.state, 'completed');
      expect(remoteExecutions, before + 1);
      final oldPort = server.port;
      await server.stop();
      server = LinkServer(
        store: desk.store,
        journal: desk.journal,
        pairing: pairing,
        approve: (_) async => approveNext,
        executeRemoteCommand: (action) async {
          remoteExecutions++;
          return {'success': true, 'message': 'confirmed $action'};
        },
      );
      await server.start(preferredPort: oldPort);
      final afterRestart = await c1.remoteScannerCommand(
        peer1!,
        'start',
        commandId: commandId,
      );
      expect(afterRestart.state, 'completed');
      expect(remoteExecutions, before + 1);
      await expectLater(
        c1.remoteScannerCommand(peer1!, 'stop', commandId: commandId),
        _code('command_id_conflict'),
      );
      await desk.store.revoke(phone1.store.deviceId);
      await expectLater(
        c1.remoteScannerCommand(peer1!, 'pause'),
        _code('unauthorized'),
      );
      desk.store.deviceById(phone1.store.deviceId)!.revoked = false;
      await desk.store.save();
      final log = File(
        '${desk.store.dir.path}${Platform.pathSeparator}remote_commands.jsonl',
      );
      expect(await log.readAsString(), contains('confirmed start'));
    });

    test(
      'a second phone gets the first phone\'s data and not its own',
      () async {
        peer2 = await c2.pair(offer(), platform: 'android', appVersion: '1');
        await phone2.journal.add(_rec(phone2.store.deviceId, 'p2scan'));
        final s = await c2.syncNow(peer2!);
        expect(s.pushed, 1);
        expect(s.pulled, 4);
        final ids = phone2.journal.allRecords().map((r) => r.id).toSet();
        expect(ids, contains('${phone1.store.deviceId}:scan1'));
        expect(ids, contains('${desk.store.deviceId}:deskscan'));
        expect(ids, contains('${desk.store.deviceId}:live-companion-scan'));
        expect(ids, contains('${desk.store.deviceId}:streamed-live-scan'));
        await c1.syncNow(peer1!);
        final ids1 = phone1.journal.allRecords().map((r) => r.id).toSet();
        expect(ids1, contains('${phone2.store.deviceId}:p2scan'));
      },
    );

    test('a signed request cannot be replayed', () async {
      final http = HttpClient(context: SecurityContext(withTrustedRoots: false))
        ..badCertificateCallback = (cert, h, p) =>
            sha256Hex(cert.der) == desk.store.identity!.fingerprint;
      Future<int> call(String nonce, int ts) async {
        final uri = Uri.parse('https://127.0.0.1:${server.port}/v1/status');
        final req = await http.openUrl('GET', uri);
        final sig = signRequest(
          base64.decode(peer2!.secretB64),
          'GET',
          '/v1/status',
          ts,
          nonce,
          sha256Hex(const <int>[]),
        );
        req.headers
          ..set('x-exalted-device', phone2.store.deviceId)
          ..set('x-exalted-ts', '$ts')
          ..set('x-exalted-nonce', nonce)
          ..set('x-exalted-sig', sig);
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      expect(await call('replaynonce-1', now), 200);
      expect(await call('replaynonce-1', now), 401);
      expect(await call('oldnonce-123', now - 600000), 401);
      http.close(force: true);
    });

    test('a revoked device is refused and keeps its local data', () async {
      final before = phone1.journal.length;
      await desk.store.revoke(phone1.store.deviceId);
      await expectLater(c1.syncNow(peer1!), _code('unauthorized'));
      expect(phone1.journal.length, before);
    });

    test('works offline: local journal still accepts records', () async {
      await server.stop();
      await phone2.journal.add(_rec(phone2.store.deviceId, 'offline1'));
      expect(phone2.journal.length, greaterThan(0));
      await expectLater(c2.syncNow(peer2!), throwsA(isA<LinkException>()));
      expect(
        phone2.journal.allRecords().any((r) => r.id.endsWith(':offline1')),
        isTrue,
      );
    });
  });
}
