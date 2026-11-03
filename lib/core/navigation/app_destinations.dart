import 'package:flutter/material.dart';

import '../router/app_router.dart';

@immutable
class AppDestination {
  const AppDestination({
    required this.index,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final int index;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// The one list of destinations. Order equals index.
const List<AppDestination> kDestinations = [
  AppDestination(
    index: kHomeTab,
    label: 'Inspect',
    icon: Icons.image_search_outlined,
    activeIcon: Icons.image_search,
  ),
  AppDestination(
    index: kScanTab,
    label: 'Decoder',
    icon: Icons.qr_code_scanner_outlined,
    activeIcon: Icons.qr_code_scanner,
  ),
  AppDestination(
    index: kOcrTab,
    label: 'OCR',
    icon: Icons.document_scanner_outlined,
    activeIcon: Icons.document_scanner,
  ),
  AppDestination(
    index: kHistoryTab,
    label: 'History',
    icon: Icons.history_outlined,
    activeIcon: Icons.history,
  ),
  AppDestination(
    index: kDevicesTab,
    label: 'Devices',
    icon: Icons.router_outlined,
    activeIcon: Icons.router,
  ),
  AppDestination(
    index: kSettingsTab,
    label: 'Settings',
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune,
  ),
];

/// Compact layouts show this many in the bottom bar; the rest go under More.
const int kBottomBarCount = 4;
