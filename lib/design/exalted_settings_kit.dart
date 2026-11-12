import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Section title with a small accent bar and an optional sub line.
class ExaltedSectionHeader extends StatelessWidget {
  const ExaltedSectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: subtitle == null ? 20 : 38,
            decoration: BoxDecoration(
              color: s.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: text.bodySmall?.copyWith(
                        color: s.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded card that holds rows and draws thin dividers between them.
class ExaltedGroup extends StatelessWidget {
  const ExaltedGroup({super.key, required this.children, this.inset = 68});

  final List<Widget> children;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = s.onSurface.withValues(alpha: dark ? 0.10 : 0.08);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0)
        rows.add(Divider(height: 1, thickness: 1, indent: inset, color: line));
      rows.add(children[i]);
    }
    final radius = BorderRadius.circular(18);
    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: radius,
        border: Border.all(color: line),
        boxShadow: dark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: rows),
        ),
      ),
    );
  }
}

/// Rounded square with an icon, tinted with the brand color.
class ExaltedIconChip extends StatelessWidget {
  const ExaltedIconChip({super.key, required this.icon, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: s.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: s.primary, size: size * 0.5),
    );
  }
}

/// One settings row: icon chip, title, sub line, and a widget on the right.
/// Highlights on hover (desktop) and ripples on touch (Android).
class ExaltedSettingTile extends StatefulWidget {
  const ExaltedSettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  State<ExaltedSettingTile> createState() => _ExaltedSettingTileState();
}

class _ExaltedSettingTileState extends State<ExaltedSettingTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: _hover && widget.onTap != null
                ? s.primary.withValues(alpha: 0.05)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                ExaltedIconChip(icon: widget.icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            widget.subtitle!,
                            style: text.bodySmall?.copyWith(
                              color: s.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 12),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row with a switch. Tapping anywhere on the row toggles it.
class ExaltedSwitchTile extends StatelessWidget {
  const ExaltedSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  void _set(bool v) {
    HapticFeedback.selectionClick();
    onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return ExaltedSettingTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => _set(!value),
      trailing: Switch(
        value: value,
        onChanged: onChanged == null ? null : _set,
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Icon(Icons.check)
              : null,
        ),
      ),
    );
  }
}
