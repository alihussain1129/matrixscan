import 'dart:convert';
import 'dart:isolate';

/// Decodes JSON. Big texts are decoded in a background isolate so the screen
/// does not freeze; small ones are decoded in place because starting an
/// isolate costs more than it saves. Throws like jsonDecode on bad input.
Future<Object?> decodeJsonOffThread(
  String text, {
  int thresholdChars = 64 * 1024,
}) {
  if (text.length < thresholdChars) {
    try {
      return Future<Object?>.value(jsonDecode(text));
    } catch (e, s) {
      return Future<Object?>.error(e, s);
    }
  }
  return Isolate.run<Object?>(() => jsonDecode(text));
}
