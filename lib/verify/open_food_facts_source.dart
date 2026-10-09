import 'dart:convert';
import 'dart:io';

import '../interpret/interpreter.dart';
import '../interpret/scan_field.dart';
import 'verification.dart';

class HttpReply {
  const HttpReply(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

typedef HttpFetch = Future<HttpReply> Function(Uri uri);

Future<HttpReply> defaultHttpFetch(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, 'EXALTED/1.0 (barcode scanner)');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return HttpReply(res.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

/// GTIN-8/12/13/14 check digit.
bool gtinCheckOk(String d) {
  if (!RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(d)) return false;
  var sum = 0;
  for (var i = 0; i < d.length - 1; i++) {
    final digit = d.codeUnitAt(d.length - 2 - i) - 48;
    sum += digit * (i.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == d.codeUnitAt(d.length - 1) - 48;
}

/// A structurally valid GTIN in the scan: a GS1 AI 01 value, or a bare
/// numeric code with a valid check digit.
String? gtinFrom(Interpretation i) {
  for (final f in i.allFields) {
    if (f.sensitive) continue;
    if (f.id == '01' &&
        f.standard == 'GS1' &&
        f.validation == FieldValidation.valid) {
      final v = f.value;
      if (v != null && gtinCheckOk(v)) return v;
    }
  }
  for (final f in i.allFields) {
    if (f.sensitive || f.id != 'raw') continue;
    final v = f.value;
    if (v != null && gtinCheckOk(v)) return v;
  }
  return null;
}

String _offCode(String gtin) =>
    (gtin.length == 14 && gtin.startsWith('0')) ? gtin.substring(1) : gtin;

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

String? _tags(Object? v) {
  if (v is! List || v.isEmpty) return null;
  return v
      .map((e) => e.toString().replaceFirst(RegExp(r'^[a-z]{2}:'), ''))
      .join(', ');
}

const _fieldList =
    'code,product_name,brands,quantity,ingredients_text,allergens_tags,'
    'categories,origins,countries,labels,packaging,nutriscore_grade,'
    'nutriments,last_modified_t,image_front_url';

const _nutrients = <(String, String, String)>[
  ('energy-kcal_100g', 'Energy', 'kcal per 100 g'),
  ('fat_100g', 'Fat', 'g per 100 g'),
  ('saturated-fat_100g', 'Saturated fat', 'g per 100 g'),
  ('carbohydrates_100g', 'Carbohydrates', 'g per 100 g'),
  ('sugars_100g', 'Sugars', 'g per 100 g'),
  ('proteins_100g', 'Protein', 'g per 100 g'),
  ('salt_100g', 'Salt', 'g per 100 g'),
];

/// Open Food Facts: free public API, community-edited food data. It is not an
/// official or manufacturer record, so it can give "Record found" but never
/// "Verified". Only the GTIN is sent.
class OpenFoodFactsSource implements VerificationSource {
  OpenFoodFactsSource({HttpFetch? fetch, DateTime Function()? clock})
    : _fetch = fetch ?? defaultHttpFetch,
      _clock = clock ?? DateTime.now;

  final HttpFetch _fetch;
  final DateTime Function() _clock;

  static const sourceInfo = SourceInfo(
    id: 'openfoodfacts',
    name: 'Open Food Facts',
    kind: SourceKind.community,
    sendsData: true,
    requirement:
        'No account needed. Public, community-edited food and drink data.',
    dataSent: 'the GTIN only.',
  );

  @override
  SourceInfo get info => sourceInfo;

  @override
  bool appliesTo(Interpretation interpretation) =>
      gtinFrom(interpretation) != null;

  @override
  Future<SourceResult> check(Interpretation interpretation) async {
    final at = _clock();
    final code = _offCode(gtinFrom(interpretation)!);
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$code', {
      'fields': _fieldList,
    });

    final HttpReply reply;
    try {
      reply = await _fetch(uri);
    } catch (e) {
      return SourceResult.unavailable(
        info,
        at,
        'Could not reach Open Food Facts (${e.runtimeType}).',
      );
    }
    if (reply.statusCode >= 500 || reply.statusCode == 429) {
      return SourceResult.unavailable(
        info,
        at,
        'Open Food Facts answered with HTTP ${reply.statusCode}.',
      );
    }

    Object? json;
    try {
      json = jsonDecode(reply.body);
    } catch (_) {
      json = null;
    }
    if (json is! Map) {
      if (reply.statusCode != 200) {
        return SourceResult.unavailable(
          info,
          at,
          'Open Food Facts answered with HTTP ${reply.statusCode}.',
        );
      }
      return SourceResult(
        info: info,
        checkedAt: at,
        claims: const [
          Claim(
            aspect: 'Record exists',
            status: VerificationStatus.unableToVerify,
            detail: 'The reply could not be read.',
          ),
        ],
      );
    }

    if (json['status'] == 0) {
      return SourceResult(
        info: info,
        checkedAt: at,
        claims: const [
          Claim(
            aspect: 'Record exists',
            status: VerificationStatus.notFound,
            detail:
                'Open Food Facts covers food and drink only, and not every '
                'product. Not being listed does not mean the code is invalid '
                'or the product is fake.',
          ),
        ],
      );
    }
    final product = json['product'];
    if (json['status'] != 1 || product is! Map) {
      return SourceResult(
        info: info,
        checkedAt: at,
        claims: const [
          Claim(
            aspect: 'Record exists',
            status: VerificationStatus.unableToVerify,
            detail: 'The reply was not in the expected form.',
          ),
        ],
      );
    }

    final p = Map<String, dynamic>.from(product);
    final t = p['last_modified_t'];
    final DateTime? updated = t is num
        ? DateTime.fromMillisecondsSinceEpoch((t * 1000).round(), isUtc: true)
        : null;

    ScanField ext(String id, String label, String? v, {String? unit}) {
      if (v == null) {
        return ScanField(
          id: 'off.$id',
          label: label,
          presence: FieldPresence.unavailable,
          origin: FieldOrigin.external,
          note: 'The Open Food Facts record has no value for this.',
          updatedAt: updated,
        );
      }
      return ScanField(
        id: 'off.$id',
        label: label,
        value: v,
        unit: unit,
        origin: FieldOrigin.external,
        note: 'From Open Food Facts (community-edited).',
        updatedAt: updated,
      );
    }

    final name = _str(p['product_name']);
    final fields = <ScanField>[
      ext('name', 'Product name', name),
      ext('brands', 'Brand', _str(p['brands'])),
      ext('quantity', 'Quantity', _str(p['quantity'])),
      ext('ingredients', 'Ingredients', _str(p['ingredients_text'])),
      ext('allergens', 'Allergens (as listed in record)', _tags(p['allergens_tags'])),
      ext('categories', 'Categories', _str(p['categories'])),
      ext('origins', 'Origin', _str(p['origins'])),
      ext('countries', 'Sold in', _str(p['countries'])),
      ext('labels', 'Labels and certifications', _str(p['labels'])),
      ext('packaging', 'Packaging', _str(p['packaging'])),
      ext('nutriscore', 'Nutri-Score', _str(p['nutriscore_grade'])),
      ext('image', 'Front image URL', _str(p['image_front_url'])),
    ];
    final nutriments = p['nutriments'];
    if (nutriments is Map) {
      for (final (key, label, unit) in _nutrients) {
        final v = nutriments[key];
        if (v is num) {
          fields.add(ext('nutrition.$key', label, v.toString(), unit: unit));
        }
      }
    }

    final recordCode = _str(p['code']);
    String strip(String s) => s.replaceFirst(RegExp(r'^0+'), '');
    final claims = <Claim>[
      Claim(
        aspect: 'Record exists',
        status: VerificationStatus.recordFound,
        detail:
            'A community record exists for this code. It is not an official '
            'or manufacturer confirmation.',
        dataUpdatedAt: updated,
      ),
      if (recordCode != null)
        strip(recordCode) == strip(code)
            ? Claim(
                aspect: 'GTIN in record',
                status: VerificationStatus.recordFound,
                value: recordCode,
                detail: 'The record carries the same GTIN as the scan.',
                dataUpdatedAt: updated,
              )
            : Claim(
                aspect: 'GTIN in record',
                status: VerificationStatus.mismatch,
                value: recordCode,
                detail: 'The record carries a different GTIN than the scan.',
                dataUpdatedAt: updated,
              ),
      if (name != null)
        Claim(
          aspect: 'Product name in record',
          status: VerificationStatus.recordFound,
          value: name,
          dataUpdatedAt: updated,
        ),
    ];

    return SourceResult(
      info: info,
      checkedAt: at,
      claims: claims,
      fields: fields,
      dataUpdatedAt: updated,
    );
  }
}