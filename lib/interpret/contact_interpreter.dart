import 'interpreter.dart';
import 'scan_field.dart';

const Map<String, String> _vcardLabels = {
  'FN': 'Full name',
  'N': 'Name',
  'ORG': 'Organization',
  'TITLE': 'Job title',
  'TEL': 'Phone',
  'EMAIL': 'Email',
  'ADR': 'Address',
  'URL': 'Website',
  'NOTE': 'Note',
  'BDAY': 'Birthday',
  'NICKNAME': 'Nickname',
};

const Map<String, String> _mecardLabels = {
  'N': 'Name',
  'TEL': 'Phone',
  'TEL-AV': 'Phone (video)',
  'EMAIL': 'Email',
  'URL': 'Website',
  'NOTE': 'Note',
  'BDAY': 'Birthday',
  'ADR': 'Address',
  'NICKNAME': 'Nickname',
  'SOUND': 'Name pronunciation',
};

/// vCard and MECARD contact codes. Nothing is saved to the phone by this.
class ContactInterpreter implements PayloadInterpreter {
  @override
  String get id => 'contact';

  @override
  Interpretation? interpret(ScanPayload payload) {
    final text = payload.raw.trim();
    final upper = text.toUpperCase();
    if (upper.startsWith('BEGIN:VCARD')) return _vcard(text);
    if (upper.startsWith('MECARD:')) return _mecard(text);
    return null;
  }
}

Interpretation _vcard(String text) {
  final fields = <ScanField>[];
  String? version;
  for (final (name, raw) in _vcardProperties(text)) {
    if (name == 'BEGIN' || name == 'END') continue;
    if (name == 'VERSION') {
      version = raw;
      continue;
    }
    final label = _vcardLabels[name];
    if (label == null) {
      fields.add(_unknownField(name, raw));
      continue;
    }
    final value = switch (name) {
      'N' => _vcardName(raw),
      'ORG' || 'ADR' => _joinParts(raw, ';', vcard: true),
      _ => _unescape(raw, vcard: true),
    };
    fields.add(_field(name, label, value, raw, 'vCard'));
  }
  return _build('vCard contact', fields, version == null ? null : 'vCard version $version');
}

Interpretation _mecard(String text) {
  final fields = <ScanField>[];
  for (final item in _splitUnescaped(text.substring(7), ';')) {
    final colon = item.indexOf(':');
    if (item.isEmpty || colon <= 0) continue;
    final key = item.substring(0, colon).toUpperCase();
    final raw = item.substring(colon + 1);
    final label = _mecardLabels[key];
    if (label == null) {
      fields.add(_unknownField(key, raw));
      continue;
    }
    final value = switch (key) {
      'N' => _mecardName(raw),
      'ADR' => _joinParts(raw, ',', vcard: false),
      _ => _unescape(raw, vcard: false),
    };
    fields.add(_field(key, label, value, raw, 'MECARD'));
  }
  return _build('MECARD contact', fields, null);
}

ScanField _field(String id, String label, String value, String raw, String std) =>
    ScanField(
      id: id,
      label: label,
      value: value.isEmpty ? null : value,
      original: raw,
      standard: std,
      presence: value.isEmpty ? FieldPresence.empty : FieldPresence.present,
    );

ScanField _unknownField(String name, String raw) {
  const max = 120;
  final long = raw.length > max;
  return ScanField(
    id: name,
    label: 'Other: $name',
    value: long ? '${raw.substring(0, max)}...' : raw,
    original: long ? raw : null,
    note: 'Not interpreted by EXALTED; kept as encoded.',
  );
}

Interpretation _build(String format, List<ScanField> fields, String? version) {
  bool has(String label) => fields.any((f) => f.label == label);
  return Interpretation(
    interpreterId: 'contact',
    formatName: format,
    warnings: const [
      'Details are as written in the code and are not verified.',
    ],
    sections: [
      ScanSection(
        id: 'contact',
        title: 'Contact card',
        fields: [
          ...fields,
          if (!has('Full name') && !has('Name'))
            const ScanField.notPresent('Name', id: 'name'),
          if (!has('Phone')) const ScanField.notPresent('Phone', id: 'tel'),
          if (!has('Email')) const ScanField.notPresent('Email', id: 'email'),
          if (version != null)
            ScanField(id: 'version', label: 'Format version', value: version),
        ],
      ),
    ],
  );
}

List<(String, String)> _vcardProperties(String text) {
  final unfolded = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n[ \t]'), '');
  final out = <(String, String)>[];
  for (final line in unfolded.split('\n')) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    var name = line.substring(0, colon);
    final semi = name.indexOf(';');
    if (semi >= 0) name = name.substring(0, semi);
    final dot = name.indexOf('.');
    if (dot >= 0) name = name.substring(dot + 1);
    out.add((name.trim().toUpperCase(), line.substring(colon + 1)));
  }
  return out;
}

String _vcardName(String raw) {
  final p = _splitUnescaped(raw, ';').map((s) => _unescape(s, vcard: true)).toList();
  String at(int i) => i < p.length ? p[i] : '';
  return [at(3), at(1), at(2), at(0), at(4)].where((s) => s.isNotEmpty).join(' ');
}

String _mecardName(String raw) {
  final p = _splitUnescaped(raw, ',').map((s) => _unescape(s, vcard: false)).toList();
  if (p.length >= 2 && p[0].isNotEmpty && p[1].isNotEmpty) {
    return '${p[1]} ${p[0]}';
  }
  return p.where((s) => s.isNotEmpty).join(' ');
}

String _joinParts(String raw, String sep, {required bool vcard}) =>
    _splitUnescaped(raw, sep)
        .map((s) => _unescape(s, vcard: vcard))
        .where((s) => s.isNotEmpty)
        .join(', ');

List<String> _splitUnescaped(String s, String sep) {
  final parts = <String>[];
  final cur = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      cur
        ..write(c)
        ..write(s[i + 1]);
      i++;
      continue;
    }
    if (c == sep) {
      parts.add(cur.toString());
      cur.clear();
      continue;
    }
    cur.write(c);
  }
  parts.add(cur.toString());
  return parts;
}

String _unescape(String s, {required bool vcard}) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      final n = s[i + 1];
      i++;
      out.write(vcard && (n == 'n' || n == 'N') ? '\n' : n);
    } else {
      out.write(c);
    }
  }
  return out.toString();
}