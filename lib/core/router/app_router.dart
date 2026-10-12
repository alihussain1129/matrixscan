import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-nav tab positions. Use these instead of bare numbers.
const int kHomeTab = 0;
const int kScanTab = 1;
const int kHistoryTab = 2;
const int kSettingsTab = 3;

/// Which bottom-nav tab is selected.
class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => kScanTab;

  void set(int index) => state = index;
}

final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(
  NavIndexNotifier.new,
);
