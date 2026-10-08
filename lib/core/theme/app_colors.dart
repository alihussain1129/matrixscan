import 'package:flutter/material.dart';

/// Extra Exalted color tokens that Material's ColorScheme does not cover.
@immutable
class ExaltedColors extends ThemeExtension<ExaltedColors> {
  const ExaltedColors({
    required this.primaryPressed,
    required this.primaryText,
    required this.surfaceRaised,
    required this.outline,
    required this.muted,
    required this.valid,
  });

  final Color primaryPressed;
  final Color primaryText;
  final Color surfaceRaised;
  final Color outline;
  final Color muted;
  final Color valid;

  @override
  ExaltedColors copyWith({
    Color? primaryPressed,
    Color? primaryText,
    Color? surfaceRaised,
    Color? outline,
    Color? muted,
    Color? valid,
  }) {
    return ExaltedColors(
      primaryPressed: primaryPressed ?? this.primaryPressed,
      primaryText: primaryText ?? this.primaryText,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      outline: outline ?? this.outline,
      muted: muted ?? this.muted,
      valid: valid ?? this.valid,
    );
  }

  @override
  ExaltedColors lerp(ThemeExtension<ExaltedColors>? other, double t) {
    if (other is! ExaltedColors) return this;
    return ExaltedColors(
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      valid: Color.lerp(valid, other.valid, t)!,
    );
  }
}

/// All Exalted colors. Brand red is sampled from the official logo.
class AppColors {
  AppColors._();

  static const Color red = Color(0xFFEB1C24);
  static const Color gray = Color(0xFF6D6E70);

  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color darkBg = Color(0xFF0E0E10);

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: red,
    onPrimary: Colors.white,
    secondary: gray,
    onSecondary: Colors.white,
    error: Color(0xFFB5121B),
    onError: Colors.white,
    surface: Color(0xFFF5F5F6),
    onSurface: Color(0xFF1A1A1C),
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: red,
    onPrimary: Colors.white,
    secondary: Color(0xFFA0A2A8),
    onSecondary: Colors.black,
    error: Color(0xFFFF6B6B),
    onError: Colors.black,
    surface: Color(0xFF18181B),
    onSurface: Color(0xFFF2F2F3),
  );

  static const ExaltedColors lightExtra = ExaltedColors(
    primaryPressed: Color(0xFFB8141B),
    primaryText: Color(0xFFC8161D),
    surfaceRaised: Color(0xFFEDEDEF),
    outline: Color(0xFFDADADD),
    muted: Color(0xFF6D6E70),
    valid: Color(0xFF1E7B3C),
  );

  static const ExaltedColors darkExtra = ExaltedColors(
    primaryPressed: Color(0xFFC8161D),
    primaryText: Color(0xFFFF5A60),
    surfaceRaised: Color(0xFF222226),
    outline: Color(0xFF34343A),
    muted: Color(0xFFA0A2A8),
    valid: Color(0xFF4CC07A),
  );
}
