import 'package:flutter/material.dart';

import 'app_colors.dart';
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
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: AppTypography.textTheme(scheme.onSurface, colors.muted),
      dividerColor: colors.outline,
      extensions: [colors],
    );
  }
}
