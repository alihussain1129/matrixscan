import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// A read-only view of the existing theme (ExaltedColors + ColorScheme).
/// There is no second palette. Change colors in app_colors.dart only.
@immutable
class ExaltedTokens {
  const ExaltedTokens({
    required this.brand,
    required this.accent,
    required this.mint,
    required this.surface,
    required this.surfaceRaised,
    required this.outline,
    required this.textPrimary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color brand;
  final Color accent;
  final Color mint;
  final Color surface;
  final Color surfaceRaised;
  final Color outline;
  final Color textPrimary;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;

  factory ExaltedTokens.fromTheme(ThemeData theme) {
    final c =
        theme.extension<ExaltedColors>() ??
        (theme.brightness == Brightness.dark
            ? AppColors.darkExtra
            : AppColors.lightExtra);
    final s = theme.colorScheme;
    return ExaltedTokens(
      brand: c.teal,
      accent: c.aqua,
      mint: c.mint,
      surface: s.surface,
      surfaceRaised: c.surfaceRaised,
      outline: c.outline,
      textPrimary: s.onSurface,
      textMuted: c.muted,
      success: c.valid,
      warning: c.warning,
      danger: s.error,
    );
  }

  static ExaltedTokens of(BuildContext context) =>
      ExaltedTokens.fromTheme(Theme.of(context));
}

class ExaltedSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class ExaltedRadius {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;
}

class ExaltedShadow {
  static List<BoxShadow> soft(Brightness b) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.35 : 0.06),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
}
