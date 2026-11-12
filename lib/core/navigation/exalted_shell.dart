import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/devices/keyence/keyence_device_screen.dart';
import '../../features/gallery/gallery_import_service.dart';
import '../../features/history/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/diagnostics/diagnostics_screen.dart';
import '../../features/inspection/inspection_data_screen.dart';
import '../../features/link/linked_devices_screen.dart';
import '../../features/ocr/ocr_entry.dart';
import '../../features/ocr/views/ocr_workspace_screen.dart';
import '../../features/scanner/desktop_decoder_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../verify/verification_screen.dart';
import '../router/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/command_palette.dart';
import '../widgets/exalted_logo.dart';
import 'app_destinations.dart';
import 'compact_nav_bar.dart';
import 'desktop_chrome.dart';

// The scanner tab uses dark chrome, so its bottom bar is dark too.
final ThemeData _darkNavTheme = AppTheme.dark();

const List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
  LogicalKeyboardKey.digit0,
];

/// Number of Ctrl+digit shortcuts. A test keeps this at least as large as
/// the destination list, because a missing key would crash the shell.
int get kShortcutKeyCount => _digitKeys.length;

/// The Windows and Linux workstation shell. Phones use [MobileShell].
class ExaltedShell extends ConsumerStatefulWidget {
  const ExaltedShell({super.key});

  @override
  ConsumerState<ExaltedShell> createState() => _ExaltedShellState();
}

class _ExaltedShellState extends ConsumerState<ExaltedShell> {
  // Keeps screen state (camera, scroll) when a resize changes the layout.
  final GlobalKey _bodyKey = GlobalKey();
  // Screens are created the first time they are visited, then kept alive.
  final Set<int> _visited = <int>{};
  bool _collapsed = false;

  void _select(int i) => ref.read(navIndexProvider.notifier).set(i);

  Widget _screenFor(int i) => switch (i) {
    kHomeTab => const HomeScreen(),
    kScanTab => const DesktopDecoderScreen(),
    kOcrTab => const OcrWorkspaceScreen(),
    kHistoryTab => const HistoryScreen(),
    kDevicesTab => const KeyenceDeviceScreen(),
    kLinkTab => const LinkedDevicesScreen(),
    kVerificationTab => const VerificationScreen(),
    kDiagnosticsTab => const DiagnosticsScreen(),
    kInspectionTab => const InspectionDataScreen(),
    _ => const SettingsScreen(),
  };

  Widget _body(int index) {
    _visited.add(index);
    return IndexedStack(
      key: _bodyKey,
      index: index,
      children: [
        for (final d in kDestinations)
          _visited.contains(d.index)
              ? _screenFor(d.index)
              : const SizedBox.shrink(),
      ],
    );
  }

  Future<void> _openImage() async {
    final picked = await GalleryImportService().pickImage();
    if (picked.path != null && mounted) {
      await openOcr(context, ref, picked.path!);
    }
  }

  void _showMore(int index) {
    showMoreDestinations(context, index: index, onSelect: _select);
  }

  Future<void> _showCommandPalette() async {
    await showCommandPalette(context);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navIndexProvider);
    // Desktop windows never fall back to the phone layout. A narrow window
    // collapses the sidebar to a rail instead.
    final layout = context.layout == ExaltedLayout.compact
        ? ExaltedLayout.medium
        : context.layout;
    final body = _body(index);

    if (layout == ExaltedLayout.compact) {
      final navTheme = index == kScanTab ? _darkNavTheme : Theme.of(context);
      return PopScope(
        canPop: index == kHomeTab,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _select(kHomeTab);
        },
        child: Scaffold(
          body: body,
          bottomNavigationBar: Theme(
            data: navTheme,
            child: CompactNavBar(
              index: index,
              onSelect: _select,
              onMore: () => _showMore(index),
            ),
          ),
        ),
      );
    }

    final expanded = layout == ExaltedLayout.expanded;
    final title = kDestinations[index].label;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _showCommandPalette,
        for (final d in kDestinations)
          SingleActivator(_digitKeys[d.index], control: true): () =>
              _select(d.index),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _Sidebar(
                      index: index,
                      collapsed: !expanded || _collapsed,
                      canToggle: expanded,
                      onSelect: _select,
                      onToggle: () => setState(() => _collapsed = !_collapsed),
                      onOpenImage: _openImage,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          DesktopTopBar(
                            title: title,
                            scannerActive: _visited.contains(kScanTab),
                            devicesActive: _visited.contains(kDevicesTab),
                            onOpenCommandPalette: _showCommandPalette,
                          ),
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              DesktopStatusBar(
                scannerActive: _visited.contains(kScanTab),
                devicesActive: _visited.contains(kDevicesTab),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- sidebar

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.collapsed,
    required this.canToggle,
    required this.onSelect,
    required this.onToggle,
    required this.onOpenImage,
  });

  final int index;
  final bool collapsed;
  final bool canToggle;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;
  final VoidCallback onOpenImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.exalted;
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      width: collapsed ? AppSizes.sidebarCollapsedWidth : AppSizes.sidebarWidth,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(right: BorderSide(color: colors.outline)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Decided from the real width so the animation never overflows.
          final showLabel = c.maxWidth > 160;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Align(
                  alignment: showLabel
                      ? Alignment.centerLeft
                      : Alignment.center,
                  child: ExaltedLogo(width: showLabel ? 130 : 40),
                ),
              ),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: ListView(
                  children: [
                    for (final g in kDestinationGroups) ...[
                      _SidebarGroupHeader(title: g.title, showLabel: showLabel),
                      for (final i in g.indexes)
                        _SidebarItem(
                          destination: kDestinations[i],
                          selected: i == index,
                          showLabel: showLabel,
                          onTap: () => onSelect(i),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: showLabel
                    ? OutlinedButton.icon(
                        onPressed: onOpenImage,
                        icon: const Icon(
                          Icons.file_open_outlined,
                          size: AppSizes.iconSm,
                        ),
                        label: const Text('Open image'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(
                            AppSizes.buttonRegular,
                          ),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Open image',
                        onPressed: onOpenImage,
                        icon: const Icon(Icons.file_open_outlined),
                      ),
              ),
              if (canToggle)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Align(
                    alignment: showLabel
                        ? Alignment.centerRight
                        : Alignment.center,
                    child: IconButton(
                      tooltip: collapsed
                          ? 'Expand sidebar'
                          : 'Collapse sidebar',
                      onPressed: onToggle,
                      icon: Icon(
                        collapsed ? Icons.chevron_right : Icons.chevron_left,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          );
        },
      ),
    );
  }
}

class _SidebarGroupHeader extends StatelessWidget {
  const _SidebarGroupHeader({required this.title, required this.showLabel});

  final String title;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    if (!showLabel) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Divider(color: colors.outline),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.muted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.exalted;
    final fg = selected ? colors.primaryText : colors.muted;

    Widget item = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.button),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.button),
                onTap: onTap,
                child: SizedBox(
                  height: AppSizes.buttonRegular,
                  child: Row(
                    mainAxisAlignment: showLabel
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      if (showLabel) const SizedBox(width: AppSpacing.md),
                      Icon(
                        selected ? destination.activeIcon : destination.icon,
                        size: AppSizes.iconMd,
                        color: fg,
                      ),
                      if (showLabel) ...[
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            destination.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: fg,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              top: 8,
              bottom: 8,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
        ],
      ),
    );

    if (!showLabel) {
      item = Tooltip(message: destination.label, child: item);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: item,
    );
  }
}
