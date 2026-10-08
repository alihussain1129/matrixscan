/// How a Wi-Fi network is secured.
enum WifiSecurity { open, wep, wpa, wpa3, unsupported }

/// A Wi-Fi network described by a "WIFI:S:...;T:...;P:...;;" QR code.
class WifiNetworkInfo {
  const WifiNetworkInfo({
    required this.ssid,
    required this.security,
    required this.password,
    required this.hidden,
  });

  /// Network name.
  final String ssid;
  final WifiSecurity security;

  /// Empty for open networks.
  final String password;
  final bool hidden;

  /// False for enterprise or unknown security, and for a secured network that
  /// came without a password.
  bool get canConnect {
    switch (security) {
      case WifiSecurity.open:
        return true;
      case WifiSecurity.wep:
      case WifiSecurity.wpa:
      case WifiSecurity.wpa3:
        return password.isNotEmpty;
      case WifiSecurity.unsupported:
        return false;
    }
  }

  String get securityLabel {
    switch (security) {
      case WifiSecurity.open:
        return 'Open (no password)';
      case WifiSecurity.wep:
        return 'WEP';
      case WifiSecurity.wpa:
        return 'WPA/WPA2';
      case WifiSecurity.wpa3:
        return 'WPA3';
      case WifiSecurity.unsupported:
        return 'Unsupported security';
    }
  }
}

/// Reads up to the first unescaped [stop1] or [stop2]. Escape pairs are kept
/// as written so they can be decoded afterwards.
(String, int) _scan(String s, int start, String stop1, [String? stop2]) {
  final raw = StringBuffer();
  var i = start;
  while (i < s.length) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      raw
        ..write(c)
        ..write(s[i + 1]);
      i += 2;
      continue;
    }
    if (c == stop1 || c == stop2) break;
    raw.write(c);
    i++;
  }
  return (raw.toString(), i);
}

String _unescape(String raw) {
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (raw[i] == r'\' && i + 1 < raw.length) {
      out.write(raw[i + 1]);
      i++;
    } else {
      out.write(raw[i]);
    }
  }
  return out.toString();
}

/// A value in double quotes is taken literally, without the quotes.
String _fieldValue(String raw) {
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    return _unescape(raw.substring(1, raw.length - 1));
  }
  return _unescape(raw);
}

/// Parses Wi-Fi QR text such as `WIFI:S:Network;T:WPA;P:Password;;`.
/// Returns null when [text] is not a Wi-Fi code or has no network name.
WifiNetworkInfo? parseWifiQr(String text) {
  final value = text.trim();
  if (value.length < 5 || value.substring(0, 5).toUpperCase() != 'WIFI:') {
    return null;
  }

  final fields = <String, String>{};
  var i = 5;
  while (i < value.length) {
    final (rawKey, afterKey) = _scan(value, i, ':', ';');
    i = afterKey;
    if (i >= value.length) break;
    if (value[i] == ';') {
      // An empty field, such as the closing ";;".
      i++;
      continue;
    }
    i++; // the ':'
    final (rawValue, afterValue) = _scan(value, i, ';');
    i = afterValue;
    if (i < value.length) i++; // the ';'
    fields.putIfAbsent(
      _unescape(rawKey).trim().toUpperCase(),
      () => _fieldValue(rawValue),
    );
  }

  final ssid = fields['S'];
  if (ssid == null || ssid.isEmpty) return null;

  final password = fields['P'] ?? '';
  final type = (fields['T'] ?? '').trim().toUpperCase();
  final security = switch (type) {
    '' => password.isEmpty ? WifiSecurity.open : WifiSecurity.wpa,
    'NOPASS' => WifiSecurity.open,
    'WEP' => WifiSecurity.wep,
    'WPA' ||
    'WPA2' ||
    'WPA/WPA2' ||
    'WPA2-PSK' ||
    'WPA-PSK' => WifiSecurity.wpa,
    'SAE' || 'WPA3' => WifiSecurity.wpa3,
    _ => WifiSecurity.unsupported,
  };

  return WifiNetworkInfo(
    ssid: ssid,
    security: security,
    password: security == WifiSecurity.open ? '' : password,
    hidden: (fields['H'] ?? '').trim().toLowerCase() == 'true',
  );
}
