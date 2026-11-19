import '../../gs1/gs1_parser.dart';
import '../../gs1/gtin.dart';

/// Null when the GTIN is valid (length, digits, check digit), otherwise a
/// short reason. Uses the existing GS1 validator.
String? gtinProblem(String gtin) {
  final r = validateGtin(gtin);
  return r.isValid ? null : r.label;
}

final RegExp _printable = RegExp(r'^[\x21-\x7E]+$');

/// GS1 AI 21 (serial): 1 to 20 printable characters.
String? serialProblem(String serial) {
  if (serial.isEmpty || serial.length > 20) {
    return 'Serial must be 1-20 characters, got ${serial.length}';
  }
  if (!_printable.hasMatch(serial)) {
    return 'Serial contains unsupported characters';
  }
  return null;
}

/// GS1 AI 10 (batch/lot): 1 to 20 printable characters.
String? lotProblem(String lot) {
  if (lot.isEmpty || lot.length > 20) {
    return 'Lot must be 1-20 characters, got ${lot.length}';
  }
  if (!_printable.hasMatch(lot)) {
    return 'Lot contains unsupported characters';
  }
  return null;
}

/// Builds a GS1 element string: (01) GTIN-14, (17) expiry, (10) lot,
/// (21) serial. Fixed-length fields come first. A group separator follows
/// the lot only when a serial comes after it. Throws [ArgumentError] on bad
/// input.
String buildGs1ElementString({
  required String gtin,
  String? lot,
  DateTime? expiry,
  String? serial,
}) {
  final g = validateGtin(gtin);
  if (!g.isValid) throw ArgumentError(g.label);
  if (lot != null) {
    final p = lotProblem(lot);
    if (p != null) throw ArgumentError(p);
  }
  if (serial != null) {
    final p = serialProblem(serial);
    if (p != null) throw ArgumentError(p);
  }
  final b = StringBuffer('01${g.normalized14}');
  if (expiry != null) {
    String two(int n) => n.toString().padLeft(2, '0');
    b.write('17${two(expiry.year % 100)}${two(expiry.month)}${two(expiry.day)}');
  }
  if (lot != null) {
    b.write('10$lot');
    if (serial != null) b.write(gs1GroupSeparator);
  }
  if (serial != null) b.write('21$serial');
  return b.toString();
}
