import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/config_controller.dart';

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
  static const int defaultMs = 1000;
  static const int minMs = 200;
  static const int maxMs = 5000;

  @override
  int build() => ref
      .read(configControllerProvider)
      .decoder
      .rearmGapMs
      .clamp(minMs, maxMs)
      .toInt();

  void set(int ms) {
    state = ms.clamp(minMs, maxMs).toInt();
    unawaited(_save(state));
  }

  Future<void> _save(int ms) async {
    try {
      await ref.read(configControllerProvider.notifier).patch({
        'decoder': {'rearmGapMs': ms},
      });
    } catch (_) {}
  }
}

final rearmGapProvider = NotifierProvider<RearmGapNotifier, int>(
  RearmGapNotifier.new,
);
