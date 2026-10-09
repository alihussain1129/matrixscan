import '../interpret/interpreter.dart';
import '../interpret/scan_field.dart';

/// The outcome of one check. A check says only what it actually established.
enum VerificationStatus {
  verified('Verified'),
  validFormat('Valid format'),
  invalidFormat('Invalid format'),
  recordFound('Record found'),
  mismatch('Mismatch'),
  expired('Expired'),
  recalled('Recalled'),
  outdated('Outdated'),
  notFound('Not found'),
  sourceUnavailable('Source unavailable'),
  unableToVerify('Unable to verify');

  const VerificationStatus(this.label);
  final String label;

  bool get isProblem =>
      this == invalidFormat ||
      this == mismatch ||
      this == expired ||
      this == recalled ||
      this == outdated;
}

enum SourceKind {
  local('Local check'),
  official('Official source'),
  manufacturer('Manufacturer source'),
  industry('Industry source'),
  community('Community source'),
  financial('Financial provider');

  const SourceKind(this.label);
  final String label;
}

class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.name,
    required this.kind,
    this.authoritative = false,
    this.sendsData = false,
    this.requirement = 'No account or credentials needed.',
    this.dataSent = 'Nothing leaves the device.',
  });

  final String id;
  final String name;
  final SourceKind kind;

  /// Only authoritative sources may produce [VerificationStatus.verified].
  final bool authoritative;

  /// True when the check contacts a server. Needs the user's consent.
  final bool sendsData;
  final String requirement;
  final String dataSent;
}

/// One statement a source makes about the scanned item.
class Claim {
  const Claim({
    required this.aspect,
    required this.status,
    this.value,
    this.detail,
    this.dataUpdatedAt,
  });

  final String aspect;
  final VerificationStatus status;

  /// The value the source reports, used to compare sources.
  final String? value;
  final String? detail;
  final DateTime? dataUpdatedAt;

  Claim withStatus(VerificationStatus s, String? d) => Claim(
    aspect: aspect,
    status: s,
    value: value,
    detail: d,
    dataUpdatedAt: dataUpdatedAt,
  );
}

class SourceResult {
  SourceResult({
    required this.info,
    required this.checkedAt,
    this.claims = const [],
    this.fields = const [],
    this.dataUpdatedAt,
    this.error,
  });

  factory SourceResult.unavailable(
    SourceInfo info,
    DateTime at,
    String reason,
  ) => SourceResult(
    info: info,
    checkedAt: at,
    error: reason,
    claims: [
      Claim(
        aspect: 'Source check',
        status: VerificationStatus.sourceUnavailable,
        detail: reason,
      ),
    ],
  );

  final SourceInfo info;
  final DateTime checkedAt;
  final List<Claim> claims;

  /// Information the source supplied that is not in the barcode.
  final List<ScanField> fields;
  final DateTime? dataUpdatedAt;
  final String? error;
}

abstract class VerificationSource {
  SourceInfo get info;

  /// Cheap, offline decision on whether this source is relevant.
  bool appliesTo(Interpretation interpretation);

  Future<SourceResult> check(Interpretation interpretation);
}