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
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard,
  ),
  AppDestination(
    index: kScanTab,
    label: 'Scanner',
    icon: Icons.qr_code_scanner_outlined,
    activeIcon: Icons.qr_code_scanner,
  ),
  AppDestination(
    index: kOcrTab,
    label: 'Decode & OCR',
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
    index: kLinkTab,
    label: 'Synchronization',
    icon: Icons.sync_alt_outlined,
    activeIcon: Icons.sync_alt,
  ),
  AppDestination(
    index: kVerificationTab,
    label: 'Verification',
    icon: Icons.fact_check_outlined,
    activeIcon: Icons.fact_check,
  ),
  AppDestination(
    index: kDiagnosticsTab,
    label: 'Diagnostics',
    icon: Icons.monitor_heart_outlined,
    activeIcon: Icons.monitor_heart,
  ),
  AppDestination(
    index: kSettingsTab,
    label: 'Settings',
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune,
  ),
  AppDestination(
    index: kInspectionTab,
    label: 'Inspection',
    icon: Icons.fact_check_outlined,
    activeIcon: Icons.fact_check,
  ),
];

/// Compact layouts show this many in the bottom bar; the rest go under More.
const int kBottomBarCount = 4;

/// Desktop sidebar sections. The menu mirrors a clean industrial product flow and
/// keeps the interface organized by purpose instead of implementation detail.
const List<({String title, List<int> indexes})> kDestinationGroups = [
  (
    title: 'WORKSPACE',
    indexes: [kHomeTab, kScanTab, kOcrTab, kInspectionTab, kVerificationTab],
  ),
  (title: 'OPERATIONS', indexes: [kHistoryTab, kDevicesTab, kLinkTab]),
  (title: 'SYSTEM', indexes: [kDiagnosticsTab, kSettingsTab]),
];
