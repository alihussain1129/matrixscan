import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Barlow Condensed for headings, Roboto for body, JetBrains Mono for data.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color text, Color muted) {
    return TextTheme(
      displaySmall: GoogleFonts.barlowCondensed(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleLarge: GoogleFonts.barlowCondensed(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleMedium: GoogleFonts.barlowCondensed(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: GoogleFonts.roboto(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: text,
      ),
      bodyMedium: GoogleFonts.roboto(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: text,
      ),
      bodySmall: GoogleFonts.roboto(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: muted,
      ),
      labelLarge: GoogleFonts.barlowCondensed(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: text,
      ),
      labelSmall: GoogleFonts.roboto(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.2,
        color: muted,
      ),
    );
  }

  /// Monospace style for decoded data, hex and analysis values.
  static TextStyle mono({
    double size = 14,
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      color: color,
      fontWeight: weight,
    );
  }
}