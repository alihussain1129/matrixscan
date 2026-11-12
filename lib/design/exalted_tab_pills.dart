import 'package:flutter/material.dart';

import 'exalted_press_scale.dart';

class ExaltedTabItem {
  const ExaltedTabItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Scrollable row of pill tabs. Selected pill is filled with the brand color.
/// Scrolls sideways on phones, hovers on desktop.
class ExaltedTabPills extends StatelessWidget {
  const ExaltedTabPills({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<ExaltedTabItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Pill(
                item: items[i],
                selected: i == selected,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ExaltedTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final sel = widget.selected;
    final fg = sel ? s.onPrimary : s.onSurface.withValues(alpha: 0.75);
    final bg = sel
        ? s.primary
        : (_hover
              ? s.onSurface.withValues(alpha: 0.09)
              : s.onSurface.withValues(alpha: 0.05));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ExaltedPressScale(
        onTap: widget.onTap,
        scale: 0.95,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: s.primary.withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.item.icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                widget.item.label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
