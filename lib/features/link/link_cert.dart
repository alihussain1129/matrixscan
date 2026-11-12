import 'dart:convert';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';

import 'link_crypto.dart';

/// The desktop's TLS identity (self-signed certificate and its key).
class LinkIdentity {
  const LinkIdentity(this.certPem, this.keyPem);
  final String certPem;
  final String keyPem;

  /// SHA-256 of the certificate. The QR code carries this so the phone can
  /// pin exactly this desktop.
  String get fingerprint => certFingerprint(certPem);
}

String certFingerprint(String pem) {
  final b64 = pem
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return sha256Hex(base64.decode(b64));
}

/// RSA key generation is slow, so it runs in a separate isolate.
Future<LinkIdentity> generateLinkIdentity(String commonName) =>
    Isolate.run(() => _generate(commonName));

LinkIdentity _generate(String cn) {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final priv = pair.privateKey as RSAPrivateKey;
  final pub = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem(
    {'CN': cn, 'O': 'Exalted'},
    priv,
    pub,
  );
  final cert = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
  return LinkIdentity(cert, CryptoUtils.encodeRSAPrivateKeyToPem(priv));
}
