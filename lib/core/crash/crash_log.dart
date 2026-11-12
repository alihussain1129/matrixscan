import 'dart:async';
import 'dart:io';

/// Appends uncaught errors to crash.log. Never throws. The file is capped, and
/// the oldest entries are dropped first.
class CrashLog {
  CrashLog(
    this._directory, {
    this.maxBytes = 200 * 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const String fileName = 'crash.log';
  static const int maxStackLines = 40;

  final Future<Directory> Function() _directory;
  final int maxBytes;
  final DateTime Function() _clock;
  Future<void> _last = Future<void>.value();

  Future<File> _file() async {
    final d = await _directory();
    return File('${d.path}${Platform.pathSeparator}$fileName');
  }

  /// Writes one entry. Entries are written one after another.
  Future<void> record(
    Object error,
    StackTrace? stack, {
    String source = 'app',
  }) {
    _last = _last.then((_) => _write(error, stack, source)).catchError((_) {});
    return _last;
  }

  Future<void> _write(Object error, StackTrace? stack, String source) async {
    try {
      final f = await _file();
      final lines = (stack?.toString() ?? '').split('\n');
      final trace = lines.take(maxStackLines).join('\n');
      final entry =
          '[${_clock().toIso8601String()}] $source\n$error\n$trace\n\n';
      final old = f.existsSync() ? await f.readAsString() : '';
      var text = old + entry;
      if (text.length > maxBytes) {
        text = text.substring(text.length - maxBytes);
        final cut = text.indexOf('\n[');
        if (cut >= 0) text = text.substring(cut + 1);
      }
      await f.writeAsString(text);
    } catch (_) {}
  }

  Future<String> read() async {
    try {
      final f = await _file();
      return f.existsSync() ? await f.readAsString() : '';
    } catch (_) {
      return '';
    }
  }
}
