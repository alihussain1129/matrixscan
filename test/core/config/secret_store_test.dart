import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/platform_secret_store.dart';

import '../../support/in_memory_secret_store.dart';

void main() {
  test('in-memory store round-trips and deletes', () async {
    final s = InMemorySecretStore();
    expect(await s.read('k'), isNull);
    await s.write('k', 'v');
    expect(await s.read('k'), 'v');
    await s.delete('k');
    expect(await s.read('k'), isNull);
  });

  test('platform store rejects a blank key and an empty value', () async {
    final s = PlatformSecretStore();
    expect(() => s.write('  ', 'v'), throwsArgumentError);
    expect(() => s.write('k', ''), throwsArgumentError);
  });

  test('the FTP password key is masked by redact()', () {
    final out = redact({ScannerConfig.ftpPasswordSecretKey: 'hunter2'}) as Map;
    expect(out[ScannerConfig.ftpPasswordSecretKey], '***');
  });
}
