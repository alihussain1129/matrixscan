import '../../design/exalted_press_scale.dart';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';
import 'app_destinations.dart';

/// Bottom navigation for phones and narrow windows. One implementation for
/// every platform: the first [kBottomBarCount] destinations plus "More".
class CompactNavBar extends StatelessWidget {
  const CompactNavBar({
    super.key,
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
                  child: _NavBarItem(
                    icon: d.index == index ? d.activeIcon : d.icon,
                    label: d.label,
                    selected: d.index == index,
                    onTap: () => onSelect(d.index),
                  ),
                ),
              Expanded(
                child: _NavBarItem(
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

/// The destinations that do not fit in the bottom bar.
Future<void> showMoreDestinations(
  BuildContext context, {
  required int index,
  required ValueChanged<int> onSelect,
}) {
  return showModalBottomSheet<void>(
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
                onSelect(d.index);
              },
            ),
        ],
      ),
    ),
  );
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
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
        child: ExaltedPressScale(
          onTap: onTap,
          scale: 0.9,
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
                child: ExaltedBounceIcon(
                  icon: icon,
                  color: color,
                  size: AppSizes.iconLg,
                  selected: selected,
                ),
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
