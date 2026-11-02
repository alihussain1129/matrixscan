import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/desktop_app_shell.dart';
import 'core/widgets/exalted_bottom_nav.dart';
import 'features/devices/keyence/keyence_device_screen.dart';
import 'features/history/history_screen.dart';
import 'features/home/home_screen.dart';
import 'features/ocr/views/ocr_workspace_screen.dart';
import 'features/scanner/scanner_screen.dart';
import 'features/settings/settings_screen.dart';

// The scanner tab uses dark chrome, so its nav bar is dark too.
final ThemeData _darkNavTheme = AppTheme.dark();

/// Desktop-specific navigation index notifier allowing access to all 6 industrial workspaces.
class DesktopNavIndexNotifier extends Notifier<int> {
  @override
  int build() => 1; // Default to Decoder Workspace on desktop

  void set(int index) => state = index;
}

final desktopNavIndexProvider =
    NotifierProvider<DesktopNavIndexNotifier, int>(
  DesktopNavIndexNotifier.new,
);

/// App shell: adaptive desktop sidebar and mobile bottom navigation.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop =
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS) &&
        MediaQuery.sizeOf(context).width >= 720;

    if (isDesktop) {
      final desktopIndex = ref.watch(desktopNavIndexProvider);

      const desktopChildren = [
        HomeScreen(),
        ScannerScreen(),
        OcrWorkspaceScreen(),
        KeyenceDeviceScreen(),
        HistoryScreen(),
        SettingsScreen(),
      ];

      return DesktopAppShell(
        index: desktopIndex,
        onChanged: (i) => ref.read(desktopNavIndexProvider.notifier).set(i),
        children: desktopChildren,
      );
    }

    final index = ref.watch(navIndexProvider);

    const mobileChildren = [
      HomeScreen(),
      ScannerScreen(),
      HistoryScreen(),
      SettingsScreen(),
    ];

    final navTheme = index == kScanTab ? _darkNavTheme : Theme.of(context);

    return PopScope(
      canPop: index == kHomeTab,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) ref.read(navIndexProvider.notifier).set(kHomeTab);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: mobileChildren,
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
