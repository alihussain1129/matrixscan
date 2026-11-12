import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/link/link_providers.dart';

Uint8List _response(List<int> txn, {int type = 0x0101}) {
  final header = ByteData(20)
    ..setUint16(0, type)
    ..setUint16(2, 12)
    ..setUint32(4, 0x2112A442);
  for (var i = 0; i < 12; i++) {
    header.setUint8(8 + i, txn[i]);
  }
  final attr = ByteData(12)
    ..setUint16(0, 0x0020)
    ..setUint16(2, 8)
    ..setUint8(4, 0)
    ..setUint8(5, 1)
    ..setUint16(6, 54321 ^ 0x2112);
  const cookie = [0x21, 0x12, 0xA4, 0x42];
  const ip = [203, 0, 113, 9];
  for (var i = 0; i < 4; i++) {
    attr.setUint8(8 + i, ip[i] ^ cookie[i]);
  }
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...attr.buffer.asUint8List(),
  ]);
}

void main() {
  final txn = Uint8List.fromList(List<int>.generate(12, (i) => i + 1));

  test('parses the mapped public address', () {
    final c = parseStunBindingResponse(_response(txn), txn);
    expect(c, isNotNull);
    expect(c!.host, '203.0.113.9');
    expect(c.port, 54321);
  });

  test('rejects wrong transaction id, wrong type and truncated data', () {
    final other = Uint8List.fromList(List<int>.filled(12, 9));
    expect(parseStunBindingResponse(_response(txn), other), isNull);
    expect(parseStunBindingResponse(_response(txn, type: 0x0111), txn), isNull);
    expect(
      parseStunBindingResponse(_response(txn).sublist(0, 24), txn),
      isNull,
    );
  });
}
