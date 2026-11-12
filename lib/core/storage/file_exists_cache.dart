import 'dart:io';

/// Remembers "does this file exist" answers for a short time, so list rows do
/// not hit the disk on every rebuild. Answers expire after [ttl].
class FileExistsCache {
  FileExistsCache({
    this.ttl = const Duration(seconds: 30),
    this.maxEntries = 500,
    DateTime Function()? clock,
    bool Function(String path)? exists,
  }) : _clock = clock ?? DateTime.now,
       _exists = exists ?? ((p) => File(p).existsSync());

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _clock;
  final bool Function(String path) _exists;
  final Map<String, (bool, DateTime)> _seen = {};

  bool check(String path) {
    final now = _clock();
    final hit = _seen[path];
    if (hit != null && now.difference(hit.$2) < ttl && !now.isBefore(hit.$2)) {
      return hit.$1;
    }
    final value = _exists(path);
    if (_seen.length >= maxEntries) _seen.clear();
    _seen[path] = (value, now);
    return value;
  }

  void clear() => _seen.clear();
}

final FileExistsCache _shared = FileExistsCache();

/// Same answer as File(path).existsSync(), but remembered for 30 seconds.
bool cachedFileExists(String path) => _shared.check(path);
