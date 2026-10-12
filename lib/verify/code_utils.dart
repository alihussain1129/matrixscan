import '../interpret/interpreter.dart';

final RegExp _labelHint = RegExp(r'gtin|ean|upc|isbn|barcode', caseSensitive: false);
final RegExp _formatHint = RegExp(r'ean|upc|isbn|gtin', caseSensitive: false);

bool _gs1CheckOk(String d) {
  var sum = 0;
  final body = d.length - 1;
  for (var i = 0; i < body; i++) {
    final digit = d.codeUnitAt(body - 1 - i) - 48;
    sum += digit * (i.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == d.codeUnitAt(body) - 48;
}

/// Brings 12/13/14-digit GTINs to 13 digits where possible.
String normalizeGtin(String d) {
  if (d.length == 14 && d.startsWith('0')) return d.substring(1);
  if (d.length == 12) return '0$d';
  return d;
}

/// Finds a valid GTIN (8, 12, 13 or 14 digits) in the interpretation.
String? gtinOf(Interpretation i) {
  final plain = RegExp(r'^\d{8}$|^\d{12,14}$');
  String? tryField(bool requireLabel) {
    for (final f in i.allFields) {
      if (f.sensitive || f.id == 'errors') continue;
      if (requireLabel && !_labelHint.hasMatch('${f.id} ${f.label}')) continue;
      final String? v = f.value;
      if (v == null) continue;
      final d = v.replaceAll(RegExp(r'[\s-]'), '');
      if (plain.hasMatch(d) && _gs1CheckOk(d)) return normalizeGtin(d);
    }
    return null;
  }

  final labelled = tryField(true);
  if (labelled != null) return labelled;
  if (_formatHint.hasMatch(i.formatName)) return tryField(false);
  return null;
}

bool isBookGtin(String g) =>
    g.length == 13 && (g.startsWith('978') || g.startsWith('979'));

/// Finds a 17-character VIN (no I, O or Q; at least one letter and digit).
String? vinOf(Interpretation i) {
  final vin = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');
  for (final f in i.allFields) {
    if (f.sensitive || f.id == 'errors') continue;
    final String? v = f.value;
    if (v == null) continue;
    final s = v.trim().toUpperCase();
    if (vin.hasMatch(s) &&
        RegExp(r'[A-Z]').hasMatch(s) &&
        RegExp(r'\d').hasMatch(s)) {
      return s;
    }
  }
  return null;
}

/// Finds the first http(s) link in the interpretation.
String? urlOf(Interpretation i) {
  for (final f in i.allFields) {
    if (f.sensitive || f.id == 'errors') continue;
    final String? v = f.value;
    if (v == null) continue;
    final s = v.trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) return s;
  }
  return null;
}
