import '../features/scanner/link_utils.dart';
import 'interpreter.dart';
import 'scan_field.dart';

final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

const Map<String, String> _gs1UrlAiLabels = {
  '01': 'GTIN',
  '10': 'Batch or lot number',
  '11': 'Production date',
  '13': 'Packaging date',
  '15': 'Best-before date',
  '17': 'Expiration date',
  '20': 'Product variant',
  '21': 'Serial number',
  '30': 'Count',
  '37': 'Count of trade items',
  '240': 'Additional product identification',
  '250': 'Secondary serial number',
};

bool _validGtin14(String value) {
  if (!RegExp(r'^\d{14}$').hasMatch(value)) return false;

  var sum = 0;
  for (var i = 0; i < value.length - 1; i++) {
    final digit = value.codeUnitAt(value.length - 2 - i) - 48;
    sum += digit * (i.isEven ? 3 : 1);
  }

  return (10 - sum % 10) % 10 == value.codeUnitAt(13) - 48;
}

/// Recognizes a deliberately narrow AI/value URL path pattern.
/// This does not establish that the URL is an official GS1 Digital Link.
ScanSection? _gs1UrlProductIds(Uri uri) {
  final segments = uri.pathSegments;

  // Require complete AI/value pairs and AI 01 as the primary identifier.
  if (segments.length < 2 || segments.length.isOdd || segments.first != '01') {
    return null;
  }

  final seen = <String>{};
  final fields = <ScanField>[];

  for (var i = 0; i < segments.length; i += 2) {
    final ai = segments[i];
    final value = segments[i + 1];

    if (!_gs1UrlAiLabels.containsKey(ai) ||
        !seen.add(ai) ||
        value.isEmpty ||
        value.contains('\u001d')) {
      return null;
    }

    if (ai == '01' && !RegExp(r'^\d{14}$').hasMatch(value)) {
      return null;
    }

    fields.add(
      ScanField(
        id: ai,
        label: 'AI $ai — ${_gs1UrlAiLabels[ai]}',
        value: value,
        standard: 'GS1 URL path (unconfirmed)',
        dataType: ai == '01' ? 'GTIN-14' : null,
        origin: FieldOrigin.parsed,
        validation: ai == '01'
            ? (_validGtin14(value)
                  ? FieldValidation.valid
                  : FieldValidation.invalid)
            : FieldValidation.notChecked,
        sensitive: ai == '21' || ai == '10' || ai == '250',
        note: ai == '01'
            ? (_validGtin14(value)
                  ? 'The GTIN-14 check digit is valid. This does not verify the product or URL.'
                  : 'The GTIN-14 check digit is invalid. It must not be used for product lookup.')
            : (ai == '21' || ai == '10' || ai == '250')
            ? 'Identifier extracted from the URL path. Not sent to product lookup.'
            : 'Identifier extracted from the URL path; its meaning has not been independently verified.',
      ),
    );
  }

  if (!seen.contains('01')) return null;

  fields.add(
    const ScanField(
      id: 'format_notice',
      label: 'Format status',
      value: 'GS1-style URL path; official Digital Link status unconfirmed',
      standard: 'GS1 URL path (unconfirmed)',
      origin: FieldOrigin.calculated,
      note: 'A URL path pattern alone does not prove GS1 registration, product authenticity, or ownership.',
    ),
  );

  return ScanSection(
    id: 'url_product_ids',
    title: 'Product identifiers in URL',
    fields: fields,
  );
}

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

    final productIds = _gs1UrlProductIds(uri);
    if (productIds != null) {
      warnings.add(
        'GS1-style identifiers were extracted from the URL path. '
        'The URL is not confirmed as an official GS1 Digital Link, and '
        'the product or website has not been authenticated.',
      );
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
      queryFields.add(
        const ScanField.notPresent('Query parameters', id: 'query'),
      );
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
            ScanSection(
              id: 'query',
              title: 'Query parameters',
              fields: queryFields,
            ),
          ],
        ),
        ?productIds,
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
