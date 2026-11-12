import 'package:flutter/material.dart';

/// Extra Exalted color tokens that Material's ColorScheme does not cover.
/// Centralized design system matching the Deep Professional Teal industrial vision.
@immutable
class ExaltedColors extends ThemeExtension<ExaltedColors> {
  const ExaltedColors({
    required this.primaryPressed,
    required this.primaryText,
    required this.surfaceRaised,
    required this.outline,
    required this.muted,
    required this.valid,
    this.sidebar = const Color(0xFF0E1622),
    this.canvas = const Color(0xFF070B14),
    this.warning = const Color(0xFFF59E0B),
    this.info = const Color(0xFF3B82F6),
    this.hover = const Color(0x14125352),
    this.aqua = const Color(0xFF2DD4BF),
    this.mint = const Color(0xFFD1FAE5),
    this.teal = const Color(0xFF125352),
  });

  final Color primaryPressed;
  final Color primaryText;
  final Color surfaceRaised;
  final Color outline;
  final Color muted;

  /// Success: decoded, verified, passed (Green).
  final Color valid;

  /// Navigation sidebar background.
  final Color sidebar;

  /// Image inspection canvas. Dark in both themes so images read true.
  final Color canvas;

  /// Warning / review (Amber).
  final Color warning;

  /// Informational (Blue).
  final Color info;

  /// Desktop hover wash.
  final Color hover;

  /// Supporting luminous aqua.
  final Color aqua;

  /// Supporting soft mint.
  final Color mint;

  /// Deep professional teal.
  final Color teal;

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
    Color? aqua,
    Color? mint,
    Color? teal,
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
      aqua: aqua ?? this.aqua,
      mint: mint ?? this.mint,
      teal: teal ?? this.teal,
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
      aqua: Color.lerp(aqua, other.aqua, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
    );
  }
}

/// Convenience extension: `context.exalted.valid` instead of Theme.of(context).extension<...>()!.
extension ExaltedColorsContext on BuildContext {
  ExaltedColors get exalted =>
      Theme.of(this).extension<ExaltedColors>() ?? AppColors.darkExtra;
}

/// Central design system color palette for Exalted Industrial Machine Vision.
class AppColors {
  AppColors._();

  // Primary: Deep professional teal
  static const Color tealPrimary = Color(0xFF125352);
  static const Color tealDark = Color(0xFF0D3E3D);
  static const Color tealLight = Color(0xFF1B7A78);

  // Supporting palette
  static const Color aqua = Color(0xFF2DD4BF);
  static const Color mint = Color(0xFFD1FAE5);
  static const Color mintDark = Color(0xFFA7F3D0);

  // Status tokens
  static const Color successGreen = Color(0xFF10B981);
  static const Color successGreenLight = Color(0xFF059669);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color warningAmberLight = Color(0xFFD97706);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color errorRedLight = Color(0xFFDC2626);
  static const Color infoBlue = Color(0xFF3B82F6);
  static const Color infoBlueLight = Color(0xFF2563EB);

  // Neutral Greys
  static const Color neutralWhite = Color(0xFFFFFFFF);
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate950 = Color(0xFF0B111A);

  // Surface tokens
  static const Color lightBg = slate50;
  static const Color darkBg = slate950;

  // Backward compatibility alias for legacy references
  static const Color red = errorRed;
  static const Color gray = slate500;
  static const Color cyan = aqua;
  static const Color cyanDeep = tealPrimary;

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: tealPrimary,
    onPrimary: neutralWhite,
    primaryContainer: Color(0xFFE0F2F1),
    onPrimaryContainer: tealDark,
    secondary: Color(0xFF334155),
    onSecondary: neutralWhite,
    error: errorRedLight,
    onError: neutralWhite,
    surface: neutralWhite,
    onSurface: slate900,
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: aqua,
    onPrimary: Color(0xFF04201F),
    primaryContainer: Color(0xFF0E3E3D),
    onPrimaryContainer: mint,
    secondary: slate400,
    onSecondary: slate950,
    error: Color(0xFFF87171),
    onError: Color(0xFF450A0A),
    surface: Color(0xFF111A27),
    onSurface: Color(0xFFF8FAFC),
  );

  static const ExaltedColors lightExtra = ExaltedColors(
    primaryPressed: tealDark,
    primaryText: tealPrimary,
    surfaceRaised: slate100,
    outline: slate200,
    muted: slate500,
    valid: successGreenLight,
    sidebar: Color(0xFFF1F5F9),
    canvas: Color(0xFF0B101C),
    warning: warningAmberLight,
    info: infoBlueLight,
    hover: Color(0x14125352),
    aqua: Color(0xFF0D9488),
    mint: mint,
    teal: tealPrimary,
  );

  static const ExaltedColors darkExtra = ExaltedColors(
    primaryPressed: Color(0xFF14B8A6),
    primaryText: aqua,
    surfaceRaised: Color(0xFF182436),
    outline: Color(0xFF1F2E45),
    muted: slate400,
    valid: Color(0xFF34D399),
    sidebar: Color(0xFF0E1622),
    canvas: Color(0xFF070B14),
    warning: Color(0xFFFBBF24),
    info: Color(0xFF60A5FA),
    hover: Color(0x1A2DD4BF),
    aqua: aqua,
    mint: mintDark,
    teal: tealPrimary,
  );
}
