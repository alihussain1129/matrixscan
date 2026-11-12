import 'package:flutter/material.dart';

import 'exalted_motion.dart';

/// Consistent page transition: fade plus a small slide.
/// No transition when reduced motion is on.
class ExaltedPageRoute<T> extends PageRouteBuilder<T> {
  ExaltedPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: ExaltedMotion.slow,
        reverseTransitionDuration: ExaltedMotion.base,
        pageBuilder: (context, animation, secondary) => builder(context),
        transitionsBuilder: (context, animation, secondary, child) {
          if (ExaltedMotion.reduced(context)) return child;
          final fade = animation.drive(CurveTween(curve: ExaltedMotion.curve));
          final slide = animation.drive(
            Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: ExaltedMotion.curve)),
          );
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      );
}
