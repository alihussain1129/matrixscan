import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/gs1/gs1_parser.dart';

void main() {
  final now = DateTime(2026, 11, 17);

  test('50 years ahead is the future', () {
    expect(parseGs1Date('760101', now: now)!.year, 2076);
  });

  test('51 years ahead is read as 49 years back', () {
    expect(parseGs1Date('770101', now: now)!.year, 1977);
  });

  test('ordinary expiry dates', () {
    expect(parseGs1Date('281231', now: now)!.year, 2028);
    expect(parseGs1Date('250630', now: now)!.year, 2025);
  });

  test('day 00 means end of month', () {
    final d = parseGs1Date('280200', now: now)!;
    expect(d.dayUnspecified, isTrue);
    expect(d.date, DateTime(2028, 2, 29));
  });

  test('invalid dates are rejected', () {
    expect(parseGs1Date('281301', now: now), isNull);
    expect(parseGs1Date('280230', now: now), isNull);
    expect(parseGs1Date('28123', now: now), isNull);
  });
}
