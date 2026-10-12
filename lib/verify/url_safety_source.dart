import '../interpret/interpreter.dart';
import 'code_utils.dart';
import 'verification.dart';

/// Offline checks of web links found in a scan. No reputation lookup.
class UrlSafetySource implements VerificationSource {
  static const sourceInfo = SourceInfo(
    id: 'local-url',
    name: 'Local link checks',
    kind: SourceKind.local,
  );

  static const _shorteners = {
    'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'is.gd', 'ow.ly', 'buff.ly',
    'cutt.ly', 'rebrand.ly', 'shorturl.at', 'tiny.cc',
  };

  @override
  SourceInfo get info => sourceInfo;

  @override
  bool appliesTo(Interpretation interpretation) => urlOf(interpretation) != null;

  @override
  Future<SourceResult> check(Interpretation interpretation) async {
    final raw = urlOf(interpretation);
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      return SourceResult(
        info: info,
        checkedAt: DateTime.now(),
        claims: const [
          Claim(
            aspect: 'Link checks',
            status: VerificationStatus.invalidFormat,
            detail: 'The link could not be read as a valid web address.',
          ),
        ],
      );
    }
    final host = uri.host.toLowerCase();
    final flags = <String>[];
    if (uri.scheme == 'http') flags.add('uses unencrypted HTTP');
    if (uri.userInfo.isNotEmpty) {
      flags.add('contains a user name part that can hide the real site');
    }
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':')) {
      flags.add('points to a raw IP address');
    }
    if (host.split('.').any((p) => p.startsWith('xn--'))) {
      flags.add('uses look-alike (punycode) characters');
    }
    if (_shorteners.contains(host)) {
      flags.add('is a link shortener, so the real destination is hidden');
    }
    if (host.split('.').length > 4) flags.add('has unusually many subdomains');
    if (uri.hasPort && uri.port != 80 && uri.port != 443) {
      flags.add('uses an unusual port');
    }

    final clean = flags.isEmpty;
    return SourceResult(
      info: info,
      checkedAt: DateTime.now(),
      claims: [
        Claim(
          aspect: 'Link checks ($host)',
          status: clean
              ? VerificationStatus.validFormat
              : VerificationStatus.unableToVerify,
          detail: clean
              ? 'No warning signs in the address itself. This is not a '
                    'reputation check, so the site may still be unsafe.'
              : 'Caution: the link ${flags.join('; ')}. Open it only if you '
                    'trust where the code came from.',
        ),
      ],
    );
  }
}
