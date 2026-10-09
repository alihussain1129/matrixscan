import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/exalted_bottom_nav.dart';
import 'features/history/history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/scanner/scanner_screen.dart';
import 'features/settings/settings_screen.dart';

// The scanner tab uses dark chrome, so its nav bar is dark too.
final ThemeData _darkNavTheme = AppTheme.dark();

/// App shell: four tabs (Home, Scan, History, Settings) with bottom navigation.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(navIndexProvider);
    final navTheme = index == kScanTab ? _darkNavTheme : Theme.of(context);

    return PopScope(
      canPop: index == kHomeTab,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) ref.read(navIndexProvider.notifier).set(kHomeTab);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: const [
            HomeScreen(),
            ScannerScreen(),
            HistoryScreen(),
            SettingsScreen(),
          ],
        ),
        bottomNavigationBar: Theme(
          data: navTheme,
          child: ExaltedBottomNav(
            index: index,
            onChanged: (i) => ref.read(navIndexProvider.notifier).set(i),
          ),
        ),
      ),
    );
  }
}
