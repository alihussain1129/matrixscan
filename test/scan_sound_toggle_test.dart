import 'package:exalted/features/scanner/scan_feedback.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.exaltedcoding.exalted/scan_feedback');

  test('beep reaches the channel only while sounds are on', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          return true;
        });
    addTearDown(() {
      ScanFeedback.setEnabled(true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await ScanFeedback.beep();
    expect(calls, 1);
    ScanFeedback.setEnabled(false);
    await ScanFeedback.beep();
    expect(calls, 1);
    ScanFeedback.setEnabled(true);
    await ScanFeedback.beep();
    expect(calls, 2);
  });
}
