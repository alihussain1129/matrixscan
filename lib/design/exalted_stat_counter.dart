import 'package:flutter/material.dart';

import 'exalted_motion.dart';
import 'exalted_tokens.dart';

/// Dashboard number that counts smoothly to its new value.
/// Implicit animation, so there is no controller to dispose.
class ExaltedStatCounter extends StatelessWidget {
  const ExaltedStatCounter({
    super.key,
    required this.value,
    required this.label,
    this.icon,
  });

  final int value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = ExaltedTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(ExaltedSpace.md),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(ExaltedRadius.md),
        border: Border.all(color: t.outline),
        boxShadow: ExaltedShadow.soft(Theme.of(context).brightness),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: t.brand),
            const SizedBox(width: ExaltedSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: value.toDouble()),
                  duration: ExaltedMotion.d(context, ExaltedMotion.slow),
                  curve: ExaltedMotion.curve,
                  builder: (context, v, _) => Text(
                    v.round().toString(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
