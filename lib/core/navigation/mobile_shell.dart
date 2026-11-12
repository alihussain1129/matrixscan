import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/diagnostics/diagnostics_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/inspection/inspection_data_screen.dart';
import '../../features/link/companion_screens.dart';
import '../../features/link/link_providers.dart';
import '../../features/link/companion_notifications.dart';
import '../../features/ocr/views/ocr_workspace_screen.dart';
import '../../features/scanner/scanner_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../verify/verification_screen.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import 'app_destinations.dart';

final ThemeData _darkNavTheme = AppTheme.dark();

/// Phone-first companion navigation. Scanner, Decode & OCR, Verification, and
/// Diagnostics remain reachable from the Overview tools menu.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  final Set<int> _visited = <int>{};

  static const _mobileTabs = [
    kHomeTab,
    kLinkTab,
    kHistoryTab,
    kDevicesTab,
    kSettingsTab,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        CompanionNotifications.initialize(
          openActivity: () {
            if (mounted) _select(kLinkTab);
          },
        ),
      );
    });
  }

  void _select(int i) => ref.read(navIndexProvider.notifier).set(i);

  Widget _screenFor(int i) => switch (i) {
    kHomeTab => const CompanionDashboardScreen(),
    kScanTab => const ScannerScreen(),
    kOcrTab => const OcrWorkspaceScreen(),
    kHistoryTab => const HistoryScreen(),
    kDevicesTab => const MobileDevicesScreen(),
    kLinkTab => const CompanionActivityScreen(),
    kVerificationTab => const VerificationScreen(),
    kDiagnosticsTab => const DiagnosticsScreen(),
    kInspectionTab => const InspectionDataScreen(),
    _ => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navIndexProvider);
    ref.listen<LinkUiState>(linkControllerProvider, (previous, next) {
      if (previous != null && previous.peers.isEmpty && next.peers.isNotEmpty) {
        _select(kHomeTab);
      }
    });
    ref.listen<int>(navIndexProvider, (previous, next) {
      if (next == kHomeTab && previous != null && previous != kHomeTab) {
        ref.read(linkControllerProvider.notifier).sweepLocalRecords();
      }
    });
    _visited.add(index);
    final selectedTab = _mobileTabs.indexOf(index);
    final navTheme = index == kScanTab ? _darkNavTheme : Theme.of(context);

    return PopScope(
      canPop: index == kHomeTab,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _select(kHomeTab);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            for (final d in kDestinations)
              _visited.contains(d.index)
                  ? _screenFor(d.index)
                  : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: Theme(
          data: navTheme,
          child: NavigationBar(
            selectedIndex: selectedTab < 0 ? 0 : selectedTab,
            onDestinationSelected: (tab) => _select(_mobileTabs[tab]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Overview',
              ),
              NavigationDestination(
                icon: Icon(Icons.notifications_active_outlined),
                selectedIcon: Icon(Icons.notifications_active),
                label: 'Activity',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.devices_outlined),
                selectedIcon: Icon(Icons.devices),
                label: 'Devices',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
