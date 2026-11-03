/// One GS1 element: application identifier and value.
class Gs1Field {
  const Gs1Field(this.ai, this.value);

  final String ai;
  final String value;

  String get label => Gs1Fields.labels[ai] ?? 'AI $ai';

  /// The value as people read it (dates become YYYY-MM-DD).
  String get display => Gs1Fields.dateAis.contains(ai)
      ? (Gs1Fields.formatDate(value) ?? value)
      : value;
}

/// Reads the human-readable GS1 form the decoder reports, for example
/// `(01)09504000059101(21)19067811811(10)563GS1(17)200331`.
class Gs1Fields {
  const Gs1Fields._();

  static final RegExp _element = RegExp(r'\((\d{2,4})\)([^()]*)');

  static const Set<String> dateAis = {'11', '12', '13', '15', '16', '17'};

  static const Map<String, String> labels = {
    '00': 'SSCC',
    '01': 'GTIN',
    '02': 'Content GTIN',
    '10': 'Batch / Lot',
    '11': 'Production date',
    '12': 'Due date',
    '13': 'Packaging date',
    '15': 'Best before',
    '16': 'Sell by',
    '17': 'Expiry',
    '20': 'Variant',
    '21': 'Serial number',
    '30': 'Count',
    '37': 'Count of units',
    '240': 'Additional ID',
    '241': 'Customer part number',
    '250': 'Secondary serial',
  };

  /// Empty when [text] is not in the parenthesised GS1 form.
  static List<Gs1Field> parse(String text) {
    final t = text.trimLeft();
    if (!t.startsWith('(')) return const [];
    return [
      for (final m in _element.allMatches(t))
        Gs1Field(m.group(1)!, m.group(2)!.trim()),
    ];
  }

  /// YYMMDD to a date. Day 00 means "end of that month". Null when invalid.
  static DateTime? parseDate(String v, {DateTime? now}) {
    if (!RegExp(r'^\d{6}$').hasMatch(v)) return null;
    final yy = int.parse(v.substring(0, 2));
    final mm = int.parse(v.substring(2, 4));
    final dd = int.parse(v.substring(4, 6));
    if (mm < 1 || mm > 12) return null;
    final current = (now ?? DateTime.now()).year;
    var year = 2000 + yy;
    if (year - current > 50) year -= 100;
    final last = DateTime(year, mm + 1, 0).day;
    if (dd == 0) return DateTime(year, mm, last);
    if (dd > last) return null;
    return DateTime(year, mm, dd);
  }

  static String? formatDate(String v, {DateTime? now}) {
    final d = parseDate(v, now: now);
    if (d == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    final month = '${d.year}-${two(d.month)}';
    return v.substring(4) == '00' ? month : '$month-${two(d.day)}';
  }

  /// GS1 check digit for GTIN-8/12/13/14.
  static bool gtinIsValid(String s) {
    if (!RegExp(r'^\d+$').hasMatch(s) || !{8, 12, 13, 14}.contains(s.length)) {
      return false;
    }
    var sum = 0;
    for (var i = 0; i < s.length - 1; i++) {
      final digit = s.codeUnitAt(s.length - 2 - i) - 48;
      sum += digit * (i.isEven ? 3 : 1);
    }
    return (10 - sum % 10) % 10 == s.codeUnitAt(s.length - 1) - 48;
  }
}
