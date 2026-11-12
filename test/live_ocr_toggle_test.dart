import 'package:exalted/features/scanner/live_ocr_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('turning live reading off clears the text and is announced', () {
    final a = LiveOcrAnalyzer();
    addTearDown(a.dispose);
    final seen = <bool>[];
    a.enabledListenable.addListener(() => seen.add(a.enabled));
    expect(a.enabled, isTrue);
    a.text.value = 'LOT 123';
    a.setEnabled(false);
    expect(a.enabled, isFalse);
    expect(a.text.value, isEmpty);
    a.setEnabled(true);
    expect(seen, [false, true]);
  });
}
