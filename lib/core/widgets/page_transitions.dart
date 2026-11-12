import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Shared page-transition animations used across desktop and mobile.
///
/// All transitions use [AppMotion] durations so motion is consistent and
/// respects the product's "subtle motion" principle.

/// A fade transition for entering/leaving a page.
class FadePageTransition extends StatelessWidget {
  const FadePageTransition({super.key, required this.child, this.animation});

  final Widget child;
  final Animation<double>? animation;

  @override
  Widget build(BuildContext context) {
    final anim = animation ?? const AlwaysStoppedAnimation(1.0);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    return FadeTransition(
      opacity: anim.drive(
        Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: AppMotion.curve)),
      ),
      child: child,
    );
  }
}

/// A slide transition for entering a page from an edge.
class SlidePageTransition extends StatelessWidget {
  const SlidePageTransition({
    super.key,
    required this.child,
    this.animation,
    this.beginOffset = const Offset(0.0, 0.15),
  });

  final Widget child;
  final Animation<double>? animation;
  final Offset beginOffset;

  @override
  Widget build(BuildContext context) {
    final anim = animation ?? const AlwaysStoppedAnimation(1.0);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    return SlideTransition(
      position: anim.drive(
        Tween<Offset>(
          begin: beginOffset,
          end: Offset.zero,
        ).chain(CurveTween(curve: AppMotion.curve)),
      ),
      child: child,
    );
  }
}

/// A shared-axis transition (used for bottom sheets, dialogs).
class SharedAxisPageTransition extends StatelessWidget {
  const SharedAxisPageTransition({
    super.key,
    required this.child,
    this.animation,
    this.axis = Axis.horizontal,
  });

  final Widget child;
  final Animation<double>? animation;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final anim = animation ?? const AlwaysStoppedAnimation(1.0);
    return SharedAxisTransition(
      animation: anim,
      secondaryAnimation: const AlwaysStoppedAnimation<double>(0.0),
      transitionType: _transitionType(axis),
      fillColor: Colors.transparent,
      child: child,
    );
  }

  SharedAxisTransitionType _transitionType(Axis axis) {
    switch (axis) {
      case Axis.horizontal:
        return SharedAxisTransitionType.horizontal;
      case Axis.vertical:
        return SharedAxisTransitionType.vertical;
    }
  }
}

/// Wraps a page so it animates in with a fade when first shown.
class AnimatedEntry extends AnimatedWidget {
  const AnimatedEntry({
    super.key,
    required this.child,
    required Animation<double> animation,
  }) : super(listenable: animation);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: (listenable as Animation<double>).drive(
        Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: AppMotion.curve)),
      ),
      child: child,
    );
  }
}

/// A reusable route builder that applies a fade transition to any page.
class FadeRoute<T> extends PageRouteBuilder<T> {
  FadeRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadePageTransition(animation: animation, child: child),
        transitionDuration: AppMotion.normal,
      );
}

/// A reusable route builder that applies a slide transition to any page.
class SlideRoute<T> extends PageRouteBuilder<T> {
  SlideRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            SlidePageTransition(animation: animation, child: child),
        transitionDuration: AppMotion.normal,
      );
}

/// An animation controller helper for sidebar collapse/expand.
class SidebarMotion extends StatelessWidget {
  const SidebarMotion({super.key, required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      width: expanded ? AppSizes.sidebarWidth : AppSizes.sidebarCollapsedWidth,
      child: child,
    );
  }
}
