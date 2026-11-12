import 'package:flutter/material.dart';

import '../../design/exalted_press_scale.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// Card with thin outline. Shadow in light mode, outline only in dark mode.
/// Give it [onTap] and it presses in and springs back like a real button.
class ExaltedCard extends StatelessWidget {
  const ExaltedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final isDark = theme.brightness == Brightness.dark;

    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? theme.colorScheme.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.outline),
        boxShadow: isDark ? const [] : AppShadows.card,
      ),
      // Lets ListTile and SwitchListTile show hover and tap effects
      // inside the decorated box.
      child: Material(type: MaterialType.transparency, child: child),
    );

    if (onTap == null) return card;
    return ExaltedPressScale(onTap: onTap, haptic: true, child: card);
  }
}
