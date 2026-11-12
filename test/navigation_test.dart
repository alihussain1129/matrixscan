import 'package:exalted/core/navigation/app_destinations.dart';
import 'package:exalted/core/navigation/exalted_shell.dart';
import 'package:exalted/core/navigation/desktop_chrome.dart';
import 'package:exalted/core/router/app_router.dart';
import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/core/theme/app_tokens.dart';
import 'package:exalted/features/devices/keyence/keyence_scanner_coordinator.dart';
import 'package:exalted/features/link/link_providers.dart';
import 'package:exalted/features/scanner/scanner_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layout is chosen from width only', () {
    expect(AppBreakpoints.of(320), ExaltedLayout.compact);
    expect(AppBreakpoints.of(719), ExaltedLayout.compact);
    expect(AppBreakpoints.of(720), ExaltedLayout.medium);
    expect(AppBreakpoints.of(1099), ExaltedLayout.medium);
    expect(AppBreakpoints.of(1100), ExaltedLayout.expanded);
    expect(AppBreakpoints.of(2560), ExaltedLayout.expanded);
  });

  test('one destination list, same names and order everywhere', () {
    expect(kDestinations.map((d) => d.label).toList(), [
      'Dashboard',
      'Scanner',
      'Decode & OCR',
      'History',
      'Devices',
      'Synchronization',
      'Verification',
      'Diagnostics',
      'Settings',
      'Inspection',
    ]);
    for (var i = 0; i < kDestinations.length; i++) {
      expect(kDestinations[i].index, i);
    }
  });

  test('tab constants match the destinations', () {
    expect(kHomeTab, 0);
    expect(kScanTab, 1);
    expect(kOcrTab, 2);
    expect(kHistoryTab, 3);
    expect(kDevicesTab, 4);
    expect(kLinkTab, 5);
    expect(kVerificationTab, 6);
    expect(kDiagnosticsTab, 7);
    expect(kSettingsTab, 8);
    expect(kInspectionTab, 9);
    expect(kBottomBarCount, 4);
  });

  test('every destination has a desktop shortcut key', () {
    expect(kShortcutKeyCount, greaterThanOrEqualTo(kDestinations.length));
  });

  test('sidebar groups cover every destination exactly once', () {
    final seen = <int>[for (final g in kDestinationGroups) ...g.indexes];
    expect(seen.toSet().length, seen.length);
    expect(seen.toSet(), {for (final d in kDestinations) d.index});
  });

  testWidgets('desktop chrome leaves background services uninitialized', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Column(
              children: [
                DesktopTopBar(title: 'Dashboard'),
                DesktopStatusBar(),
              ],
            ),
          ),
        ),
      ),
    );

    expect(container.exists(scannerControllerProvider), isFalse);
    expect(container.exists(keyenceScannerCoordinatorProvider), isFalse);
    expect(container.exists(linkControllerProvider), isFalse);
  });
}
