import 'package:exalted/interpret/default_registry.dart';
import 'package:exalted/interpret/interpreter.dart';
import 'package:exalted/interpret/scan_field.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 9);
final _registry = defaultInterpreterRegistry(clock: () => _now);

Interpretation _run(String raw) => _registry.interpret(
  ScanPayload(raw: raw, symbology: 'QR Code', source: 'live'),
);

ScanField _id(Interpretation i, String id) =>
    i.allFields.firstWhere((f) => f.id == id);

List<ScanField> _label(Interpretation i, String label) =>
    i.allFields.where((f) => f.label == label).toList();

void main() {
  group('Wi-Fi', () {
    const raw = 'WIFI:S:CafeNet;T:WPA;P:s3cret-pass;;';

    test('fields, and the password is hidden in exports', () {
      final i = _run(raw);
      expect(i.formatName, 'Wi-Fi network');
      expect(_id(i, 'ssid').value, 'CafeNet');
      expect(_id(i, 'security').value, 'WPA/WPA2');
      expect(_id(i, 'password').sensitive, isTrue);
      expect(_id(i, 'password').value, 's3cret-pass');
      expect(_id(i, 'raw').value, raw);
      expect(i.toJson().toString(), isNot(contains('s3cret-pass')));
      expect(i.toJson(includeSensitive: true).toString(), contains('s3cret-pass'));
    });

    test('open network has no password', () {
      final i = _run('WIFI:S:Guest;T:nopass;;');
      expect(_id(i, 'password').presence, FieldPresence.notPresent);
      expect(_id(i, 'security').value, 'Open (no password)');
    });

    test('WEP gets a warning', () {
      final i = _run('WIFI:S:Old;T:WEP;P:abc;;');
      expect(i.warnings.any((w) => w.contains('WEP')), isTrue);
    });
  });

  group('URL', () {
    test('parts and warnings', () {
      final i = _run('https://user@evil.example.com:8443/path/a?x=1&y=two#frag');
      expect(i.formatName, 'Web link');
      expect(_id(i, 'scheme').value, 'https');
      expect(_id(i, 'host').value, 'evil.example.com');
      expect(_id(i, 'port').value, '8443');
      expect(_id(i, 'path').value, '/path/a');
      expect(_id(i, 'fragment').value, 'frag');
      expect(
        i.section('url')!.sections.single.fields.map((f) => '${f.label}=${f.value}'),
        ['x=1', 'y=two'],
      );
      expect(i.warnings.any((w) => w.contains('real host is evil.example.com')), isTrue);
      expect(i.warnings.any((w) => w.contains('non-standard port')), isTrue);
      expect(_id(i, 'redirects').presence, FieldPresence.unavailable);
      expect(_id(i, 'reputation').presence, FieldPresence.unavailable);
    });

    test('plain HTTP and IP hosts are flagged', () {
      final i = _run('http://192.168.1.1/x');
      expect(i.warnings.any((w) => w.contains('does not use HTTPS')), isTrue);
      expect(i.warnings.any((w) => w.contains('IP address')), isTrue);
      expect(_id(i, 'https').value, 'No');
    });

    test('punycode host is flagged', () {
      final i = _run('https://xn--80ak6aa92e.com/');
      expect(i.warnings.any((w) => w.contains('punycode')), isTrue);
    });

    test('www. links get an assumed https scheme, noted as such', () {
      final i = _run('www.example.com');
      expect(_id(i, 'scheme').value, 'https');
      expect(_id(i, 'scheme').origin, FieldOrigin.calculated);
      expect(_id(i, 'scheme').note, contains('Assumed'));
    });

    test('HTTPS alone gives no trust claim', () {
      final i = _run('https://example.com/');
      expect(_id(i, 'https').note, contains('does not show that the site is trustworthy'));
    });

    test('text and other schemes are not links', () {
      expect(_run('hello world').formatName, 'Unknown format');
      expect(_run('ftp://example.com/file').formatName, 'Unknown format');
    });
  });

  group('contacts', () {
    final vcard = [
      'BEGIN:VCARD',
      'VERSION:3.0',
      'FN:Jane Q. Public',
      'N:Public;Jane;Q.;Dr.;',
      r'ORG:Example\, Inc.;Sales',
      'TITLE:Engineer',
      'TEL;TYPE=CELL:+1-555-0100',
      'EMAIL:jane@example.com',
      'ADR;TYPE=WORK:;;1 Main St;Springfield;IL;62701;USA',
      'X-CUSTOM:hello',
      'END:VCARD',
    ].join('\n');

    test('vCard fields', () {
      final i = _run(vcard);
      expect(i.formatName, 'vCard contact');
      expect(_label(i, 'Full name').single.value, 'Jane Q. Public');
      expect(_label(i, 'Name').single.value, 'Dr. Jane Q. Public');
      expect(_label(i, 'Organization').single.value, 'Example, Inc., Sales');
      expect(_label(i, 'Phone').single.value, '+1-555-0100');
      expect(_label(i, 'Email').single.value, 'jane@example.com');
      expect(_label(i, 'Address').single.value, '1 Main St, Springfield, IL, 62701, USA');
      expect(_label(i, 'Other: X-CUSTOM').single.value, 'hello');
      expect(_id(i, 'raw').value, vcard);
    });

    test('folded vCard lines are joined', () {
      final i = _run(
        ['BEGIN:VCARD', 'FN:A B', 'NOTE:abc', ' def', 'END:VCARD'].join('\n'),
      );
      expect(_label(i, 'Note').single.value, 'abcdef');
    });

    test('missing phone and email are reported as not present', () {
      final i = _run('BEGIN:VCARD\nFN:A B\nEND:VCARD');
      expect(_label(i, 'Phone').single.presence, FieldPresence.notPresent);
      expect(_label(i, 'Email').single.presence, FieldPresence.notPresent);
    });

    // Name order (family,given) is from memory of the MECARD format and is
    // not yet checked against its specification.
    test('MECARD fields', () {
      final i = _run(r'MECARD:N:Owen,Sean;TEL:+15550100;EMAIL:sean@example.com;NOTE:a\;b;;');
      expect(i.formatName, 'MECARD contact');
      expect(_label(i, 'Name').single.value, 'Sean Owen');
      expect(_label(i, 'Phone').single.value, '+15550100');
      expect(_label(i, 'Note').single.value, 'a;b');
    });
  });

  group('GS1', () {
    const full = '(01)04006381333931(17)270924(10)ABC123(21)XYZ789';

    test('all key fields, nothing claimed beyond the text', () {
      final i = _run(full);
      expect(i.interpreterId, 'gs1');
      expect(_id(i, '01').value, '04006381333931');
      expect(_id(i, '01').validation, FieldValidation.valid);
      expect(_id(i, '17').value, '2027-09-24');
      expect(_id(i, '17').original, '270924');
      expect(_id(i, 'expiryStatus').value, 'Not expired');
      expect(_id(i, 'expiryStatus').origin, FieldOrigin.calculated);
      expect(_id(i, '10').value, 'ABC123');
      expect(_id(i, '21').value, 'XYZ789');
      expect(_id(i, 'raw').value, full);
      expect(i.warnings.any((w) => w.contains('not confirmed as GS1')), isTrue);
      expect(i.allFields.every((f) => f.verification == FieldVerification.notVerified), isTrue);
    });

    test('absent fields are not present, and no expiry status is invented', () {
      final i = _run('(01)04006381333931');
      for (final ai in ['10', '21', '17']) {
        expect(_id(i, ai).presence, FieldPresence.notPresent);
      }
      expect(i.allFields.where((f) => f.id == 'expiryStatus'), isEmpty);
    });

    test('the invalid GTIN seen on the phone is flagged', () {
      final i = _run('(01)08976543211234(17)270924(10)272718(21)8760C6AEDE474');
      expect(_id(i, '01').validation, FieldValidation.invalid);
      expect(i.warnings.any((w) => w.contains('expected 9')), isTrue);
      expect(_id(i, '10').value, '272718');
      expect(_id(i, '21').value, '8760C6AEDE474');
    });

    test('expiry statuses', () {
      expect(_id(_run('(17)200101'), 'expiryStatus').value, 'Expired');
      expect(_id(_run('(17)200101'), 'expiryStatus').warning, isNotNull);
      expect(
        _id(_run('(17)261015'), 'expiryStatus').value,
        'Near expiry (within 30 days)',
      );
      final bad = _run('(17)271332');
      expect(_id(bad, '17').validation, FieldValidation.invalid);
      expect(bad.allFields.where((f) => f.id == 'expiryStatus'), isEmpty);
    });

    test('unknown AIs and unparsed text are kept', () {
      final unknown = _run('(01)04006381333931(99)hello');
      expect(_id(unknown, '99').value, 'hello');
      expect(_id(unknown, '99').note, contains('Not interpreted'));
      final tail = _run(']d20104006381333931ZZtail');
      expect(_id(tail, 'unparsed').value, 'ZZtail');
    });

    test('an EAN-13 number is not treated as GS1', () {
      expect(_run('8600250286876').formatName, 'Unknown format');
    });
  });

  test('Wi-Fi is not taken over by the URL interpreter', () {
    expect(_run('WIFI:S:a;T:nopass;;').interpreterId, 'wifi');
  });
}