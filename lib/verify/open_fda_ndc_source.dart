import 'dart:async';
import 'dart:convert';

import '../interpret/interpreter.dart';
import '../interpret/scan_field.dart';
import 'code_utils.dart';
import 'http_client.dart';
import 'verification.dart';

/// The 10-digit NDC carried in a US pharmacy GTIN (12, 13 or 14 digits), or
/// null when the GTIN does not have the NDC pattern. Kept for existing
/// callers; the source itself uses [fdaUpcKey].
String? ndc10FromGtin(String gtin) {
  if (!RegExp(r'^\d{12,14}$').hasMatch(gtin)) return null;
  final p = gtin.padLeft(14, '0');
  if (p.substring(1, 3) != '03') return null;
  return p.substring(3, 13);
}

/// A 10-digit NDC has three possible hyphenation layouts. Kept for existing
/// callers.
List<String> ndcPackageCandidates(String n) => [
  '${n.substring(0, 4)}-${n.substring(4, 8)}-${n.substring(8)}',
  '${n.substring(0, 5)}-${n.substring(5, 8)}-${n.substring(8)}',
  '${n.substring(0, 5)}-${n.substring(5, 9)}-${n.substring(9)}',
];

/// True for a digits-only GS1 code (8, 12, 13 or 14 digits) whose check digit
/// is correct.
bool gtinCheckDigitOk(String d) {
  if (!RegExp(r'^(\d{8}|\d{12,14})$').hasMatch(d)) return false;
  var sum = 0;
  for (var i = 0; i < d.length - 1; i++) {
    final digit = d.codeUnitAt(d.length - 2 - i) - 48;
    sum += digit * (i.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == d.codeUnitAt(d.length - 1) - 48;
}

/// The 13-digit form openFDA stores in `openfda.upc` (checked against real
/// records: only this form matches), or null when [code] cannot be searched.
/// Rejects non-digits, wrong lengths, bad check digits, 14-digit codes with a
/// non-zero indicator digit, and all-zero codes (openFDA uses 13 zeros as a
/// placeholder UPC on many records).
String? fdaUpcKey(String code) {
  if (!gtinCheckDigitOk(code)) return null;
  final String key;
  if (code.length == 12) {
    key = '0$code';
  } else if (code.length == 13) {
    key = code;
  } else if (code.length == 14 && code.startsWith('0')) {
    key = code.substring(1);
  } else {
    return null;
  }
  if (RegExp(r'^0+$').hasMatch(key)) return null;
  return key;
}

/// The 10-digit NDC inside a 13-digit key shaped `03` + NDC10 + check digit.
/// Only an identifying hint: about 70% of UPCs on real records have this
/// shape, the rest are ordinary retail codes.
String? _ndc10FromKey(String key) =>
    key.startsWith('03') ? key.substring(2, 12) : null;

String? _s(Object? v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

String? _listOf(Object? v) =>
    v is List && v.isNotEmpty ? v.map((e) => e.toString()).join(', ') : null;

String? _ingredientsOf(Map r) {
  final ai = r['active_ingredients'];
  if (ai is! List) return null;
  final out = <String>[];
  for (final e in ai) {
    if (e is Map && _s(e['name']) != null) {
      final st = _s(e['strength']);
      out.add(st == null ? _s(e['name'])! : '${_s(e['name'])} $st');
    }
  }
  return out.isEmpty ? null : out.join('; ');
}

String? _labelerOf(Map r) {
  final l = _s(r['labeler_name']);
  if (l != null) return l;
  final of = r['openfda'];
  return of is Map ? _listOf(of['manufacturer_name']) : null;
}

void _debugLog(String m) {
  assert(() {
    // ignore: avoid_print
    print('[EXALTED][VERIFY] $m');
    return true;
  }());
}

/// US drug listings via the openFDA NDC Directory, matched by the exact
/// `openfda.upc` value. A listing is not proof that a particular pack is
/// genuine, approved or safe, so this never reports "Verified".
class OpenFdaNdcSource implements VerificationSource {
  OpenFdaNdcSource({
    HttpFetch? fetch,
    DateTime Function()? clock,
    this._timeout = const Duration(seconds: 12),
  }) : _fetch = fetch ?? robustHttpFetch,
       _clock = clock ?? DateTime.now;

  final HttpFetch _fetch;
  final DateTime Function() _clock;
  final Duration _timeout;

  static const _limit = 10;
  static const _aspect = 'Medicine listing';
  static const _notProof =
      'Medicine database record found. This confirms a database match only; '
      'it does not authenticate the physical package or establish '
      'regulatory approval.';

  static const sourceInfo = SourceInfo(
    id: 'openfda-ndc',
    name: 'openFDA NDC Directory',
    kind: SourceKind.official,
    authoritative: false,
    sendsData: true,
    requirement: 'No account needed. US FDA public drug listing.',
    dataSent: 'the scanned product code (UPC/GTIN) only.',
  );

  @override
  SourceInfo get info => sourceInfo;

  @override
  bool appliesTo(Interpretation interpretation) {
    final g = gtinOf(interpretation);
    return g != null && fdaUpcKey(g) != null;
  }

  SourceResult _claim(
    DateTime at,
    VerificationStatus status,
    String detail, {
    List<ScanField> fields = const [],
  }) => SourceResult(
    info: info,
    checkedAt: at,
    fields: fields,
    claims: [Claim(aspect: _aspect, status: status, detail: detail)],
  );

  static bool _isNoMatchBody(String body) {
    try {
      final j = jsonDecode(body);
      final e = j is Map ? j['error'] : null;
      return e is Map && e['code'] == 'NOT_FOUND';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SourceResult> check(Interpretation interpretation) async {
    final at = _clock();
    final code = gtinOf(interpretation);
    final key = code == null ? null : fdaUpcKey(code);
    if (key == null) {
      return _claim(
        at,
        VerificationStatus.unableToVerify,
        'This is not a UPC/GTIN that the FDA directory can be searched with, '
        'so no lookup was made.',
      );
    }
    final ndc10 = _ndc10FromKey(key);
    final uri = Uri.https('api.fda.gov', '/drug/ndc.json', {
      'search': 'openfda.upc:"$key"',
      'limit': '$_limit',
    });

    final HttpReply reply;
    try {
      reply = await _fetch(uri).timeout(_timeout);
    } on TimeoutException {
      return SourceResult.unavailable(
        info,
        at,
        'openFDA did not answer in time.',
      );
    } catch (e) {
      return SourceResult.unavailable(
        info,
        at,
        'Could not reach openFDA (${e.runtimeType}).',
      );
    }
    final status = reply.statusCode;
    _debugLog('openFDA lookup -> HTTP $status');

    if (status == 404) {
      if (_isNoMatchBody(reply.body)) {
        return _claim(
          at,
          VerificationStatus.notFound,
          'The FDA NDC Directory has no record listing this UPC/GTIN. Many '
          'products, including all non-US ones, are not listed with a UPC, '
          'so this does not mean the product is fake or unapproved.',
        );
      }
      return _claim(
        at,
        VerificationStatus.unableToVerify,
        'openFDA answered HTTP 404 without a recognisable "no match" reply.',
      );
    }
    if (status == 429) {
      return SourceResult.unavailable(
        info,
        at,
        'openFDA rate limit reached. Try again later.',
      );
    }
    if (status != 200) {
      return SourceResult.unavailable(
        info,
        at,
        'openFDA answered with HTTP $status.',
      );
    }

    Object? json;
    try {
      json = jsonDecode(reply.body);
    } catch (_) {
      json = null;
    }
    final results = json is Map ? json['results'] : null;
    if (results is! List || results.isEmpty) {
      return _claim(
        at,
        VerificationStatus.unableToVerify,
        'The openFDA reply could not be read as a list of records.',
      );
    }

    // Accept only records whose own UPC list contains the scanned code.
    final exact = <Map>[];
    for (final r in results) {
      if (r is! Map) continue;
      final of = r['openfda'];
      final upcs = of is Map ? of['upc'] : null;
      if (upcs is List && upcs.any((u) => _s(u) == key)) exact.add(r);
    }
    if (exact.isEmpty) {
      return _claim(
        at,
        VerificationStatus.mismatch,
        'openFDA returned records for this search, but none of them lists the '
        'scanned code, so nothing is shown.',
      );
    }

    // A UPC is attached to a label (SPL set), so several records can share
    // it. Prefer the one whose package list holds the NDC encoded in the code.
    Map? primary;
    Map? primaryPackage;
    if (ndc10 != null) {
      for (final r in exact) {
        final pk = r['packaging'];
        if (pk is! List) continue;
        for (final p in pk) {
          if (p is Map && _s(p['package_ndc'])?.replaceAll('-', '') == ndc10) {
            primary = r;
            primaryPackage = p;
            break;
          }
        }
        if (primary != null) break;
      }
    }
    final basis = primary == null ? exact : <Map>[primary];

    // With several candidate records, show a field only if all agree.
    String? agreed(String? Function(Map r) pick) {
      String? v;
      for (final r in basis) {
        final x = pick(r);
        if (x == null) return null;
        if (v != null && v != x) return null;
        v = x;
      }
      return v;
    }

    final values = <String, String?>{
      'Brand name': agreed((r) => _s(r['brand_name'])),
      'Generic name': agreed((r) => _s(r['generic_name'])),
      'Active ingredients': agreed(_ingredientsOf),
      'Labeler': agreed(_labelerOf),
      'Dosage form': agreed((r) => _s(r['dosage_form'])),
      'Route': agreed((r) => _listOf(r['route'])),
      'Marketing category': agreed((r) => _s(r['marketing_category'])),
      'Matched UPC': key,
      'Package NDC': primaryPackage == null
          ? null
          : _s(primaryPackage['package_ndc']),
      'Package description': primaryPackage == null
          ? null
          : _s(primaryPackage['description']),
      'Records sharing this UPC': exact.length > 1 ? '${exact.length}' : null,
      'Listing expires': agreed((r) => _s(r['listing_expiration_date'])),
      'Marketing ended': agreed((r) => _s(r['marketing_end_date'])),
    };
    final fields = <ScanField>[
      for (final e in values.entries)
        if (e.value != null)
          ScanField(
            id: 'fda.${e.key}',
            label: e.key,
            value: e.value,
            origin: FieldOrigin.external,
            note: 'From the openFDA NDC Directory.',
          ),
    ];

    final meta = json is Map ? json['meta'] : null;
    final mr = meta is Map ? meta['results'] : null;
    final total = mr is Map ? mr['total'] : null;
    final b = StringBuffer(_notProof);
    if (primaryPackage != null) {
      b.write(' Matched package NDC ${_s(primaryPackage['package_ndc'])}.');
    } else if (ndc10 != null) {
      b.write(
        ' The code is listed on this label, but none of the returned records '
        'contains the package NDC encoded in it.',
      );
    }
    if (primary == null && exact.length > 1) {
      b.write(
        ' ${exact.length} records share this UPC, so only details identical '
        'across all of them are shown.',
      );
    }
    if (total is int && total > results.length) {
      b.write(' Only the first ${results.length} of $total records were read.');
    }
    return _claim(
      at,
      VerificationStatus.recordFound,
      b.toString(),
      fields: fields,
    );
  }
}
