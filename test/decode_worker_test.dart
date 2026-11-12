import 'package:exalted/ffi/decode_worker.dart';
import 'package:exalted/ffi/exalted_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

/// True when the native core can be loaded in this environment.
bool _nativeCoreLoadable() {
  try {
    ExaltedBindings.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  test('worker starts, answers and shuts down', () async {
    final nativeLoadable = _nativeCoreLoadable();
    final worker = DecodeWorker();
    final reply = await worker.decode(
      address: 0,
      length: 0,
      width: 0,
      height: 0,
      rowStride: 0,
      formatsMask: 0,
      tryHarder: false,
    );
    worker.dispose();

    expect(reply, isNotNull);
    final status = reply![0];
    expect(reply[1], isNull, reason: 'an empty buffer must yield no info');
    expect(reply[2], isNull, reason: 'an empty buffer must yield no text');

    if (nativeLoadable) {
      // The real core is present: it must reject the empty buffer itself.
      expect(status, isNot(DecodeWorker.unavailableStatus));
      expect(status, isNot(1), reason: 'nothing can be decoded from no data');
      expect(status, -1);
    } else {
      // No native core here: the worker must say so explicitly.
      expect(status, DecodeWorker.unavailableStatus);
    }
  });
}
