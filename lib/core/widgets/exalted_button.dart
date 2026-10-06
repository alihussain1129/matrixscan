import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// Exalted button: red raised fill (or outlined), white bold caps, press animation.
class ExaltedButton extends StatefulWidget {
  const ExaltedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;
  final bool expand;

  @override
  State<ExaltedButton> createState() => _ExaltedButtonState();
}

class _ExaltedButtonState extends State<ExaltedButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<ExaltedColors>()!;
    final enabled = widget.onPressed != null;

    final Color background = widget.outlined
        ? Colors.transparent
        : (_pressed ? colors.primaryPressed : scheme.primary);
    final Color foreground =
        widget.outlined ? colors.primaryText : scheme.onPrimary;

    final textStyle = theme.textTheme.labelLarge!.copyWith(
      color: foreground,
      fontSize: 15,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => _setPressed(true) : null,
            onTapUp: enabled ? (_) => _setPressed(false) : null,
            onTapCancel: enabled ? () => _setPressed(false) : null,
            onTap: widget.onPressed,
            child: AnimatedScale(
              scale: _pressed ? 0.96 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                constraints: BoxConstraints(
                  minHeight: 48,
                  minWidth: widget.expand ? double.infinity : 48,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  border: widget.outlined
                      ? Border.all(color: colors.primaryText, width: 1.5)
                      : null,
                  boxShadow: (widget.outlined || !enabled || _pressed)
                      ? const []
                      : AppShadows.button,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 20, color: foreground),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(widget.label.toUpperCase(), style: textStyle),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}