import 'dart:convert';
import 'dart:io';

import 'link_crypto.dart';
import 'link_models.dart';

class PairingOffer {
  PairingOffer(this.token, this.expiresAt);
  final String token;
  final DateTime expiresAt;
}

/// Temporary pairing tokens: random, short-lived and usable once.
class PairingManager {
  PairingManager({
    this.ttl = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, DateTime> _open = {};
  int _fails = 0;
  DateTime? _lockedUntil;

  bool get hasOpenOffer {
    _prune();
    return _open.isNotEmpty;
  }

  PairingOffer create() {
    _prune();
    final token = randomToken();
    final exp = _clock().add(ttl);
    _open[token] = exp;
    return PairingOffer(token, exp);
  }

  /// True only for a known, unexpired token. The token is spent either way,
  /// so it can never be tried twice. Many wrong tries lock pairing for 1 min.
  bool consume(String token) {
    final now = _clock();
    if (_lockedUntil != null && now.isBefore(_lockedUntil!)) return false;
    _prune();
    final exp = _open.remove(token);
    final ok = exp != null && now.isBefore(exp);
    if (ok) {
      _fails = 0;
    } else {
      _fails++;
      if (_fails >= 8) {
        _lockedUntil = now.add(const Duration(minutes: 1));
        _fails = 0;
      }
    }
    return ok;
  }

  void cancelAll() => _open.clear();

  void _prune() {
    final now = _clock();
    _open.removeWhere((_, exp) => !now.isBefore(exp));
  }
}

/// What the QR code contains. No permanent secret is in it.
class PairingPayload {
  PairingPayload({
    required this.hosts,
    required this.port,
    required this.fingerprint,
    required this.token,
    required this.expiresAt,
    required this.desktopName,
  });

  final List<String> hosts;
  final int port;
  final String fingerprint;
  final String token;
  final DateTime expiresAt;
  final String desktopName;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  String encode() => jsonEncode({
    'v': 1,
    'app': 'exalted',
    'hosts': hosts,
    'port': port,
    'fp': fingerprint,
    'token': token,
    'exp': expiresAt.millisecondsSinceEpoch,
    'name': desktopName,
  });

  static PairingPayload parse(String raw) {
    LinkException bad() =>
        LinkException('bad_qr', 'This is not an Exalted pairing code.');
    Object? j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      throw bad();
    }
    if (j is! Map || j['app'] != 'exalted' || j['v'] != 1) throw bad();
    final hosts = j['hosts'];
    final port = j['port'];
    final fp = j['fp'];
    final token = j['token'];
    final exp = j['exp'];
    if (hosts is! List || hosts.isEmpty || hosts.length > 8) throw bad();
    final hostList = <String>[];
    for (final h in hosts) {
      if (h is! String || InternetAddress.tryParse(h) == null) throw bad();
      hostList.add(h);
    }
    if (port is! int || port < 1 || port > 65535) throw bad();
    if (fp is! String || !isSha256Hex(fp)) throw bad();
    if (token is! String || token.length < 16 || token.length > 128) {
      throw bad();
    }
    if (exp is! int) throw bad();
    return PairingPayload(
      hosts: hostList,
      port: port,
      fingerprint: fp,
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp),
      desktopName: (j['name'] as String?) ?? 'Desktop',
    );
  }
}

/// Only local-network callers are served.
bool isPrivateAddress(InternetAddress a) {
  if (a.isLoopback) return true;
  final b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4 && b.length == 4) {
    if (b[0] == 10) return true;
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
    if (b[0] == 192 && b[1] == 168) return true;
    if (b[0] == 169 && b[1] == 254) return true;
    return false;
  }
  if (b.length == 16) {
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return true;
    if ((b[0] & 0xfe) == 0xfc) return true;
  }
  return false;
}

Future<List<String>> localIPv4Addresses() async {
  final out = <String>[];
  try {
    for (final ni in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final a in ni.addresses) {
        if (!a.isLoopback && isPrivateAddress(a)) out.add(a.address);
      }
    }
  } catch (_) {}
  return out;
}
