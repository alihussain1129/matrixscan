import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/crash/crash_log.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('crash_log_test_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('records an entry with time, source, error and stack', () async {
    final log = CrashLog(
      () async => tmp,
      clock: () => DateTime.utc(2026, 11, 10, 12),
    );
    await log.record('boom', StackTrace.fromString('#0 a\n#1 b'), source: 'x');
    final text = await log.read();
    expect(text, contains('2026-11-10T12:00:00.000Z'));
    expect(text, contains('x'));
    expect(text, contains('boom'));
    expect(text, contains('#1 b'));
  });

  test('keeps the file under the cap and keeps the newest entry', () async {
    final log = CrashLog(() async => tmp, maxBytes: 600);
    for (var i = 0; i < 20; i++) {
      await log.record('entry $i', null);
    }
    final text = await log.read();
    expect(text.length, lessThanOrEqualTo(600));
    expect(text, contains('entry 19'));
    expect(text, isNot(contains('entry 0\n')));
    expect(text.startsWith('['), isTrue);
  });

  test('never throws when the folder is not available', () async {
    final log = CrashLog(() async => throw StateError('no folder'));
    await log.record('boom', null);
    expect(await log.read(), '');
  });
}
