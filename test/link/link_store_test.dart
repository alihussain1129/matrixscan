import 'dart:convert';
import 'dart:io';

import 'package:exalted/features/link/link_models.dart';
import 'package:exalted/features/link/link_crypto.dart';
import 'package:exalted/features/link/link_store.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Directory> tempDir() async {
    final dir = await Directory.systemTemp.createTemp('exalted_link_store_');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  PeerDesktop peer() => PeerDesktop(
    id: 'desktop-1',
    name: 'Desktop',
    host: '192.168.1.20',
    port: 443,
    fingerprint: List<String>.filled(64, 'f').join(),
    secretB64: 'peer-secret',
    pairedAt: DateTime.utc(2026, 11, 11),
  );

  test('stores credentials outside public link metadata', () async {
    final dir = await tempDir();
    final vault = InMemoryLinkSecretStore();
    final store = LinkStore(dir, secretStore: vault)..deviceName = 'Desktop';
    await store.load();
    await store.addPeer(peer());

    final file = File('${dir.path}${Platform.pathSeparator}link_state.json');
    final text = await file.readAsString();
    final public = jsonDecode(text) as Map;
    expect(public['format'], 3);
    expect(text, isNot(contains('peer-secret')));
    expect(public.containsKey('identity'), isFalse);
    expect((public['peers'] as List).single.containsKey('secret'), isFalse);
    expect(
      await vault.read('exalted.link.credentials.v1.${public['secretDigest']}'),
      contains('peer-secret'),
    );
  });

  test(
    'remote control authorization persists and defaults to disabled',
    () async {
      final dir = await tempDir();
      final vault = InMemoryLinkSecretStore();
      final store = LinkStore(dir, secretStore: vault);
      await store.load();
      final device = LinkedDevice(
        id: 'phone-android',
        name: 'Phone',
        platform: 'android',
        appVersion: '1',
        pairedAt: DateTime.utc(2026, 11, 12),
        secretB64: 'device-secret',
      );
      expect(device.remoteControlAuthorized, isFalse);
      await store.addDevice(device);
      await store.setRemoteControlAuthorization(device.id, true);

      final reloaded = LinkStore(dir, secretStore: vault);
      await reloaded.load();
      expect(reloaded.deviceById(device.id)!.remoteControlAuthorized, isTrue);
      await reloaded.setRemoteControlAuthorization(device.id, false);
      await reloaded.revoke(device.id);
      await reloaded.setRemoteControlAuthorization(device.id, true);
      expect(reloaded.deviceById(device.id)!.remoteControlAuthorized, isFalse);
    },
  );

  test(
    'migrates legacy credentials without changing paired identity',
    () async {
      final dir = await tempDir();
      final file = File('${dir.path}${Platform.pathSeparator}link_state.json');
      await file.writeAsString(
        jsonEncode({
          'deviceId': 'phone-1',
          'deviceName': 'Phone',
          'identity': {'cert': 'certificate', 'key': 'private-key'},
          'peers': [peer().toJson()],
          'devices': const [],
        }),
      );
      final vault = InMemoryLinkSecretStore();
      final store = LinkStore(dir, secretStore: vault);
      await store.load();

      expect(store.deviceId, 'phone-1');
      expect(store.identity!.keyPem, 'private-key');
      expect(store.peers.single.secretB64, 'peer-secret');
      final public = await file.readAsString();
      expect(public, isNot(contains('private-key')));
      expect(public, isNot(contains('peer-secret')));
      expect(await dir.list().any((e) => e.path.contains('.legacy-')), isTrue);
    },
  );

  test(
    'rejects changed protected credentials and preserves state file',
    () async {
      final dir = await tempDir();
      final vault = InMemoryLinkSecretStore();
      final store = LinkStore(dir, secretStore: vault);
      await store.load();
      final stateFile = File(
        '${dir.path}${Platform.pathSeparator}link_state.json',
      );
      final state = jsonDecode(await stateFile.readAsString()) as Map;
      await vault.write(
        'exalted.link.credentials.v1.${state['secretDigest']}',
        '{"identity":"changed"}',
      );

      final reloaded = LinkStore(dir, secretStore: vault);
      await expectLater(reloaded.load(), throwsFormatException);
      expect(await dir.list().any((e) => e.path.contains('.corrupt-')), isTrue);
    },
  );

  test(
    'upgrades protected format 2 without changing identity or pairing',
    () async {
      final dir = await tempDir();
      final vault = InMemoryLinkSecretStore();
      const secret = <String, Object?>{
        'identity': {'cert': 'certificate', 'key': 'private-key'},
        'deviceSecrets': {},
        'peerSecrets': {'desktop-1': 'peer-secret'},
      };
      final secretText = jsonEncode(secret);
      final digest = sha256Hex(utf8.encode(canonicalJson(secret)));
      await vault.write('exalted.link.credentials.v1', secretText);
      final file = File('${dir.path}${Platform.pathSeparator}link_state.json');
      await file.writeAsString(
        jsonEncode({
          'format': 2,
          'deviceId': 'phone-2',
          'deviceName': 'Phone',
          'secretDigest': digest,
          'devices': const [],
          'peers': [
            {
              'id': 'desktop-1',
              'name': 'Desktop',
              'host': '192.168.1.20',
              'port': 443,
              'fp': 'f' * 64,
              'pairedAt': DateTime.utc(2026, 11, 11).toIso8601String(),
              'pushCursor': 0,
              'pullCursor': 0,
            },
          ],
        }),
      );

      final store = LinkStore(dir, secretStore: vault);
      await store.load();
      final upgraded = jsonDecode(await file.readAsString()) as Map;
      expect(upgraded['format'], 3);
      expect(store.deviceId, 'phone-2');
      expect(store.identity?.keyPem, 'private-key');
      expect(store.peers.single.secretB64, 'peer-secret');
      expect(await vault.read('exalted.link.credentials.v1'), isNull);
    },
  );

  test(
    'interrupted vault stage leaves the prior credential set loadable',
    () async {
      final dir = await tempDir();
      final vault = _FailAfterWriteSecretStore();
      final store = LinkStore(dir, secretStore: vault)..deviceName = 'Desktop';
      await store.load();
      final file = File('${dir.path}${Platform.pathSeparator}link_state.json');
      final originalState = await file.readAsString();
      final original = jsonDecode(originalState) as Map;
      final originalVaultKey =
          'exalted.link.credentials.v1.${original['secretDigest']}';

      vault.failAfterNextWrite = true;
      await expectLater(
        store.addPeer(peer()),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsString(), originalState);

      final recovered = LinkStore(dir, secretStore: vault);
      await recovered.load();
      expect(recovered.deviceId, store.deviceId);
      expect(recovered.peers, isEmpty);
      expect(await vault.read(originalVaultKey), isNotNull);
    },
  );
}

class _FailAfterWriteSecretStore implements SecretStore {
  final Map<String, String> values = {};
  bool failAfterNextWrite = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    if (failAfterNextWrite) {
      failAfterNextWrite = false;
      throw const FileSystemException('simulated interruption');
    }
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
