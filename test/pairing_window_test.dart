import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/core/pairing_window.dart';

void main() {
  late DateTime now;
  late PairingWindow w;

  setUp(() {
    now = DateTime(2026, 11, 5, 12);
    w = PairingWindow(window: const Duration(seconds: 5), clock: () => now);
  });

  test('pairs the missing half when it arrives within the window', () {
    w.open('r1', missing: PairSide.image);
    now = now.add(const Duration(seconds: 2));
    expect(w.claim(PairSide.image), 'r1');
  });

  test('accepts an arrival exactly at the window limit', () {
    w.open('r1', missing: PairSide.barcode);
    now = now.add(const Duration(seconds: 5));
    expect(w.claim(PairSide.barcode), 'r1');
  });

  test('rejects a stale record', () {
    w.open('r1', missing: PairSide.image);
    now = now.add(const Duration(seconds: 6));
    expect(w.claim(PairSide.image), isNull);
  });

  test('a record can be claimed only once', () {
    w.open('r1', missing: PairSide.image);
    expect(w.claim(PairSide.image), 'r1');
    expect(w.claim(PairSide.image), isNull);
  });

  test('does not pair the same side with itself', () {
    w.open('r1', missing: PairSide.image);
    expect(w.claim(PairSide.barcode), isNull);
    expect(w.claim(PairSide.image), 'r1');
  });

  test('a newer waiting record replaces the older one', () {
    w.open('r1', missing: PairSide.image);
    now = now.add(const Duration(seconds: 1));
    w.open('r2', missing: PairSide.image);
    expect(w.claim(PairSide.image), 'r2');
    expect(w.claim(PairSide.image), isNull);
  });

  test('clear drops the waiting record', () {
    w.open('r1', missing: PairSide.barcode);
    w.clear();
    expect(w.claim(PairSide.barcode), isNull);
  });

  test('returns null when nothing is waiting', () {
    expect(w.claim(PairSide.image), isNull);
  });
}
