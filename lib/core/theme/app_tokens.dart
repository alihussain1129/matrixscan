import 'package:flutter/material.dart';

/// Sizes shared by every platform. Use these instead of literals.
class AppSizes {
  AppSizes._();

  // Icons.
  static const double iconXs = 14;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;

  // Controls.
  static const double buttonCompact = 32;
  static const double buttonRegular = 40;
  static const double buttonLarge = 48;
  static const double inputHeight = 44;
  static const double minTouchTarget = 48;

  // Shell.
  static const double toolbarHeight = 56;
  static const double sidebarWidth = 240;
  static const double sidebarCollapsedWidth = 72;
  static const double railWidth = 72;
  static const double infoPanelWidth = 360;
  static const double maxContentWidth = 1600;
}

/// Layout classes chosen from the real available width, never from the OS.
enum ExaltedLayout {
  /// Phones and very narrow windows: bottom navigation, stacked content.
  compact,

  /// Tablets and narrow windows: navigation rail, one or two panels.
  medium,

  /// Desktop windows: full sidebar plus a right information panel.
  expanded,
}

class AppBreakpoints {
  AppBreakpoints._();

  static const double mediumMin = 720;
  static const double expandedMin = 1100;

  static ExaltedLayout of(double width) {
    if (width >= expandedMin) return ExaltedLayout.expanded;
    if (width >= mediumMin) return ExaltedLayout.medium;
    return ExaltedLayout.compact;
  }
}

extension ExaltedLayoutContext on BuildContext {
  ExaltedLayout get layout => AppBreakpoints.of(MediaQuery.sizeOf(this).width);
}

/// Animation timings. Kept short: motion supports the workflow.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;
}
