import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/core/message_framer.dart';

List<int> bytes(String s) => utf8.encode(s);
List<String> decoded(List<List<int>> messages) =>
    messages.map(utf8.decode).toList();

void main() {
  group('MessageFramer', () {
    test('returns several messages from one chunk', () {
      final framer = MessageFramer();
      expect(decoded(framer.add(bytes('AAA\rBBB\rCC'))), ['AAA', 'BBB']);
      expect(framer.pendingBytes, 2);
      expect(decoded(framer.add(bytes('C\r'))), ['CCC']);
      expect(framer.pendingBytes, 0);
    });

    test('reassembles a message split across chunks', () {
      final framer = MessageFramer();
      expect(framer.add(bytes('HEL')), isEmpty);
      expect(framer.add(bytes('LO')), isEmpty);
      expect(decoded(framer.add(bytes('\r'))), ['HELLO']);
    });

    test('handles a CRLF terminator split between chunks', () {
      final framer = MessageFramer(terminator: const [0x0D, 0x0A]);
      expect(framer.add(bytes('AB\r')), isEmpty);
      expect(decoded(framer.add(bytes('\nCD\r\n'))), ['AB', 'CD']);
    });

    test('keeps a multi-byte character split across chunks intact', () {
      final framer = MessageFramer();
      expect(framer.add([0x61, 0xC3]), isEmpty);
      expect(decoded(framer.add([0xA9, 0x0D])), ['a\u00e9']);
    });

    test('skips empty messages by default and keeps them when asked', () {
      expect(decoded(MessageFramer().add(bytes('\r\rX\r'))), ['X']);
      expect(decoded(MessageFramer(skipEmpty: false).add(bytes('\rX\r'))), [
        '',
        'X',
      ]);
    });

    test('discards an over-long partial buffer and recovers', () {
      final framer = MessageFramer(maxMessageBytes: 4);
      expect(framer.add(bytes('abcdefg')), isEmpty);
      expect(framer.overflowCount, 1);
      expect(framer.pendingBytes, 0);
      expect(decoded(framer.add(bytes('ok\r'))), ['ok']);
    });

    test('drops an over-long complete message but keeps the next one', () {
      final framer = MessageFramer(maxMessageBytes: 4);
      expect(decoded(framer.add(bytes('abcdefg\rok\r'))), ['ok']);
      expect(framer.overflowCount, 1);
    });

    test('reset drops a partial message', () {
      final framer = MessageFramer();
      framer.add(bytes('half'));
      framer.reset();
      expect(decoded(framer.add(bytes('new\r'))), ['new']);
    });

    test('rejects an empty terminator', () {
      expect(() => MessageFramer(terminator: const []), throwsArgumentError);
    });
  });
}
