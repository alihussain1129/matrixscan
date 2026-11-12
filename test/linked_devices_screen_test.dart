import 'dart:io';

import 'package:exalted/features/link/link_providers.dart';
import 'package:exalted/features/link/link_journal.dart';
import 'package:exalted/features/link/link_models.dart';
import 'package:exalted/features/link/linked_devices_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop view shows Add device and an empty device list', (
    t,
  ) async {
    if (!(Platform.isLinux || Platform.isWindows)) return;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          linkControllerProvider.overrideWith(
            () => _StaticLinkController(const LinkUiState(ready: true)),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: LinkedDevicesScreen())),
      ),
    );
    expect(find.text('Add device'), findsOneWidget);
    expect(find.text('No linked devices yet'), findsOneWidget);
    // Unmount so the controller's timer is cancelled.
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('desktop view lets the user record a conflict decision', (
    t,
  ) async {
    if (!(Platform.isLinux || Platform.isWindows)) return;
    t.view.physicalSize = const Size(800, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final current = SyncRecord(
      id: 'peer:decoder:one',
      kind: SyncKind.decoder,
      originDeviceId: 'peer',
      createdAt: DateTime.utc(2026, 11, 11),
      payload: {'text': 'current value'},
    );
    final incoming = SyncRecord(
      id: current.id,
      kind: SyncKind.decoder,
      originDeviceId: 'peer',
      createdAt: current.createdAt,
      payload: {'text': 'incoming value'},
    );
    final conflict = SyncConflictCase(current: current, incoming: incoming);
    final controller = _StaticLinkController(
      LinkUiState(ready: true, conflicts: [conflict]),
    );

    await t.pumpWidget(
      ProviderScope(
        overrides: [linkControllerProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: Scaffold(body: LinkedDevicesScreen())),
      ),
    );
    expect(find.textContaining('incoming value'), findsOneWidget);
    final keepCurrent = find.text('Keep current');
    await t.ensureVisible(keepCurrent);
    await t.tap(keepCurrent);
    await t.pump();
    expect(controller.resolutionSaveIncomingCopy, isFalse);
    expect(
      controller.resolvedConflict?.incoming.payload['text'],
      'incoming value',
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('failed sync history offers retry for a linked peer', (t) async {
    if (!(Platform.isLinux || Platform.isWindows)) return;
    t.view.physicalSize = const Size(800, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final peer = PeerDesktop(
      id: 'peer-1',
      name: 'Line 4',
      host: '127.0.0.1',
      port: 1,
      fingerprint: 'fingerprint',
      secretB64: 'secret',
      pairedAt: DateTime.utc(2026, 11, 11),
    );
    final session = SyncSessionEntry(
      peerId: peer.id,
      peerName: peer.name,
      startedAt: DateTime.utc(2026, 11, 11, 10),
      finishedAt: DateTime.utc(2026, 11, 11, 10, 1),
      succeeded: false,
      error: 'Connection timed out',
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          linkControllerProvider.overrideWith(
            () => _StaticLinkController(
              LinkUiState(ready: true, peers: [peer], syncHistory: [session]),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: LinkedDevicesScreen())),
      ),
    );
    expect(find.text('Sync history'), findsOneWidget);
    expect(find.textContaining('Connection timed out'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

class _StaticLinkController extends LinkController {
  _StaticLinkController(this.initialState);

  final LinkUiState initialState;
  bool? resolutionSaveIncomingCopy;
  SyncConflictCase? resolvedConflict;

  @override
  LinkUiState build() => initialState;

  @override
  Future<void> resolveConflict(
    SyncConflictCase conflict, {
    required bool saveIncomingCopy,
  }) async {
    resolvedConflict = conflict;
    resolutionSaveIncomingCopy = saveIncomingCopy;
  }
}
