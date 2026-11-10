import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/storage/file_exists_cache.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('fec_test_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('remembers the answer until it expires', () {
    var now = DateTime.utc(2026, 11, 10, 12);
    final c = FileExistsCache(clock: () => now);
    final f = File('${tmp.path}${Platform.pathSeparator}a.txt')..writeAsStringSync('x');
    expect(c.check(f.path), isTrue);
    f.deleteSync();
    expect(c.check(f.path), isTrue);
    now = now.add(const Duration(seconds: 31));
    expect(c.check(f.path), isFalse);
  });

  test('a missing file is checked again after the time is up', () {
    var now = DateTime.utc(2026, 11, 10, 12);
    final c = FileExistsCache(clock: () => now);
    final path = '${tmp.path}${Platform.pathSeparator}b.txt';
    expect(c.check(path), isFalse);
    File(path).writeAsStringSync('x');
    expect(c.check(path), isFalse);
    now = now.add(const Duration(seconds: 31));
    expect(c.check(path), isTrue);
  });

  test('stays under the entry limit', () {
    var calls = 0;
    final c = FileExistsCache(maxEntries: 3, exists: (_) { calls++; return true; });
    for (var i = 0; i < 10; i++) {
      c.check('p$i');
    }
    expect(calls, 10);
    c.check('p9');
    expect(calls, 10);
  });
}
