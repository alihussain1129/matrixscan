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

/// VIN decoding via the US NHTSA vPIC service.
class NhtsaVinSource implements VerificationSource {
  NhtsaVinSource({HttpFetch? fetch, DateTime Function()? clock})
    : _fetch = fetch ?? robustHttpFetch,
      _clock = clock ?? DateTime.now;

  final HttpFetch _fetch;
  final DateTime Function() _clock;

  static const sourceInfo = SourceInfo(
    id: 'nhtsa-vpic',
    name: 'NHTSA VIN decoder',
    kind: SourceKind.official,
    sendsData: true,
    requirement: 'No account needed. Best for vehicles sold in the US.',
    dataSent: 'the VIN only.',
  );

  @override
  SourceInfo get info => sourceInfo;

  @override
  bool appliesTo(Interpretation interpretation) => vinOf(interpretation) != null;

  @override
  Future<SourceResult> check(Interpretation interpretation) async {
    final at = _clock();
    final vin = vinOf(interpretation);
    if (vin == null) {
      return SourceResult.unavailable(info, at, 'No VIN available.');
    }
    final uri = Uri.https(
      'vpic.nhtsa.dot.gov',
      '/api/vehicles/DecodeVinValues/$vin',
      {'format': 'json'},
    );
    final HttpReply reply;
    try {
      reply = await _fetch(uri);
    } catch (e) {
      return SourceResult.unavailable(
        info,
        at,
        'Could not reach NHTSA (${e.runtimeType}).',
      );
    }
    if (reply.statusCode != 200) {
      return SourceResult.unavailable(
        info,
        at,
        'NHTSA answered with HTTP ${reply.statusCode}.',
      );
    }
    Object? json;
    try {
      json = jsonDecode(reply.body);
    } catch (_) {
      json = null;
    }
    final results = json is Map ? json['Results'] : null;
    final row = results is List && results.isNotEmpty ? results.first : null;
    if (row is! Map) {
      return SourceResult.unavailable(
        info,
        at,
        'NHTSA returned an unreadable answer.',
      );
    }
    final make = _s(row['Make']);
    final errorText = _s(row['ErrorText']);
    if (make == null) {
      return SourceResult(
        info: info,
        checkedAt: at,
        claims: [
          Claim(
            aspect: 'VIN decode',
            status: VerificationStatus.unableToVerify,
            detail:
                'NHTSA could not decode this VIN${errorText == null ? '' : ': $errorText'}. '
                'Non-US vehicles are often not covered.',
          ),
        ],
      );
    }
    ScanField f(String label, Object? v) => ScanField(
      id: 'nhtsa.$label',
      label: label,
      value: _s(v),
      origin: FieldOrigin.external,
    );
    final clean = _s(row['ErrorCode']) == '0';
    return SourceResult(
      info: info,
      checkedAt: at,
      fields: [
        f('Make', row['Make']),
        f('Model', row['Model']),
        f('Model year', row['ModelYear']),
        f('Vehicle type', row['VehicleType']),
        f('Body class', row['BodyClass']),
        f('Plant country', row['PlantCountry']),
      ].where((e) => e.value != null).toList(),
      claims: [
        Claim(
          aspect: 'VIN decode',
          status: VerificationStatus.recordFound,
          detail:
              'The VIN decodes to the details shown.'
              '${clean ? '' : ' NHTSA reported: ${errorText ?? 'a data warning'}.'} '
              'Decoding does not prove this specific vehicle exists.',
        ),
      ],
    );
  }
}
