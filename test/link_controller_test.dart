import 'dart:io';

import 'package:exalted/features/link/link_client.dart';
import 'package:exalted/features/link/link_journal.dart';
import 'package:exalted/features/link/link_models.dart';
import 'package:exalted/features/link/link_pairing.dart';
import 'package:exalted/features/link/link_providers.dart';
import 'package:exalted/features/link/link_store.dart';
import 'package:exalted/core/config/platform_secret_store.dart';
import 'package:exalted/core/config/data_directory_provider.dart';
import 'package:exalted/features/history/history_entry.dart';
import 'package:exalted/features/history/history_repository.dart';
import 'package:exalted/features/history/history_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _until(bool Function() ok, String what, {int seconds = 15}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

class _Rig {
  _Rig(this.container, this.ctl, this.client, this.phoneStore);
  final ProviderContainer container;
  final LinkController ctl;
  final LinkClient client;
  final LinkStore phoneStore;
  LinkUiState get ui => container.read(linkControllerProvider);
}

Future<_Rig> _rig() async {
  final desktopDir = Directory.systemTemp.createTempSync('mx_desktop');
  final phoneDir = Directory.systemTemp.createTempSync('mx_phone');
  addTearDown(() {
    for (final d in [desktopDir, phoneDir]) {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
  final c = ProviderContainer(
    overrides: [
      linkDirectoryProvider.overrideWith((ref) async => desktopDir),
      dataDirectoryProvider.overrideWithValue(() async => desktopDir),
      secretStoreProvider.overrideWithValue(InMemoryLinkSecretStore()),
    ],
  );
  addTearDown(c.dispose);
  c.listen(linkControllerProvider, (_, _) {});
  await _until(() => c.read(linkControllerProvider).ready, 'controller ready');
  final phoneStore = LinkStore(
    phoneDir,
    secretStore: InMemoryLinkSecretStore(),
  );
  await phoneStore.load();
  final phoneJournal = FileSyncStore(phoneDir);
  await phoneJournal.open();
  return _Rig(
    c,
    c.read(linkControllerProvider.notifier),
    LinkClient(store: phoneStore, journal: phoneJournal),
    phoneStore,
  );
}

void main() {
  test('a bad pairing code is refused without any network use', () async {
    final r = await _rig();
    r.ctl.previewCode('hello');
    expect(r.ui.preview, isNull);
    expect(r.ui.error, 'This is not an Exalted pairing code.');
  });

  test(
    'approved pairing authenticates, tokens cannot be replayed, revoke blocks',
    () async {
      final r = await _rig();
      await r.ctl.startPairing(hosts: ['127.0.0.1']);
      final payload = PairingPayload.parse(r.ui.payload!.encode());
      expect(payload.port, r.ui.serverPort);

      final pairing = r.client.pair(
        payload,
        platform: 'android',
        appVersion: '1.0.0',
      );
      await _until(() => r.ui.pending != null, 'approval request');
      expect(r.ui.pending!.deviceId, r.phoneStore.deviceId);
      expect(r.ui.devices, isEmpty, reason: 'not linked before approval');

      r.ctl.respondToPairing(true);
      final peer = await pairing.timeout(const Duration(seconds: 20));
      expect(peer.fingerprint, payload.fingerprint);
      expect(r.phoneStore.peers, hasLength(1));
      await _until(() => r.ui.devices.length == 1, 'desktop lists the device');
      expect(r.ui.devices.single.revoked, isFalse);

      // The same one-time token must not work a second time.
      await expectLater(
        r.client.pair(payload, platform: 'android', appVersion: '1.0.0'),
        throwsA(isA<LinkException>()),
      );

      await r.ctl.revokeDevice(r.ui.devices.single.id);
      expect(r.ui.devices.single.revoked, isTrue);
      await expectLater(r.client.syncNow(peer), throwsA(isA<LinkException>()));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('a rejected request links nothing on either side', () async {
    final r = await _rig();
    await r.ctl.startPairing(hosts: ['127.0.0.1']);
    final payload = PairingPayload.parse(r.ui.payload!.encode());
    final pairing = r.client.pair(
      payload,
      platform: 'android',
      appVersion: '1.0.0',
    );
    await _until(() => r.ui.pending != null, 'approval request');
    r.ctl.respondToPairing(false);
    await expectLater(pairing, throwsA(isA<LinkException>()));
    expect(r.phoneStore.peers, isEmpty);
    expect(r.ui.devices, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'live desktop journal event imports into phone history automatically',
    () async {
      final r = await _rig();
      await r.ctl.startPairing(hosts: ['127.0.0.1']);
      final payload = PairingPayload.parse(r.ui.payload!.encode());

      final phoneDirectory = Directory.systemTemp.createTempSync(
        'mx_phone_app',
      );
      addTearDown(() {
        try {
          phoneDirectory.deleteSync(recursive: true);
        } catch (_) {}
      });
      final phoneSecrets = InMemoryLinkSecretStore();
      ProviderContainer makePhone() => ProviderContainer(
        overrides: [
          linkDirectoryProvider.overrideWith((ref) async => phoneDirectory),
          dataDirectoryProvider.overrideWithValue(() async => phoneDirectory),
          secretStoreProvider.overrideWithValue(phoneSecrets),
          desktopLinkRoleProvider.overrideWithValue(false),
        ],
      );
      var phone = makePhone();
      var phoneDisposed = false;
      addTearDown(() {
        if (!phoneDisposed) phone.dispose();
      });
      phone.listen(linkControllerProvider, (_, _) {});
      await _until(
        () => phone.read(linkControllerProvider).ready,
        'phone controller ready',
      );
      final phoneHistory = phone.read(historyControllerProvider.future);
      phone.listen(historyControllerProvider, (_, _) {});

      final phoneCtl = phone.read(linkControllerProvider.notifier);
      phoneCtl.previewCode(payload.encode());
      final linking = phoneCtl.confirmPair();
      await _until(() => r.ui.pending != null, 'desktop pairing approval');
      r.ctl.respondToPairing(true);
      await linking;

      await _until(
        () => phone.read(linkControllerProvider).companionStreaming,
        'phone event stream connected',
      );

      final saved = await r.container
          .read(historyRepositoryProvider)
          .add(
            kind: HistoryKind.barcode,
            source: HistorySource.live,
            text: 'LIVE-HISTORY-42',
            format: 'Data Matrix',
            allowRepeat: true,
          );
      expect(saved, isNotNull);
      await r.ctl.sweepLocalRecords();

      await phoneHistory;
      await _until(() {
        final value = phone.read(historyControllerProvider).asData?.value;
        return value?.any((entry) => entry.text == 'LIVE-HISTORY-42') ?? false;
      }, 'new desktop record imported into phone History');

      final peers = phone.read(linkControllerProvider).peers;
      expect(peers, hasLength(1));
      expect(peers.single.pullCursor, greaterThan(0));

      final offlineSaved = await r.container
          .read(historyRepositoryProvider)
          .add(
            kind: HistoryKind.barcode,
            source: HistorySource.live,
            text: 'RECONNECTED-HISTORY-43',
            format: 'QR Code',
            allowRepeat: true,
          );
      expect(offlineSaved, isNotNull);
      await r.ctl.sweepLocalRecords();

      // Simulate the Android process stopping while the desktop remains
      // available. Startup reconnect must pull the durable journal backlog.
      phone.dispose();
      phoneDisposed = true;
      phone = makePhone();
      phoneDisposed = false;
      phone.listen(linkControllerProvider, (_, _) {});
      await _until(
        () => phone.read(linkControllerProvider).ready,
        'phone controller restarted',
      );
      phone.listen(historyControllerProvider, (_, _) {});
      await phone.read(historyControllerProvider.future);
      await _until(() {
        final value = phone.read(historyControllerProvider).asData?.value;
        return value?.any((entry) => entry.text == 'RECONNECTED-HISTORY-43') ??
            false;
      }, 'offline desktop record imported after phone restart');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
