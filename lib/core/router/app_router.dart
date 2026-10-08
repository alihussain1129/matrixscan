import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which bottom-nav tab is selected: 0 = Scan, 1 = History, 2 = Settings.
class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(
  NavIndexNotifier.new,
);
