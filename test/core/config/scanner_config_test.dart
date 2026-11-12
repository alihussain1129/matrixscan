import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/config/app_config.dart';

void main() {
  test('defaults carry the values the app already uses', () {
    const s = ScannerConfig();
    expect(s.host, '192.168.100.100');
    expect(s.port, 9004);
    expect(s.ftpReceiverPort, 2121);
    expect(s.connectTimeoutMs, 10000);
    expect(s.ftpReceiverEnabled, isFalse);
    expect(const AppConfig().validate(), isEmpty);
  });

  test('FTP bind address must be IPv4', () {
    final i = const AppConfig(
      scanner: ScannerConfig(ftpBindAddress: 'localhost'),
    ).validate();
    expect(i.any((x) => x.path == 'scanner.ftpBindAddress'), isTrue);
  });

  test('FTP receiver port out of range is rejected', () {
    final i = const AppConfig(scanner: ScannerConfig(ftpReceiverPort: 70000))
        .validate();
    expect(i.any((x) => x.path == 'scanner.ftpReceiverPort'), isTrue);
  });

  test('huge octet in host is reported, not thrown', () {
    final i = const AppConfig(
      scanner: ScannerConfig(host: '99999999999999999999.1.1.1'),
    ).validate();
    expect(i.any((x) => x.path == 'scanner.host'), isTrue);
  });

  test('reconnect max delay below initial delay is rejected', () {
    final i = const AppConfig(
      scanner: ScannerConfig(
        reconnectInitialDelayMs: 5000,
        reconnectMaxDelayMs: 1000,
      ),
    ).validate();
    expect(i.any((x) => x.path == 'scanner.reconnectMaxDelayMs'), isTrue);
  });

  test('warns when the FTP receiver is on without credentials', () {
    const c = AppConfig(scanner: ScannerConfig(ftpReceiverEnabled: true));
    expect(c.warnings().any((x) => x.path == 'scanner.ftpUsername'), isTrue);
    expect(const AppConfig().warnings(), isEmpty);
  });

  test('json round trip keeps scanner settings and never holds a password', () {
    const c = AppConfig(
      scanner: ScannerConfig(
        ftpReceiverEnabled: true,
        ftpReceiverPort: 2222,
        ftpBindAddress: '10.0.0.2',
        ftpUsername: 'u',
        ftpMaxUploadBytes: 1000000,
        reconnectMaxAttempts: 3,
      ),
    );
    final text = jsonEncode(c.toJson());
    expect(text.toLowerCase().contains('password'), isFalse);
    final issues = <ConfigIssue>[];
    final back = AppConfig.fromJson(
      jsonDecode(text) as Map<String, dynamic>,
      issues,
    );
    expect(issues, isEmpty);
    expect(back.scanner.ftpReceiverPort, 2222);
    expect(back.scanner.ftpBindAddress, '10.0.0.2');
    expect(back.scanner.ftpUsername, 'u');
    expect(back.scanner.ftpMaxUploadBytes, 1000000);
    expect(back.scanner.reconnectMaxAttempts, 3);
  });
}
