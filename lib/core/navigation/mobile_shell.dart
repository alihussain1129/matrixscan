import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/devices/keyence/keyence_device_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/ocr/views/ocr_workspace_screen.dart';
import '../../features/scanner/scanner_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../router/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'app_destinations.dart';

final ThemeData _darkNavTheme = AppTheme.dark();

/// Mobile shell with adaptive bottom navigation for all primary destinations:
/// Inspect, Decoder, OCR, History, Devices, and Settings.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  final Set<int> _visited = <int>{};

  void _select(int i) => ref.read(navIndexProvider.notifier).set(i);

  Widget _screenFor(int i) => switch (i) {
    kHomeTab => const HomeScreen(),
    kScanTab => const ScannerScreen(),
    kOcrTab => const OcrWorkspaceScreen(),
    kHistoryTab => const HistoryScreen(),
    kDevicesTab => const KeyenceDeviceScreen(),
    _ => const SettingsScreen(),
  };

  void _showMore(int index) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in kDestinations.skip(kBottomBarCount))
              ListTile(
                leading: Icon(d.index == index ? d.activeIcon : d.icon),
                title: Text(d.label),
                selected: d.index == index,
                onTap: () {
                  Navigator.pop(ctx);
                  _select(d.index);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navIndexProvider);
    _visited.add(index);
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
          child: _MobileCompactBar(
            index: index,
            onSelect: _select,
            onMore: () => _showMore(index),
          ),
        ),
      ),
    );
  }
}

class _MobileCompactBar extends StatelessWidget {
  const _MobileCompactBar({
    required this.index,
    required this.onSelect,
    required this.onMore,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.exalted;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final d in kDestinations.take(kBottomBarCount))
                Expanded(
                  child: _MobileBarItem(
                    icon: d.index == index ? d.activeIcon : d.icon,
                    label: d.label,
                    selected: d.index == index,
                    onTap: () => onSelect(d.index),
                  ),
                ),
              Expanded(
                child: _MobileBarItem(
                  icon: Icons.more_horiz,
                  label: 'More',
                  selected: index >= kBottomBarCount,
                  onTap: onMore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileBarItem extends StatelessWidget {
  const _MobileBarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    final color = selected ? colors.primaryText : colors.muted;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: AppMotion.normal,
                curve: AppMotion.curve,
                width: 50,
                height: 28,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary.withAlpha(40)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Icon(icon, color: color, size: AppSizes.iconMd),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelSmall!.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
