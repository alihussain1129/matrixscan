import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation destinations, identical on every platform and layout.
/// Use these instead of bare numbers.
const int kHomeTab = 0; // Dashboard
const int kScanTab = 1; // Scanner
const int kOcrTab = 2; // Decode & OCR
const int kHistoryTab = 3; // History
const int kDevicesTab = 4; // Devices & Connections
const int kLinkTab = 5; // Synchronization
const int kVerificationTab = 6; // Verification
const int kDiagnosticsTab = 7; // Diagnostics
const int kSettingsTab = 8; // Settings
const int kInspectionTab = 9; // Inspection records

/// Which destination is selected. The active screen should feel like a
/// professional product workflow: dashboard first, then task-focused areas.
class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => kHomeTab;

  void set(int index) => state = index;
}

final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(
  NavIndexNotifier.new,
);
