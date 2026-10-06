import 'package:flutter/material.dart';

/// Shadows. In dark mode cards use an outline instead, because shadows
/// do not show on dark backgrounds.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> button = [
    BoxShadow(
      color: Color(0x40B8141B),
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];
}