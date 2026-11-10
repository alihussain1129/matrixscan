import 'dart:async';
import 'dart:io';

import 'restart_policy.dart';

/// Relaunches the app after a fatal error, if the policy allows it.
/// Only one restart attempt runs at a time. Never throws.
class AutoRestarter {
  AutoRestarter({
    required this.policy,
    required this.store,
    Future<bool> Function()? relaunch,
    void Function(int code)? exitApp,
    DateTime Function()? clock,
    this.exitDelay = const Duration(milliseconds: 500),
    void Function(String message)? log,
  }) : _relaunch = relaunch ?? relaunchApp,
       _exit = exitApp ?? exit,
       _clock = clock ?? DateTime.now,
       _log = log ?? ((_) {});

  final RestartPolicy policy;
  final RestartHistoryStore store;
  final Duration exitDelay;
  final Future<bool> Function() _relaunch;
  final void Function(int code) _exit;
  final DateTime Function() _clock;
  final void Function(String message) _log;
  bool _busy = false;

  /// Returns true when a new copy was started and the exit was requested.
  Future<bool> handleFatal() async {
    if (_busy) return false;
    _busy = true;
    var exiting = false;
    try {
      final decision = policy.decide(await store.load(), _clock());
      _log(decision.reason);
      if (!decision.restart) return false;
      await store.save(decision.history);
      if (!await _relaunch()) {
        _log('could not start a new copy');
        return false;
      }
      exiting = true;
      await Future<void>.delayed(exitDelay);
      _exit(1);
      return true;
    } catch (e) {
      _log('restart failed: $e');
      return false;
    } finally {
      if (!exiting) _busy = false;
    }
  }
}
