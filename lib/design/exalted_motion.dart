import 'package:flutter/material.dart';

/// Shared durations and curves. Use [d] so reduced-motion users get
/// instant changes.
class ExaltedMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;
  static const Curve curveIn = Curves.easeInCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Returns [Duration.zero] when the user asked for reduced motion.
  static Duration d(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
}
