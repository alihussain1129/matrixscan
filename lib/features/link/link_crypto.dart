import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final Random _rng = Random.secure();

Uint8List randomBytes(int n) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = _rng.nextInt(256);
  }
  return out;
}

/// URL-safe random token from the system secure random generator.
String randomToken([int bytes = 24]) =>
    base64Url.encode(randomBytes(bytes)).replaceAll('=', '');

String sha256Hex(List<int> data) => sha256.convert(data).toString();

final RegExp _shaRe = RegExp(r'^[0-9a-f]{64}$');
bool isSha256Hex(String s) => _shaRe.hasMatch(s);

/// JSON with sorted keys, so the same data always gives the same hash.
String canonicalJson(Object? v) => jsonEncode(_canon(v));

Object? _canon(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canon(v[k])};
  }
  if (v is List) return [for (final e in v) _canon(e)];
  return v;
}

String pathAndQuery(Uri u) => u.hasQuery ? '${u.path}?${u.query}' : u.path;

String signRequest(
  List<int> secret,
  String method,
  String target,
  int ts,
  String nonce,
  String bodyHash,
) {
  final msg = '$method\n$target\n$ts\n$nonce\n$bodyHash';
  return Hmac(sha256, secret).convert(utf8.encode(msg)).toString();
}

bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return d == 0;
}
