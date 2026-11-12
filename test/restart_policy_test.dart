import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/crash/restart_policy.dart';

void main() {
  final now = DateTime.utc(2026, 11, 10, 12);

  test('does nothing when auto-restart is off', () {
    final d = const RestartPolicy().decide([], now);
    expect(d.restart, isFalse);
    expect(d.history, isEmpty);
  });

  test('restarts and records the time when under the limit', () {
    final d = const RestartPolicy(
      enabled: true,
      maxPerHour: 3,
    ).decide([now.subtract(const Duration(minutes: 5))], now);
    expect(d.restart, isTrue);
    expect(d.history.length, 2);
    expect(d.history.last, now);
  });

  test('stops a crash loop at the limit', () {
    final times = [
      for (var i = 1; i <= 3; i++) now.subtract(Duration(minutes: i)),
    ];
    final d = RestartPolicy(enabled: true, maxPerHour: 3).decide(times, now);
    expect(d.restart, isFalse);
    expect(d.reason, contains('limit'));
    expect(d.history.length, 3);
  });

  test('old restarts no longer count', () {
    final times = [
      for (var i = 1; i <= 3; i++) now.subtract(Duration(hours: 2, minutes: i)),
    ];
    final d = RestartPolicy(enabled: true, maxPerHour: 3).decide(times, now);
    expect(d.restart, isTrue);
    expect(d.history, [now]);
  });

  test('times in the future count as recent', () {
    final times = [for (var i = 1; i <= 3; i++) now.add(Duration(days: i))];
    final d = RestartPolicy(enabled: true, maxPerHour: 3).decide(times, now);
    expect(d.restart, isFalse);
  });

  test(
    'history survives a save and load, and bad files give an empty list',
    () async {
      final tmp = Directory.systemTemp.createTempSync('restart_hist_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final store = RestartHistoryStore(() async => tmp);
      expect(await store.load(), isEmpty);
      await store.save([now]);
      expect(await store.load(), [now]);
      File('${tmp.path}${Platform.pathSeparator}restarts.json')
          .writeAsStringSync('not json');
      expect(await store.load(), isEmpty);
    },
  );

  test('relaunchApp reports success and failure without throwing', () async {
    String? exe;
    expect(await relaunchApp(starter: (e, a) async => exe = e), isTrue);
    expect(exe, isNotNull);
    expect(
      await relaunchApp(starter: (e, a) async => throw StateError('x')),
      isFalse,
    );
  });
}
