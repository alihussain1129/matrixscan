import 'package:exalted/features/link/link_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validatePeerAddress', () {
    test('accepts local IPv4 addresses and valid ports', () {
      expect(validatePeerAddress('192.168.1.20', '47821'), isNull);
      expect(validatePeerAddress(' 10.0.0.5 ', ' 8080 '), isNull);
      expect(validatePeerAddress('172.16.4.9', '1'), isNull);
      expect(validatePeerAddress('127.0.0.1', '65535'), isNull);
    });

    test('rejects public, malformed and IPv6 addresses', () {
      expect(validatePeerAddress('8.8.8.8', '47821'), isNotNull);
      expect(validatePeerAddress('example.com', '47821'), isNotNull);
      expect(validatePeerAddress('', '47821'), isNotNull);
      expect(validatePeerAddress('::1', '47821'), isNotNull);
      expect(validatePeerAddress('172.32.0.1', '47821'), isNotNull);
    });

    test('rejects bad ports', () {
      expect(validatePeerAddress('192.168.1.20', '0'), isNotNull);
      expect(validatePeerAddress('192.168.1.20', '65536'), isNotNull);
      expect(validatePeerAddress('192.168.1.20', 'abc'), isNotNull);
      expect(validatePeerAddress('192.168.1.20', ''), isNotNull);
    });
  });
}
