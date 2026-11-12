import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ExaltedSegment<T> {
  const ExaltedSegment({required this.value, required this.label, this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// Pill-shaped choice bar. The selected thumb slides to the new option.
/// Needs a bounded width (put it in a Padding, Expanded or SizedBox).
class ExaltedSegmented<T> extends StatelessWidget {
  const ExaltedSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<ExaltedSegment<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    final raw = options.indexWhere((o) => o.value == value);
    final idx = raw < 0 ? 0 : raw;
    final n = options.length;

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: s.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final segW = box.maxWidth / n;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: idx * segW,
                width: segW,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: s.primary,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: s.primary.withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onChanged(options[i].value);
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (options[i].icon != null) ...[
                                    Icon(
                                      options[i].icon,
                                      size: 16,
                                      color: i == idx
                                          ? s.onPrimary
                                          : s.onSurface.withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: base.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: i == idx
                                          ? s.onPrimary
                                          : s.onSurface.withValues(alpha: 0.7),
                                    ),
                                    child: Text(options[i].label),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
