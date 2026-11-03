import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/devices/keyence/keyence_device_screen.dart';
import '../../features/devices/keyence/keyence_sr751_client.dart';
import '../../features/gallery/gallery_import_service.dart';
import '../../features/history/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/ocr/ocr_entry.dart';
import '../../features/ocr/views/ocr_workspace_screen.dart';
import '../../features/scanner/scanner_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../router/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/exalted_logo.dart';
import 'app_destinations.dart';

// The scanner tab uses dark chrome, so its bottom bar is dark too.
final ThemeData _darkNavTheme = AppTheme.dark();

const List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];

/// One shell for Android, Linux and Windows. The layout depends only on the
/// window width, never on the operating system.
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
    kScanTab => const ScannerScreen(),
    kOcrTab => const OcrWorkspaceScreen(),
    kHistoryTab => const HistoryScreen(),
    kDevicesTab => const KeyenceDeviceScreen(),
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
    final layout = context.layout;
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
            child: _CompactBar(
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
                          _TopBar(title: title),
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const _StatusBar(),
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
                    for (final d in kDestinations)
                      _SidebarItem(
                        destination: d,
                        selected: d.index == index,
                        showLabel: showLabel,
                        onTap: () => onSelect(d.index),
                      ),
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
          Material(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
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

// ---------------------------------------------------------------- top bar

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.exalted;
    return Container(
      height: AppSizes.toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: AnimatedSwitcher(
        duration: AppMotion.fast,
        child: Text(
          title,
          key: ValueKey<String>(title),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- status bar

/// Shows only state the app can report: the KEYENCE client connection and
/// which OCR engine this platform uses. It makes no readiness claims.
class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.exalted;
    final text = theme.textTheme.labelSmall!;
    final keyence = ref.watch(keyenceSr751ClientProvider);
    final connected = keyence.status == KeyenceConnectionStatus.connected;
    final ocrEngine = Platform.isAndroid ? 'Google ML Kit' : 'Tesseract';
    final platform = Platform.isLinux
        ? 'Linux'
        : Platform.isWindows
        ? 'Windows'
        : Platform.isAndroid
        ? 'Android'
        : Platform.operatingSystem;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.router_outlined,
            size: AppSizes.iconXs,
            color: connected ? colors.valid : colors.muted,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              connected
                  ? 'KEYENCE SR-751 connected · ${keyence.host}:${keyence.port}'
                  : 'KEYENCE SR-751 not connected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.copyWith(
                color: connected ? colors.valid : colors.muted,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Icon(
            Icons.text_fields_outlined,
            size: AppSizes.iconXs,
            color: colors.muted,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text('OCR engine: $ocrEngine', style: text),
          const Spacer(),
          Text(platform, style: text),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ compact bar

class _CompactBar extends StatelessWidget {
  const _CompactBar({
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
          height: 68,
          child: Row(
            children: [
              for (final d in kDestinations.take(kBottomBarCount))
                Expanded(
                  child: _BarItem(
                    icon: d.index == index ? d.activeIcon : d.icon,
                    label: d.label,
                    selected: d.index == index,
                    onTap: () => onSelect(d.index),
                  ),
                ),
              Expanded(
                child: _BarItem(
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

class _BarItem extends StatelessWidget {
  const _BarItem({
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
                width: 56,
                height: 32,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Icon(icon, color: color, size: AppSizes.iconLg),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelSmall!.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
