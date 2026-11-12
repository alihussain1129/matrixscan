import 'package:exalted/features/link/link_pairing.dart';
import 'package:exalted/features/link/pairing_scan_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only Exalted pairing codes are accepted from a scan', () {
    expect(pairingFromScan('WIFI:T:WPA;S:home;P:secret;;'), isNull);
    expect(pairingFromScan('https://example.com/?x=1'), isNull);
    expect(pairingFromScan(''), isNull);
    expect(pairingFromScan('{"app":"other","v":1}'), isNull);
  });

  test('a real pairing code survives the round trip', () {
    final payload = PairingPayload(
      hosts: ['192.168.1.20'],
      port: 47821,
      fingerprint: 'ab' * 32,
      token: 'tokentokentokentoken',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      desktopName: 'Desk',
    );
    final back = pairingFromScan(payload.encode());
    expect(back, isNotNull);
    expect(back!.port, 47821);
    expect(back.desktopName, 'Desk');
  });
}
