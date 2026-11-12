import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/storage/image_storage_service.dart';
import 'package:exalted/features/devices/keyence/keyence_ftp_receiver.dart';

void main() {
  final cases = <List<String?>>[
    [null, null],
    ['user', null],
    [null, 'pw'],
    ['   ', 'pw'],
    ['user', ''],
  ];

  for (final c in cases) {
    test('refuses to start with username=${c[0]} password=${c[1]}', () async {
      final r = KeyenceFtpReceiver(
        port: 0,
        imageStorage: ImageStorageService(),
        username: c[0],
        password: c[1],
      );
      expect(await r.start(), isFalse);
      expect(r.isRunning, isFalse);
      await r.stop();
    });
  }

  test('starts when both credentials are present', () async {
    final r = KeyenceFtpReceiver(
      port: 0,
      imageStorage: ImageStorageService(),
      username: 'user',
      password: 'pw',
    );
    expect(await r.start(), isTrue);
    expect(r.isRunning, isTrue);
    await r.stop();
  });
}
