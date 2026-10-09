import '../features/scanner/link_utils.dart';
import 'interpreter.dart';
import 'scan_field.dart';

final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

/// Web links. Never contacts the link: redirects and reputation are reported
/// as not checked.
class UrlInterpreter implements PayloadInterpreter {
  @override
  String get id => 'url';

  @override
  Interpretation? interpret(ScanPayload payload) {
    final uri = linkUri(payload.raw);
    if (uri == null) return null;

    final text = payload.raw.trim();
    final assumed = text.toLowerCase().startsWith('www.');
    final warnings = <String>[];

    if (uri.userInfo.isNotEmpty) {
      warnings.add(
        'The link has text before the host (user@host); the real host is '
        '${uri.host}.',
      );
    }
    if (_ipv4.hasMatch(uri.host) || uri.host.contains(':')) {
      warnings.add('The host is an IP address, not a domain name.');
    }
    if (uri.host.split('.').any((l) => l.startsWith('xn--'))) {
      warnings.add(
        'The host uses punycode (xn--), which can disguise lookalike '
        'characters.',
      );
    }
    if (uri.scheme != 'https') {
      warnings.add('The link does not use HTTPS.');
    }
    if (uri.hasPort && uri.port != 80 && uri.port != 443) {
      warnings.add('The link uses a non-standard port (${uri.port}).');
    }

    final queryFields = <ScanField>[];
    try {
      uri.queryParametersAll.forEach((key, values) {
        queryFields.add(ScanField(label: key, value: values.join(', ')));
      });
    } catch (_) {
      warnings.add('The query string could not be decoded.');
    }
    if (queryFields.isEmpty) {
      queryFields.add(const ScanField.notPresent('Query parameters', id: 'query'));
    }

    return Interpretation(
      interpreterId: id,
      formatName: 'Web link',
      warnings: warnings,
      sections: [
        ScanSection(
          id: 'url',
          title: 'Web link',
          fields: [
            ScanField(
              id: 'url',
              label: 'Link',
              value: text,
              origin: FieldOrigin.decoded,
              standard: 'URL (RFC 3986)',
            ),
            ScanField(
              id: 'scheme',
              label: 'Scheme',
              value: uri.scheme,
              origin: assumed ? FieldOrigin.calculated : FieldOrigin.parsed,
              note: assumed
                  ? 'Assumed: the text starts with www., so https was added.'
                  : null,
            ),
            ScanField(id: 'host', label: 'Host', value: uri.host),
            if (uri.hasPort)
              ScanField(id: 'port', label: 'Port', value: '${uri.port}')
            else
              const ScanField.notPresent('Port', id: 'port'),
            ScanField(
              id: 'https',
              label: 'Encrypted connection (HTTPS)',
              value: uri.scheme == 'https' ? 'Yes' : 'No',
              origin: FieldOrigin.calculated,
              note:
                  'HTTPS protects the connection only. It does not show that '
                  'the site is trustworthy.',
            ),
            if (uri.path.isEmpty)
              const ScanField.notPresent('Path', id: 'path')
            else
              ScanField(id: 'path', label: 'Path', value: uri.path),
            if (uri.fragment.isEmpty)
              const ScanField.notPresent('Fragment', id: 'fragment')
            else
              ScanField(id: 'fragment', label: 'Fragment', value: uri.fragment),
          ],
          sections: [
            ScanSection(id: 'query', title: 'Query parameters', fields: queryFields),
          ],
        ),
        ScanSection(
          id: 'url_checks',
          title: 'Online checks',
          fields: const [
            ScanField(
              id: 'redirects',
              label: 'Redirects',
              presence: FieldPresence.unavailable,
              note: 'Not checked. EXALTED does not contact the link.',
            ),
            ScanField(
              id: 'reputation',
              label: 'Domain reputation',
              presence: FieldPresence.unavailable,
              note: 'No reputation source is configured.',
            ),
          ],
        ),
      ],
    );
  }
}