import 'package:flutter/material.dart';

import 'exalted_motion.dart';

/// One transition for every route: fade plus a small slide.
/// No animation when reduced motion is on.
class ExaltedPageTransitionsBuilder extends PageTransitionsBuilder {
  const ExaltedPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
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
  }
}

/// Registered once in AppTheme. iOS keeps the Cupertino swipe-back.
const PageTransitionsTheme kExaltedPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: ExaltedPageTransitionsBuilder(),
    TargetPlatform.linux: ExaltedPageTransitionsBuilder(),
    TargetPlatform.windows: ExaltedPageTransitionsBuilder(),
    TargetPlatform.macOS: ExaltedPageTransitionsBuilder(),
    TargetPlatform.fuchsia: ExaltedPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  },
);
