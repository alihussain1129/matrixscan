import 'package:exalted/ffi/decode_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'worker starts, answers and shuts down without the native core',
    () async {
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
      expect(reply, isNotNull);
      expect(reply![0], DecodeWorker.unavailableStatus);
      worker.dispose();
    },
  );
}
