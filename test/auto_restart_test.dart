import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/crash/auto_restart.dart';
import 'package:exalted/core/crash/restart_policy.dart';

void main() {
  final now = DateTime.utc(2026, 11, 10, 12);
  late Directory tmp;
  late RestartHistoryStore store;
  var relaunches = 0;
  int? exitCode;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auto_restart_test_');
    store = RestartHistoryStore(() async => tmp);
    relaunches = 0;
    exitCode = null;
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  AutoRestarter make({
    int max = 3,
    bool enabled = true,
    bool relaunchOk = true,
  }) => AutoRestarter(
    policy: RestartPolicy(enabled: enabled, maxPerHour: max),
    store: store,
    relaunch: () async {
      relaunches++;
      return relaunchOk;
    },
    exitApp: (c) => exitCode = c,
    clock: () => now,
    exitDelay: Duration.zero,
  );

  test('restarts, saves the time and exits', () async {
    expect(await make().handleFatal(), isTrue);
    expect(relaunches, 1);
    expect(exitCode, 1);
    expect(await store.load(), [now]);
  });

  test('does nothing at the limit or when disabled', () async {
    await store.save([now.subtract(const Duration(minutes: 1))]);
    expect(await make(max: 1).handleFatal(), isFalse);
    expect(await make(enabled: false).handleFatal(), isFalse);
    expect(relaunches, 0);
    expect(exitCode, isNull);
  });

  test('does not exit when the new copy could not start', () async {
    expect(await make(relaunchOk: false).handleFatal(), isFalse);
    expect(relaunches, 1);
    expect(exitCode, isNull);
  });

  test('two errors at once cause one restart', () async {
    final r = make();
    final a = r.handleFatal();
    final b = r.handleFatal();
    expect(await a, isTrue);
    expect(await b, isFalse);
    expect(relaunches, 1);
  });
}
