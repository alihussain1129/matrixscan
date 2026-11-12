import 'package:flutter/material.dart';

/// Meaning of a status. The chip always shows an icon and a label, so the
/// meaning never depends on colour alone.
enum ExaltedStatusKind { success, warning, error, info, neutral }

/// Compact status indicator used for scanner, link, sync and verification
/// state across desktop and mobile.
class ExaltedStatusChip extends StatelessWidget {
  const ExaltedStatusChip({
    super.key,
    required this.label,
    this.kind = ExaltedStatusKind.neutral,
    this.icon,
  });

  final String label;
  final ExaltedStatusKind kind;

  /// Overrides the default icon for [kind].
  final IconData? icon;

  static IconData defaultIcon(ExaltedStatusKind kind) {
    switch (kind) {
      case ExaltedStatusKind.success:
        return Icons.check_circle_outline;
      case ExaltedStatusKind.warning:
        return Icons.warning_amber_rounded;
      case ExaltedStatusKind.error:
        return Icons.error_outline;
      case ExaltedStatusKind.info:
        return Icons.info_outline;
      case ExaltedStatusKind.neutral:
        return Icons.circle_outlined;
    }
  }

  Color _foreground(ColorScheme scheme, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    switch (kind) {
      case ExaltedStatusKind.success:
        return dark ? const Color(0xFF6FE0B0) : const Color(0xFF1B7A55);
      case ExaltedStatusKind.warning:
        return dark ? const Color(0xFFFFC857) : const Color(0xFF8A5A00);
      case ExaltedStatusKind.error:
        return scheme.error;
      case ExaltedStatusKind.info:
        return scheme.primary;
      case ExaltedStatusKind.neutral:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _foreground(theme.colorScheme, theme.brightness);
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? defaultIcon(kind), size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
