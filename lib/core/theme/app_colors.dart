import 'package:flutter/material.dart';

/// Extra Exalted color tokens that Material's ColorScheme does not cover.
/// New fields have defaults so older call sites keep compiling.
@immutable
class ExaltedColors extends ThemeExtension<ExaltedColors> {
  const ExaltedColors({
    required this.primaryPressed,
    required this.primaryText,
    required this.surfaceRaised,
    required this.outline,
    required this.muted,
    required this.valid,
    this.sidebar = const Color(0xFF0C1322),
    this.canvas = const Color(0xFF070B14),
    this.warning = const Color(0xFFFFB020),
    this.info = const Color(0xFF2BD4F5),
    this.hover = const Color(0x142BD4F5),
  });

  final Color primaryPressed;
  final Color primaryText;
  final Color surfaceRaised;
  final Color outline;
  final Color muted;

  /// Success: decoded, verified, passed.
  final Color valid;

  /// Navigation sidebar background.
  final Color sidebar;

  /// Image inspection canvas. Dark in both themes so images read true.
  final Color canvas;

  /// Warning / review.
  final Color warning;

  /// Processing / informational (same family as the primary accent).
  final Color info;

  /// Desktop hover wash.
  final Color hover;

  @override
  ExaltedColors copyWith({
    Color? primaryPressed,
    Color? primaryText,
    Color? surfaceRaised,
    Color? outline,
    Color? muted,
    Color? valid,
    Color? sidebar,
    Color? canvas,
    Color? warning,
    Color? info,
    Color? hover,
  }) {
    return ExaltedColors(
      primaryPressed: primaryPressed ?? this.primaryPressed,
      primaryText: primaryText ?? this.primaryText,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      outline: outline ?? this.outline,
      muted: muted ?? this.muted,
      valid: valid ?? this.valid,
      sidebar: sidebar ?? this.sidebar,
      canvas: canvas ?? this.canvas,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      hover: hover ?? this.hover,
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
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
    );
  }
}

/// `context.exalted.valid` instead of Theme.of(context).extension<...>()!.
extension ExaltedColorsContext on BuildContext {
  ExaltedColors get exalted => Theme.of(this).extension<ExaltedColors>()!;
}

/// All Exalted colors.
///
/// [red] and [gray] are the official logo colors and are used for branding
/// only. The interactive accent is cyan.
class AppColors {
  AppColors._();

  // Brand (logo only).
  static const Color red = Color(0xFFEB1C24);
  static const Color gray = Color(0xFF6D6E70);

  // Interactive accent.
  static const Color cyan = Color(0xFF2BD4F5);
  static const Color cyanDeep = Color(0xFF0A7EA4);

  static const Color lightBg = Color(0xFFF3F6FA);
  static const Color darkBg = Color(0xFF0A0F1A);

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: cyanDeep,
    onPrimary: Colors.white,
    secondary: Color(0xFF5B6880),
    onSecondary: Colors.white,
    error: Color(0xFFC42B3A),
    onError: Colors.white,
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF0F1A2E),
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: cyan,
    onPrimary: Color(0xFF031219),
    secondary: Color(0xFF9AA7BF),
    onSecondary: Color(0xFF0A0F1A),
    error: Color(0xFFFF6B77),
    onError: Color(0xFF1A0508),
    surface: Color(0xFF0F1626),
    onSurface: Color(0xFFE8EDF6),
  );

  static const ExaltedColors lightExtra = ExaltedColors(
    primaryPressed: Color(0xFF086A8A),
    primaryText: Color(0xFF086A8A),
    surfaceRaised: Color(0xFFEBF0F7),
    outline: Color(0xFFD3DBE8),
    muted: Color(0xFF5B6880),
    valid: Color(0xFF15803D),
    sidebar: Color(0xFFE9EEF6),
    canvas: Color(0xFF0B101C),
    warning: Color(0xFFB45309),
    info: Color(0xFF0A7EA4),
    hover: Color(0x140A7EA4),
  );

  static const ExaltedColors darkExtra = ExaltedColors(
    primaryPressed: Color(0xFF1FB3D1),
    primaryText: Color(0xFF5BDDF7),
    surfaceRaised: Color(0xFF151E32),
    outline: Color(0xFF243049),
    muted: Color(0xFF8A97B0),
    valid: Color(0xFF3DDC97),
    sidebar: Color(0xFF0C1322),
    canvas: Color(0xFF070B14),
    warning: Color(0xFFFFB020),
    info: Color(0xFF2BD4F5),
    hover: Color(0x142BD4F5),
  );
}
