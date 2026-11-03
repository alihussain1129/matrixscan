import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/devices/keyence/keyence_device_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/ocr/views/ocr_workspace_screen.dart';
import '../../features/scanner/scanner_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../widgets/exalted_bottom_nav.dart';
import 'app_destinations.dart';

// The scanner tab uses dark chrome, so its bottom bar is dark too.
final ThemeData _darkNavTheme = AppTheme.dark();

/// Shell for phones: the original four-tab bottom navigation (Home, Scan,
/// History, Settings) around the original scanner screen.
///
/// Bar positions map to the shared destination numbers, so every screen that
/// sets [navIndexProvider] keeps working.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  static const List<int> _tabs = [
    kHomeTab,
    kScanTab,
    kHistoryTab,
    kSettingsTab,
  ];

  // Screens are created the first time they are visited, then kept alive.
  final Set<int> _visited = <int>{};

  Widget _screenFor(int i) => switch (i) {
    kHomeTab => const HomeScreen(),
    kScanTab => const ScannerScreen(),
    kOcrTab => const OcrWorkspaceScreen(),
    kHistoryTab => const HistoryScreen(),
    kDevicesTab => const KeyenceDeviceScreen(),
    _ => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navIndexProvider);
    _visited.add(index);
    final position = _tabs.indexOf(index);
    final navTheme = index == kScanTab ? _darkNavTheme : Theme.of(context);

    return PopScope(
      canPop: index == kHomeTab,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) ref.read(navIndexProvider.notifier).set(kHomeTab);
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
          child: ExaltedBottomNav(
            index: position < 0 ? 0 : position,
            onChanged: (i) => ref.read(navIndexProvider.notifier).set(_tabs[i]),
          ),
        ),
      ),
    );
  }
}
