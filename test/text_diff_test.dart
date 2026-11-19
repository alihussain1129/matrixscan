import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/inspection/text_diff.dart';

void main() {
  test('identical strings have no differences', () {
    expect(diffStrings('ABC123', 'ABC123'), isEmpty);
    expect(diffStrings('', ''), isEmpty);
  });

  test('one substituted character', () {
    final d = diffStrings('ABC', 'ABD').single;
    expect(d.kind, DiffKind.substituted);
    expect(d.expectedIndex, 2);
    expect(d.expectedChar, 'C');
    expect(d.actualChar, 'D');
  });

  test('one missing character', () {
    final d = diffStrings('ABC', 'AC').single;
    expect(d.kind, DiffKind.missing);
    expect(d.expectedIndex, 1);
    expect(d.expectedChar, 'B');
  });

  test('one extra character', () {
    final d = diffStrings('AC', 'ABC').single;
    expect(d.kind, DiffKind.extra);
    expect(d.actualIndex, 1);
    expect(d.actualChar, 'B');
  });

  test('a missing and a substituted character together', () {
    final d = diffStrings('ABCD', 'AXD');
    expect(d.length, 2);
    expect(d.map((x) => x.kind).toSet(), {
      DiffKind.substituted,
      DiffKind.missing,
    });
  });

  test('empty actual means every character is missing', () {
    final d = diffStrings('AB', '');
    expect(d.length, 2);
    expect(d.every((x) => x.kind == DiffKind.missing), isTrue);
  });

  test('descriptions are readable', () {
    expect(
      describeDiffs(diffStrings('ABC', 'ABD')),
      'expected "C" but found "D" at position 3',
    );
  });
}
