import 'dart:math' as math;

enum DiffKind { substituted, missing, extra }

/// One character-level difference between an expected and an actual string.
class FieldDiff {
  const FieldDiff(
    this.kind, {
    required this.expectedIndex,
    required this.actualIndex,
    this.expectedChar,
    this.actualChar,
  });

  final DiffKind kind;

  /// Position in the expected string (for an extra character: where it sits).
  final int expectedIndex;

  /// Position in the actual string (for a missing character: where it should be).
  final int actualIndex;
  final String? expectedChar;
  final String? actualChar;
}

/// Minimal edit script (Levenshtein) from [expected] to [actual].
/// Empty list means the strings are identical.
List<FieldDiff> diffStrings(String expected, String actual) {
  final n = expected.length;
  final m = actual.length;
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = expected[i - 1] == actual[j - 1] ? 0 : 1;
      d[i][j] = math.min(
        d[i - 1][j - 1] + cost,
        math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
      );
    }
  }
  final out = <FieldDiff>[];
  var i = n;
  var j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0) {
      final same = expected[i - 1] == actual[j - 1];
      if (d[i][j] == d[i - 1][j - 1] + (same ? 0 : 1)) {
        if (!same) {
          out.add(
            FieldDiff(
              DiffKind.substituted,
              expectedIndex: i - 1,
              actualIndex: j - 1,
              expectedChar: expected[i - 1],
              actualChar: actual[j - 1],
            ),
          );
        }
        i--;
        j--;
        continue;
      }
    }
    if (i > 0 && d[i][j] == d[i - 1][j] + 1) {
      out.add(
        FieldDiff(
          DiffKind.missing,
          expectedIndex: i - 1,
          actualIndex: j,
          expectedChar: expected[i - 1],
        ),
      );
      i--;
      continue;
    }
    out.add(
      FieldDiff(
        DiffKind.extra,
        expectedIndex: i,
        actualIndex: j - 1,
        actualChar: actual[j - 1],
      ),
    );
    j--;
  }
  return out.reversed.toList();
}

String describeDiff(FieldDiff d) => switch (d.kind) {
  DiffKind.substituted =>
    'expected "${d.expectedChar}" but found "${d.actualChar}" at position ${d.expectedIndex + 1}',
  DiffKind.missing =>
    'missing "${d.expectedChar}" at position ${d.expectedIndex + 1}',
  DiffKind.extra => 'extra "${d.actualChar}" at position ${d.actualIndex + 1}',
};

String describeDiffs(List<FieldDiff> diffs) => diffs.map(describeDiff).join('; ');
