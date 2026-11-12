import 'dart:convert';
import 'dart:io';

class RestartDecision {
  const RestartDecision({
    required this.restart,
    required this.history,
    required this.reason,
  });
  final bool restart;

  /// Restart times to save: the recent ones, plus now when restart is true.
  final List<DateTime> history;
  final String reason;
}

/// Decides whether the app may restart itself. A crash loop stops after
/// maxPerHour restarts inside the window. Times in the future (clock set back)
/// count as recent, so a clock change cannot cause a loop.
class RestartPolicy {
  const RestartPolicy({
    this.enabled = false,
    this.maxPerHour = 3,
    this.window = const Duration(hours: 1),
  });
  final bool enabled;
  final int maxPerHour;
  final Duration window;

  RestartDecision decide(List<DateTime> previous, DateTime now) {
    final recent = [
      for (final t in previous)
        if (now.difference(t) < window) t,
    ];
    if (!enabled) {
      return RestartDecision(
        restart: false,
        history: recent,
        reason: 'auto-restart is off',
      );
    }
    if (recent.length >= maxPerHour) {
      return RestartDecision(
        restart: false,
        history: recent,
        reason: 'restart limit reached ($maxPerHour per hour)',
      );
    }
    return RestartDecision(
      restart: true,
      history: [...recent, now],
      reason: 'restarting',
    );
  }
}

/// Keeps the restart times in restarts.json. Never throws.
class RestartHistoryStore {
  RestartHistoryStore(this._directory);
  static const String fileName = 'restarts.json';
  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final d = await _directory();
    return File('${d.path}${Platform.pathSeparator}$fileName');
  }

  Future<List<DateTime>> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return [];
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return [];
      return [
        for (final v in raw)
          if (v is String && DateTime.tryParse(v) != null) DateTime.parse(v),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<DateTime> times) async {
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode([for (final t in times) t.toIso8601String()]),
      );
    } catch (_) {}
  }
}

typedef ProcessStarter = Future<void> Function(
  String executable,
  List<String> args,
);

Future<void> _startDetached(String exe, List<String> args) async {
  await Process.start(exe, args, mode: ProcessStartMode.detached);
}

/// Starts a new copy of this app. It does not exit the current process; the
/// caller decides when to do that. Returns false if the start failed.
Future<bool> relaunchApp({ProcessStarter? starter}) async {
  try {
    await (starter ?? _startDetached)(Platform.resolvedExecutable, const []);
    return true;
  } catch (_) {
    return false;
  }
}
