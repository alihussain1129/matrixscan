import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ocr/models/ocr_record.dart';
import '../ocr/services/ocr_history_repository.dart';
import 'live_ocr_analyzer.dart';

/// Saves live OCR text to OCR History on every platform.
///
/// It listens to the live OCR text. When text appears it waits 3 seconds,
/// then saves it if it looks like real text and is not similar to the last
/// saved text. Nothing runs during widget build.
class OcrAutoSaver {
  OcrAutoSaver(this._ref, this._isMounted);

  final WidgetRef _ref;
  final bool Function() _isMounted;

  Timer? _timer;
  String _last = '';
  ValueNotifier<String>? _notifier;

  void start() {
    if (_notifier != null) return;
    final n = _ref.read(liveOcrAnalyzerProvider).text;
    _notifier = n;
    n.addListener(_onText);
  }

  void stop() {
    _notifier?.removeListener(_onText);
    _notifier = null;
    _timer?.cancel();
    _timer = null;
  }

  void _onText() {
    if (_timer != null) return;
    if ((_notifier?.value ?? '').isEmpty) return;
    _timer = Timer(const Duration(seconds: 3), _fire);
  }

  Future<void> _fire() async {
    _timer = null;
    if (!_isMounted()) return;
    final live = _ref.read(liveOcrAnalyzerProvider);
    final txt = live.text.value.trim();
    if (!worthSaving(txt)) return;
    if (similar(txt, _last)) return;
    _last = txt;
    try {
      await _ref
          .read(ocrHistoryRepositoryProvider)
          .addRecord(
            OcrRecord(
              id: 'ocr_${DateTime.now().microsecondsSinceEpoch}',
              imagePath: '',
              text: txt,
              rawText: txt,
              createdAt: DateTime.now(),
              language: 'eng',
              engine: Platform.isAndroid
                  ? 'Google ML Kit (live)'
                  : 'Tesseract (live)',
              processingDurationMs: live.lastMs.value,
            ),
          );
    } catch (e) {
      debugPrint('[EXALTED][OCR_AUTOSAVE] save failed: $e');
    }
  }

  static bool worthSaving(String t) {
    if (t.length < 12) return false;
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words < 3) return false;
    final good = RegExp(r'[A-Za-z0-9\s.,:;()/&+\-]').allMatches(t).length;
    return good / t.length > 0.85;
  }

  static bool similar(String a, String b) {
    if (b.isEmpty) return false;
    Set<String> w(String x) => x
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((e) => e.length > 1)
        .toSet();
    final sa = w(a), sb = w(b);
    if (sa.isEmpty || sb.isEmpty) return false;
    final inter = sa.intersection(sb).length;
    final union = sa.union(sb).length;
    return inter / union >= 0.5;
  }
}
