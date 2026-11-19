import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/features/devices/core/upload_guard.dart';
import 'package:exalted/features/devices/keyence/keyence_ftp_receiver.dart';

void main() {
  test('default config uses the documented SR-750 FTP service port', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final r = c.read(keyenceFtpReceiverProvider);
    expect(r.port, 21);
    expect(r.activeDataSourcePort, 20);
    expect(r.maxUploadBytes, kMaxUploadBytes);
    expect(r.username, isNull);
    expect(r.password, isNull);
  });

  test('config port and upload limit reach the receiver', () {
    final c = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          const AppConfig(
            scanner: ScannerConfig(
              ftpReceiverPort: 2222,
              ftpMaxUploadBytes: 5000000,
              ftpUsername: 'u',
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final r = c.read(keyenceFtpReceiverProvider);
    expect(r.port, 2222);
    expect(r.maxUploadBytes, 5000000);
    expect(r.username, isNull, reason: 'no password store yet');
  });
}
