import 'package:flutter/services.dart';

/// Plays a short native beep after a barcode has been accepted.
class ScanFeedback {
  ScanFeedback._();

  static const MethodChannel _channel =
      MethodChannel('com.exaltedcoding.exalted/scan_feedback');

  static Future<void> beep() async {
    try {
      await _channel.invokeMethod<bool>('beep');
    } on PlatformException {
      // Sound must never interfere with scanning.
    } on MissingPluginException {
      // Keep scanning functional if the native channel is unavailable.
    }
  }
}
