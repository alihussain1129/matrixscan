import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

enum StatusBadgeVariant { success, warning, error, info, neutral, processing }

/// Industrial status badge that communicates state through icon, text, and color.
/// Never relies on color alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.variant = StatusBadgeVariant.neutral,
    this.icon,
    this.sublabel,
    this.compact = false,
  });

  final String label;
  final StatusBadgeVariant variant;
  final IconData? icon;
  final String? sublabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.exalted;
    final theme = Theme.of(context);

    Color bg;
    Color fg;
    Color border;
    IconData defaultIcon;

    switch (variant) {
      case StatusBadgeVariant.success:
        bg = colors.valid.withAlpha(25);
        fg = colors.valid;
        border = colors.valid.withAlpha(80);
        defaultIcon = Icons.check_circle_outline;
        break;
      case StatusBadgeVariant.warning:
        bg = colors.warning.withAlpha(25);
        fg = colors.warning;
        border = colors.warning.withAlpha(80);
        defaultIcon = Icons.warning_amber_rounded;
        break;
      case StatusBadgeVariant.error:
        bg = theme.colorScheme.error.withAlpha(25);
        fg = theme.colorScheme.error;
        border = theme.colorScheme.error.withAlpha(80);
        defaultIcon = Icons.error_outline;
        break;
      case StatusBadgeVariant.info:
        bg = colors.info.withAlpha(25);
        fg = colors.info;
        border = colors.info.withAlpha(80);
        defaultIcon = Icons.info_outline;
        break;
      case StatusBadgeVariant.processing:
        bg = colors.aqua.withAlpha(25);
        fg = colors.aqua;
        border = colors.aqua.withAlpha(80);
        defaultIcon = Icons.sync;
        break;
      case StatusBadgeVariant.neutral:
        bg = colors.surfaceRaised;
        fg = colors.muted;
        border = colors.outline;
        defaultIcon = Icons.circle_outlined;
        break;
    }

    final displayIcon = icon ?? defaultIcon;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (variant == StatusBadgeVariant.processing)
            SizedBox(
              width: compact ? 10 : 12,
              height: compact ? 10 : 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: fg),
            )
          else
            Icon(displayIcon, size: compact ? 12 : 14, color: fg),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          if (sublabel != null && sublabel!.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(
              '($sublabel)',
              style: TextStyle(
                color: fg.withAlpha(180),
                fontSize: compact ? 10 : 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
