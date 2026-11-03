import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation destinations, identical on every platform and layout.
/// Use these instead of bare numbers.
const int kHomeTab = 0; // Inspect
const int kScanTab = 1; // Decoder
const int kOcrTab = 2;
const int kHistoryTab = 3;
const int kDevicesTab = 4;
const int kSettingsTab = 5;

/// Which destination is selected. The scanner starts and stops its camera
/// from this value, so it is the single source of truth for navigation.
class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => kScanTab;

  void set(int index) => state = index;
}

final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(
  NavIndexNotifier.new,
);
