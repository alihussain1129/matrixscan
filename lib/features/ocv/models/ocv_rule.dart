/// Supported industrial Optical Character Verification (OCV) inspection rule types.
enum OcvRuleType {
  /// Regular expression match.
  regex,

  /// Exact string comparison (with optional case sensitivity).
  exactMatch,

  /// Standard manufacturing lot code pattern (e.g. LOT-XXXXXXXX).
  lotCode,

  /// Expiry date format check and validity verification (must be in future).
  expiryDate,

  /// Component serial number with format and length constraints.
  serialNumber,

  /// Numerical range validation (e.g. batch number between min and max).
  numericRange,
}

/// An industrial OCV verification rule used to validate OCR-extracted text
/// on production lines, packaging, stamped parts, and labels.
class OcvRule {
  const OcvRule({
    required this.id,
    required this.name,
    required this.type,
    required this.pattern,
    this.minConfidence = 0.65,
    this.caseSensitive = false,
    this.expectedPrefix,
    this.expectedSuffix,
    this.minNumber,
    this.maxNumber,
    this.dateWithinDays,
    this.description = '',
  });

  final String id;
  final String name;
  final OcvRuleType type;
  final String pattern;
  final double minConfidence;
  final bool caseSensitive;
  final String? expectedPrefix;
  final String? expectedSuffix;
  final num? minNumber;
  final num? maxNumber;
  final int? dateWithinDays;
  final String description;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'pattern': pattern,
        'minConfidence': minConfidence,
        'caseSensitive': caseSensitive,
        'expectedPrefix': expectedPrefix,
        'expectedSuffix': expectedSuffix,
        'minNumber': minNumber,
        'maxNumber': maxNumber,
        'dateWithinDays': dateWithinDays,
        'description': description,
      };

  static OcvRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final typeName = json['type'];
    final pattern = json['pattern'];

    if (id is! String || name is! String || typeName is! String || pattern is! String) {
      return null;
    }

    final type = OcvRuleType.values.asNameMap()[typeName] ?? OcvRuleType.regex;
    final minConf = (json['minConfidence'] as num?)?.toDouble() ?? 0.65;
    final caseSens = json['caseSensitive'] == true;
    final prefix = json['expectedPrefix'] as String?;
    final suffix = json['expectedSuffix'] as String?;
    final minNum = json['minNumber'] as num?;
    final maxNum = json['maxNumber'] as num?;
    final dateDays = (json['dateWithinDays'] as num?)?.toInt();
    final desc = json['description'] is String ? json['description'] as String : '';

    return OcvRule(
      id: id,
      name: name,
      type: type,
      pattern: pattern,
      minConfidence: minConf,
      caseSensitive: caseSens,
      expectedPrefix: prefix,
      expectedSuffix: suffix,
      minNumber: minNum,
      maxNumber: maxNum,
      dateWithinDays: dateDays,
      description: desc,
    );
  }

  /// Preset standard industrial inspection rules.
  static List<OcvRule> presets() => [
        const OcvRule(
          id: 'rule_pharma_lot',
          name: 'Pharmaceutical Lot Number',
          type: OcvRuleType.lotCode,
          pattern: r'LOT[:\s-]*[A-Z0-9]{6,12}',
          description: 'Validates standard 6-12 character alphanumeric batch/lot identifiers.',
        ),
        const OcvRule(
          id: 'rule_expiry_mmyyyy',
          name: 'Expiration Date (MM/YYYY)',
          type: OcvRuleType.expiryDate,
          pattern: r'(0[1-9]|1[0-2])[\/\.-]20\d{2}',
          description: 'Validates that date is valid MM/YYYY format and has not expired.',
        ),
        const OcvRule(
          id: 'rule_automotive_vin',
          name: 'Automotive Serial (17-char VIN/DIN)',
          type: OcvRuleType.serialNumber,
          pattern: r'[A-HJ-NPR-Z0-9]{17}',
          caseSensitive: false,
          description: 'Validates 17-character ISO standard automotive vehicle or chassis serials.',
        ),
        const OcvRule(
          id: 'rule_industrial_batch',
          name: 'Industrial Batch Code',
          type: OcvRuleType.regex,
          pattern: r'B[0-9]{4}-[A-Z]{2}',
          description: 'Standard factory batch format B####-XX.',
        ),
      ];
}
