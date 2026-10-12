import 'dart:convert';

import '../interpret/interpreter.dart';
import '../interpret/scan_field.dart';
import 'code_utils.dart';
import 'http_client.dart';
import 'verification.dart';

String? _s(Object? v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

ScanField _f(String id, String label, String? value) => ScanField(
  id: id,
  label: label,
  value: value,
  origin: FieldOrigin.external,
);

/// Books by ISBN-13 (EAN barcodes starting 978/979) via Open Library.
class OpenLibrarySource implements VerificationSource {
  OpenLibrarySource({HttpFetch? fetch, DateTime Function()? clock})
    : _fetch = fetch ?? robustHttpFetch,
      _clock = clock ?? DateTime.now;

  final HttpFetch _fetch;
  final DateTime Function() _clock;

  static const sourceInfo = SourceInfo(
    id: 'openlibrary',
    name: 'Open Library',
    kind: SourceKind.community,
    sendsData: true,
    requirement: 'No account needed. Public book catalogue.',
    dataSent: 'the ISBN only.',
  );

  @override
  SourceInfo get info => sourceInfo;

  @override
  bool appliesTo(Interpretation interpretation) {
    final g = gtinOf(interpretation);
    return g != null && isBookGtin(g);
  }

  @override
  Future<SourceResult> check(Interpretation interpretation) async {
    final at = _clock();
    final isbn = gtinOf(interpretation);
    if (isbn == null) {
      return SourceResult.unavailable(info, at, 'No ISBN available.');
    }
    final uri = Uri.https('openlibrary.org', '/api/books', {
      'bibkeys': 'ISBN:$isbn',
      'format': 'json',
      'jscmd': 'data',
    });
    final HttpReply reply;
    try {
      reply = await _fetch(uri);
    } catch (e) {
      return SourceResult.unavailable(
        info,
        at,
        'Could not reach Open Library (${e.runtimeType}).',
      );
    }
    if (reply.statusCode != 200) {
      return SourceResult.unavailable(
        info,
        at,
        'Open Library answered with HTTP ${reply.statusCode}.',
      );
    }
    Object? json;
    try {
      json = jsonDecode(reply.body);
    } catch (_) {
      json = null;
    }
    if (json is! Map) {
      return SourceResult.unavailable(
        info,
        at,
        'Open Library returned an unreadable answer.',
      );
    }
    final book = json['ISBN:$isbn'];
    if (book is! Map) {
      return SourceResult(
        info: info,
        checkedAt: at,
        claims: const [
          Claim(
            aspect: 'Book record',
            status: VerificationStatus.notFound,
            detail:
                'Open Library has no record for this ISBN. Many valid books '
                'are missing from it.',
          ),
        ],
      );
    }
    String? names(Object? list) {
      if (list is! List) return null;
      final n = [
        for (final e in list)
          if (e is Map && _s(e['name']) != null) _s(e['name'])!,
      ];
      return n.isEmpty ? null : n.join(', ');
    }

    final fields = <ScanField>[
      for (final e in {
        'Title': _s(book['title']),
        'Authors': names(book['authors']),
        'Publisher': names(book['publishers']),
        'Published': _s(book['publish_date']),
        'Pages': _s(book['number_of_pages']),
        'Open Library page': _s(book['url']),
      }.entries)
        if (e.value != null) _f('openlibrary.${e.key}', e.key, e.value),
    ];
    return SourceResult(
      info: info,
      checkedAt: at,
      fields: fields,
      claims: const [
        Claim(
          aspect: 'Book record',
          status: VerificationStatus.recordFound,
          detail:
              'A catalogue record matches this ISBN. It does not prove this '
              'copy is genuine.',
        ),
      ],
    );
  }
}
