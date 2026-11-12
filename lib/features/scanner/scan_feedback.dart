import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays a short native beep after a barcode has been accepted.
class ScanFeedback {
  ScanFeedback._();

  static const MethodChannel _channel = MethodChannel(
    'com.exaltedcoding.exalted/scan_feedback',
  );

  static final ValueNotifier<bool> _enabled = ValueNotifier<bool>(true);
  static bool _warned = false;

  /// Whether scan sounds are on. Changes are announced to listeners.
  static ValueListenable<bool> get enabledListenable => _enabled;
  static bool get enabled => _enabled.value;
  static void setEnabled(bool value) => _enabled.value = value;

  static Future<void> beep() async {
    if (!_enabled.value) return;
    try {
      await _channel.invokeMethod<bool>('beep');
    } on PlatformException catch (e) {
      // Sound must never interfere with scanning, but the reason is logged.
      debugPrint('[EXALTED][BEEP] failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      if (!_warned) {
        _warned = true;
        debugPrint('[EXALTED][BEEP] native channel not registered');
      }
    }
  }
}
