import 'dart:convert';

import '../interpret/interpreter.dart';
import '../interpret/scan_field.dart';
import 'code_utils.dart';
import 'http_client.dart';
import 'verification.dart';

String? _s(Object? v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

ScanField _f(String id, String label, String? value) => ScanField(
  id: id,
  label: label,
  value: value,
  origin: FieldOrigin.external,
);

/// Open Food Facts family (Beauty Facts, Products Facts). Same API.
class OpenFactsSource implements VerificationSource {
  OpenFactsSource({
    required this.id,
    required this.name,
    required this.host,
    HttpFetch? fetch,
    DateTime Function()? clock,
  }) : _fetch = fetch ?? robustHttpFetch,
       _clock = clock ?? DateTime.now;

  final String id;
  final String name;
  final String host;
  final HttpFetch _fetch;
  final DateTime Function() _clock;
  final Map<String, (SourceResult, DateTime)> _cache = {};

  @override
  SourceInfo get info => SourceInfo(
    id: id,
    name: name,
    kind: SourceKind.community,
    sendsData: true,
    requirement: 'No account needed. Public, community-edited data.',
    dataSent: 'the GTIN only.',
  );

  @override
  bool appliesTo(Interpretation interpretation) {
    final g = gtinOf(interpretation);
    return g != null && !isBookGtin(g);
  }

  String _strip(String d) => d.replaceFirst(RegExp(r'^0+'), '');

  @override
  Future<SourceResult> check(Interpretation interpretation) async {
    final at = _clock();
    final gtin = gtinOf(interpretation);
    if (gtin == null) {
      return SourceResult(
        info: info,
        checkedAt: at,
        claims: const [
          Claim(
            aspect: 'Record exists',
            status: VerificationStatus.unableToVerify,
            detail: 'No valid GTIN was available for this lookup.',
          ),
        ],
      );
    }
    final hit = _cache[gtin];
    if (hit != null && at.difference(hit.$2) < const Duration(minutes: 5)) {
      return hit.$1;
    }

    final uri = Uri.https(host, '/api/v2/product/$gtin', {
      'fields': 'code,product_name,brands,quantity,categories,last_modified_t',
    });
    final HttpReply reply;
    try {
      reply = await _fetch(uri);
    } catch (e) {
      return SourceResult.unavailable(
        info,
        at,
        'Could not reach $name (${e.runtimeType}).',
      );
    }
    if (reply.statusCode >= 500 || reply.statusCode == 429) {
      return SourceResult.unavailable(
        info,
        at,
        '$name answered with HTTP ${reply.statusCode}.',
      );
    }

    Object? json;
    try {
      json = jsonDecode(reply.body);
    } catch (_) {
      json = null;
    }
    if (json is! Map) {
      return SourceResult(
        info: info,
        checkedAt: at,
        claims: [
          Claim(
            aspect: 'Record exists',
            status: VerificationStatus.unableToVerify,
            detail: '$name returned an unreadable answer.',
          ),
        ],
      );
    }

    final product = json['product'];
    final found = json['status'] == 1 && product is Map;
    SourceResult result;
    if (!found) {
      result = SourceResult(
        info: info,
        checkedAt: at,
        claims: [
          Claim(
            aspect: 'Record exists',
            status: VerificationStatus.notFound,
            detail:
                '$name has no record for this code. That does not mean the '
                'product is fake; the database may simply not list it.',
          ),
        ],
      );
    } else {
      final returned = _s(product['code']);
      final mismatch = returned != null && _strip(returned) != _strip(gtin);
      DateTime? updated;
      final t = product['last_modified_t'];
      if (t is int) {
        updated = DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true);
      }
      final fields = <ScanField>[
        for (final e in {
          'Product name': _s(product['product_name']),
          'Brand': _s(product['brands']),
          'Quantity': _s(product['quantity']),
          'Categories': _s(product['categories']),
        }.entries)
          if (e.value != null) _f('$id.${e.key}', e.key, e.value),
      ];
      result = SourceResult(
        info: info,
        checkedAt: at,
        fields: fields,
        dataUpdatedAt: updated,
        claims: [
          Claim(
            aspect: 'Record exists',
            status: mismatch
                ? VerificationStatus.mismatch
                : VerificationStatus.recordFound,
            detail: mismatch
                ? '$name returned a record for a different code ($returned).'
                : 'A community record matches this code. A match does not '
                      'prove authenticity or safety.',
            dataUpdatedAt: updated,
          ),
        ],
      );
    }
    if (result.claims.every(
      (c) =>
          c.status == VerificationStatus.recordFound ||
          c.status == VerificationStatus.notFound,
    )) {
      _cache[gtin] = (result, at);
    }
    return result;
  }
}
