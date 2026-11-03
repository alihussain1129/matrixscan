import 'package:exalted/core/navigation/app_destinations.dart';
import 'package:exalted/core/router/app_router.dart';
import 'package:exalted/core/theme/app_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layout is chosen from width only', () {
    expect(AppBreakpoints.of(320), ExaltedLayout.compact);
    expect(AppBreakpoints.of(719), ExaltedLayout.compact);
    expect(AppBreakpoints.of(720), ExaltedLayout.medium);
    expect(AppBreakpoints.of(1099), ExaltedLayout.medium);
    expect(AppBreakpoints.of(1100), ExaltedLayout.expanded);
    expect(AppBreakpoints.of(2560), ExaltedLayout.expanded);
  });

  test('one destination list, same names and order everywhere', () {
    expect(kDestinations.map((d) => d.label).toList(), [
      'Inspect',
      'Decoder',
      'OCR',
      'History',
      'Devices',
      'Settings',
    ]);
    for (var i = 0; i < kDestinations.length; i++) {
      expect(kDestinations[i].index, i);
    }
  });

  test('tab constants match the destinations', () {
    expect(kHomeTab, 0);
    expect(kScanTab, 1);
    expect(kOcrTab, 2);
    expect(kHistoryTab, 3);
    expect(kDevicesTab, 4);
    expect(kSettingsTab, 5);
    expect(kBottomBarCount, 4);
  });
}
