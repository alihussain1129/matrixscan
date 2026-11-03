import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Turns the decoder's per-frame hits into detection events.
///
/// Every payload is tracked on its own, so two codes in view at the same time
/// do not restart each other. A payload starts a new event when it was not
/// seen for longer than the re-arm gap (for example a new product that carries
/// the same code).
class DetectionEventTracker {
  final Map<String, int> _seen = <String, int>{};

  /// Records a decode at [nowMs]. Returns true when it starts a new event.
  bool observe(String text, int nowMs, int rearmGapMs) {
    _seen.removeWhere((_, last) => nowMs - last >= rearmGapMs);
    final isNew = !_seen.containsKey(text);
    _seen[text] = nowMs;
    return isNew;
  }

  /// The next decode always counts as a new event.
  void reset() => _seen.clear();
}

/// How long a code must be out of view before the same payload counts as a new
/// event. Saved between runs.
class RearmGapNotifier extends Notifier<int> {
  static const String _key = 'exalted_rearm_gap_ms';
  static const int defaultMs = 1000;
  static const int minMs = 200;
  static const int maxMs = 5000;

  bool _changedByUser = false;

  @override
  int build() {
    unawaited(_restore());
    return defaultMs;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_key);
      if (saved != null && !_changedByUser) {
        state = saved.clamp(minMs, maxMs).toInt();
      }
    } catch (_) {}
  }

  void set(int ms) {
    _changedByUser = true;
    state = ms.clamp(minMs, maxMs).toInt();
    unawaited(_save(state));
  }

  Future<void> _save(int ms) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, ms);
    } catch (_) {}
  }
}

final rearmGapProvider = NotifierProvider<RearmGapNotifier, int>(
  RearmGapNotifier.new,
);
