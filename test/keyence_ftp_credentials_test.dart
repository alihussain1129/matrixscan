import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/storage/image_storage_service.dart';
import 'package:exalted/features/devices/keyence/keyence_ftp_receiver.dart';

void main() {
  test('configureCredentials enables startup', () async {
    final r = KeyenceFtpReceiver(port: 0, imageStorage: ImageStorageService());
    expect(await r.start(), isFalse);
    r.configureCredentials(username: 'u', password: 'p');
    expect(await r.start(), isTrue);
    await r.stop();
  });

  test('credentials cannot change while running', () async {
    final r = KeyenceFtpReceiver(
      port: 0,
      imageStorage: ImageStorageService(),
      username: 'u',
      password: 'p',
    );
    expect(await r.start(), isTrue);
    expect(
      () => r.configureCredentials(username: 'x', password: 'y'),
      throwsStateError,
    );
    await r.stop();
  });
}
