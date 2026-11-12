import 'dart:io';

import 'package:exalted/features/link/link_journal.dart';
import 'package:exalted/features/link/link_models.dart';
import 'package:exalted/features/link/sync_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts only this device\'s records after the cursor', () async {
    final tmp = await Directory.systemTemp.createTemp('pending_test');
    addTearDown(() => tmp.delete(recursive: true));
    final store = FileSyncStore(Directory('${tmp.path}/j'));
    await store.open();
    final me = SyncBridge(store: store, deviceId: 'phone');
    final other = SyncBridge(store: store, deviceId: 'other');
    final t = DateTime.utc(2026, 11, 11);
    for (final id in ['1', '2', '3']) {
      await me.journal(
        kind: SyncKind.decoder,
        localId: id,
        createdAt: t,
        payload: {'text': id},
      );
    }
    await other.journal(
      kind: SyncKind.decoder,
      localId: 'x',
      createdAt: t,
      payload: {'text': 'x'},
    );
    expect(pendingCount(store, 'phone', 0), 3);
    expect(pendingCount(store, 'phone', 2), 1);
    expect(pendingCount(store, 'phone', 3), 0);
    expect(pendingCount(store, 'phone', 99), 0);
  });
}
