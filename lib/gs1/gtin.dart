/// Result of checking a GTIN string.
enum GtinStatus { valid, invalidLength, invalidCharacters, invalidCheckDigit }

class GtinResult {
  const GtinResult(this.value, this.status, {this.expectedCheckDigit});

  /// The input exactly as given (leading zeros preserved).
  final String value;
  final GtinStatus status;

  /// Set when [status] is [GtinStatus.invalidCheckDigit].
  final int? expectedCheckDigit;

  bool get isValid => status == GtinStatus.valid;

  /// The GTIN left-padded with zeros to 14 digits. Null unless valid.
  String? get normalized14 => isValid ? value.padLeft(14, '0') : null;

  String get label {
    switch (status) {
      case GtinStatus.valid:
        return 'GTIN Valid';
      case GtinStatus.invalidLength:
        return 'Invalid GTIN Length (${value.length})';
      case GtinStatus.invalidCharacters:
        return 'Invalid GTIN Characters';
      case GtinStatus.invalidCheckDigit:
        return 'Invalid GTIN Check Digit (expected $expectedCheckDigit)';
    }
  }
}

/// GS1 check digit for [dataDigits] (the number without its check digit).
/// The rightmost data digit has weight 3, then 1, 3, 1, ...
int gs1CheckDigit(String dataDigits) {
  var sum = 0;
  for (var i = dataDigits.length - 1; i >= 0; i--) {
    final digit = dataDigits.codeUnitAt(i) - 0x30;
    final fromRight = dataDigits.length - 1 - i;
    sum += digit * (fromRight.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10;
}

const Set<int> _gtinLengths = {8, 12, 13, 14};
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

/// Checks structure and check digit only. A valid result says nothing about
/// whether the product exists or is genuine.
GtinResult validateGtin(String value) {
  if (value.isNotEmpty && !_digitsOnly.hasMatch(value)) {
    return GtinResult(value, GtinStatus.invalidCharacters);
  }
  if (!_gtinLengths.contains(value.length)) {
    return GtinResult(value, GtinStatus.invalidLength);
  }
  final data = value.substring(0, value.length - 1);
  final expected = gs1CheckDigit(data);
  final actual = value.codeUnitAt(value.length - 1) - 0x30;
  if (expected != actual) {
    return GtinResult(
      value,
      GtinStatus.invalidCheckDigit,
      expectedCheckDigit: expected,
    );
  }
  return GtinResult(value, GtinStatus.valid);
}