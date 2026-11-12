import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/storage/json_decode.dart';

void main() {
  test('small text gives the same result as jsonDecode', () async {
    const text = '[{"a":1},{"b":[true,null,"x"]}]';
    expect(await decodeJsonOffThread(text), jsonDecode(text));
  });

  test('big text is decoded in the background with the same result', () async {
    final data = [
      for (var i = 0; i < 5000; i++) {'id': i, 'name': 'entry $i'},
    ];
    final text = jsonEncode(data);
    expect(text.length, greaterThan(64 * 1024));
    expect(await decodeJsonOffThread(text), data);
  });

  test('bad input throws in both paths', () async {
    await expectLater(decodeJsonOffThread('not json'), throwsA(anything));
    final bad = '[${'1,' * 40000}';
    await expectLater(decodeJsonOffThread(bad), throwsA(anything));
  });
}
