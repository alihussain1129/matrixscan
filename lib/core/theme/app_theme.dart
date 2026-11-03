import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Builds the light and dark Exalted themes.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(
    scheme: AppColors.lightScheme,
    colors: AppColors.lightExtra,
    background: AppColors.lightBg,
  );

  static ThemeData dark() => _build(
    scheme: AppColors.darkScheme,
    colors: AppColors.darkExtra,
    background: AppColors.darkBg,
  );

  static ThemeData _build({
    required ColorScheme scheme,
    required ExaltedColors colors,
    required Color background,
  }) {
    final text = AppTypography.textTheme(scheme.onSurface, colors.muted);
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: text,
      dividerColor: colors.outline,
      dividerTheme: DividerThemeData(
        color: colors.outline,
        thickness: 1,
        space: 1,
      ),
      focusColor: scheme.primary.withValues(alpha: 0.35),
      hoverColor: colors.hover,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: colors.outline),
        ),
        textStyle: TextStyle(color: scheme.onSurface, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(colors.outline),
        radius: const Radius.circular(AppRadius.pill),
        thickness: const WidgetStatePropertyAll(6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: colors.outline,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.surfaceRaised,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        actionTextColor: scheme.primary,
      ),
      extensions: [colors],
    );
  }
}
