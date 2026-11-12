import 'package:exalted/core/navigation/mobile_shell.dart';
import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/link/companion_screens.dart';
import 'package:exalted/features/link/link_models.dart';
import 'package:exalted/features/link/link_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 11, 12);
  final peer = PeerDesktop(
    id: 'desktop-1',
    name: 'Packing line',
    host: '192.168.1.10',
    port: 47821,
    fingerprint: 'f' * 64,
    secretB64: 'secret',
    pairedAt: now,
  );
  final snapshot = CompanionSnapshot(
    deviceId: peer.id,
    name: peer.name,
    platform: 'linux',
    serverTime: now,
    todayScans: 8,
    todayOcr: 2,
    todayInspections: 3,
    passedInspections: 2,
    failedInspections: 1,
    reviewInspections: 0,
    activeLinkedDevices: 1,
    hardware: {
      'available': true,
      'keyence': {'status': 'connected', 'model': 'SR-751', 'scanCount': 14},
      'camera': {'status': 'ready'},
    },
    events: [
      CompanionActivityEvent(
        id: 'event-scan',
        type: 'decoder',
        title: 'Data Matrix',
        detail: 'LOT-2048',
        sourceDeviceId: peer.id,
        createdAt: now,
        status: 'success',
      ),
      CompanionActivityEvent(
        id: 'event-inspection',
        type: 'inspection',
        title: 'Inspection fail',
        detail: 'Expiry date mismatch',
        sourceDeviceId: peer.id,
        createdAt: now.subtract(const Duration(minutes: 1)),
        status: 'fail',
      ),
      CompanionActivityEvent(
        id: 'event-ocr',
        type: 'ocr',
        title: 'OCR completed',
        detail: 'Batch A-17',
        sourceDeviceId: peer.id,
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
    ],
  );

  LinkUiState linkedState() => LinkUiState(
    ready: true,
    peers: [peer],
    companionPeerId: peer.id,
    companionConnected: true,
    companionSnapshot: snapshot,
    companionHeartbeat: now,
    companionLatencyMs: 18,
  );

  ProviderScope scope(Widget child) => ProviderScope(
    overrides: [
      linkControllerProvider.overrideWith(
        () => _StaticLinkController(linkedState()),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );

  testWidgets('companion overview renders real status and desktop metrics', (
    tester,
  ) async {
    await tester.pumpWidget(scope(const CompanionDashboardScreen()));
    expect(find.text('Packing line'), findsOneWidget);
    expect(find.textContaining('Linux desktop · 18 ms'), findsOneWidget);
    expect(find.text('Desktop scans'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Desktop hardware'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Desktop hardware'), findsOneWidget);
    expect(find.text('SR-751'), findsOneWidget);
    expect(find.text('Scan on phone'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('activity filters show only the selected event class', (
    tester,
  ) async {
    await tester.pumpWidget(scope(const CompanionActivityScreen()));
    expect(find.textContaining('LOT-2048'), findsOneWidget);
    expect(find.textContaining('Expiry date mismatch'), findsOneWidget);
    expect(find.textContaining('Batch A-17'), findsOneWidget);
    await tester.tap(find.text('Scans'));
    await tester.pumpAndSettle();
    expect(find.textContaining('LOT-2048'), findsOneWidget);
    expect(find.textContaining('Expiry date mismatch'), findsNothing);
    expect(find.textContaining('Batch A-17'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mobile shell exposes five phone-first destinations', (
    tester,
  ) async {
    await tester.pumpWidget(scope(const MobileShell()));
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Live activity'), findsOneWidget);
    expect(find.textContaining('LOT-2048'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mobile companion tools include Inspection', (tester) async {
    await tester.pumpWidget(scope(const CompanionDashboardScreen()));
    expect(find.text('Quick tools'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Scanner'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Decode & OCR'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Inspection'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Verification'), findsOneWidget);
    await tester.tap(find.byTooltip('More tools'));
    await tester.pump();
    expect(find.text('Inspection'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });
}

class _StaticLinkController extends LinkController {
  _StaticLinkController(this.initialState);

  final LinkUiState initialState;

  @override
  LinkUiState build() => initialState;
}
