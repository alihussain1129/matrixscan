import 'package:flutter/material.dart';

/// Slides its child up with a small overshoot and fades it in, once.
/// Used for the scan result card. No motion in reduced-motion mode.
class ExaltedSpringUp extends StatelessWidget {
  const ExaltedSpringUp({super.key, required this.child, this.dy = 48});

  final Widget child;
  final double dy;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - v) * dy),
          child: child,
        ),
      ),
    );
  }
}
