import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays a short native beep after a barcode has been accepted.
class ScanFeedback {
  ScanFeedback._();

  static const MethodChannel _channel =
      MethodChannel('com.exaltedcoding.exalted/scan_feedback');

  static Future<void> beep() async {
    try {
      await _channel.invokeMethod<bool>('beep');
    } on PlatformException catch (e) {
      // Sound must never interfere with scanning, but the reason is logged.
      debugPrint('[EXALTED][BEEP] failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      debugPrint('[EXALTED][BEEP] native channel not registered');
    }
  }
}