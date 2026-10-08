import 'package:exalted/features/scanner/link_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts http and https links, including port, path and query', () {
    final a = linkUri('https://example.com/a?b=1');
    expect(a, isNotNull);
    expect(a!.scheme, 'https');
    expect(a.host, 'example.com');

    final b = linkUri('  http://example.com:8080/x  ');
    expect(b, isNotNull);
    expect(b!.scheme, 'http');
    expect(b.port, 8080);

    expect(linkUri('HTTPS://Example.com/Path')?.scheme, 'https');
  });

  test('a bare www address is opened as https', () {
    final uri = linkUri('www.example.com/page');
    expect(uri, isNotNull);
    expect(uri!.scheme, 'https');
    expect(uri.host, 'www.example.com');
  });

  test('anything that is not a single web link is rejected', () {
    const rejected = [
      '',
      '   ',
      'example.com',
      'https://',
      'http://',
      'https://exa mple.com',
      'https://example.com and more text',
      'ftp://example.com',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'mailto:someone@example.com',
      'tel:+923001234567',
      'WIFI:S:Network;T:WPA;P:Password;;',
      'LOT-4471-DM',
    ];
    for (final text in rejected) {
      expect(linkUri(text), isNull, reason: 'should reject: "$text"');
    }
  });
}
