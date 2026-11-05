import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/features/devices/keyence/sr751_message_classifier.dart';

void main() {
  const guide = Sr751ReplyProfile.guideDocumented();

  test('legacy profile classifies plain data as a barcode and trims it', () {
    final c = Sr751MessageClassifier().classify('  LOT-9924-X \r');
    expect(c.kind, Sr751MessageKind.barcode);
    expect(c.payload, 'LOT-9924-X');
  });

  test('legacy profile treats ERROR forms and NG as read failures', () {
    final c = Sr751MessageClassifier();
    for (final line in ['ERROR', 'ERROR,01', 'NG']) {
      expect(c.classify(line).kind, Sr751MessageKind.readFailure, reason: line);
    }
  });

  test('legacy profile ignores blank lines and keeps NGX as data', () {
    final c = Sr751MessageClassifier();
    expect(c.classify('   ').kind, Sr751MessageKind.ignored);
    expect(c.classify('NGX').kind, Sr751MessageKind.barcode);
  });

  test('legacy profile still treats OK as a barcode (known limitation)', () {
    expect(
      Sr751MessageClassifier().classify('OK').kind,
      Sr751MessageKind.barcode,
    );
  });

  test('a configured acknowledgement after a sent command is a response', () {
    final c = Sr751MessageClassifier(profile: guide)..noteCommandSent('BEEP');
    final r = c.classify('OK');
    expect(r.kind, Sr751MessageKind.commandResponse);
    expect(r.command, 'BEEP');
  });

  test(
    'an acknowledgement with no pending command is unknown, not a barcode',
    () {
      final r = Sr751MessageClassifier(profile: guide).classify('OK');
      expect(r.kind, Sr751MessageKind.unknown);
      expect(r.payload, isEmpty);
    },
  );

  test('a pending command answers only one acknowledgement', () {
    final c = Sr751MessageClassifier(profile: guide)..noteCommandSent('BEEP');
    expect(c.classify('OK').kind, Sr751MessageKind.commandResponse);
    expect(c.classify('OK').kind, Sr751MessageKind.unknown);
  });

  test('a pending command expires after the reply window', () {
    var now = DateTime(2026, 11, 5);
    final c = Sr751MessageClassifier(profile: guide, clock: () => now)
      ..noteCommandSent('BEEP');
    now = now.add(const Duration(seconds: 3));
    expect(c.classify('OK').kind, Sr751MessageKind.unknown);
  });

  test('ordinary data stays a barcode while a command is pending', () {
    final c = Sr751MessageClassifier(profile: guide)..noteCommandSent('BEEP');
    expect(c.classify('LOT-9924-X').kind, Sr751MessageKind.barcode);
    expect(c.classify('OK').kind, Sr751MessageKind.commandResponse);
  });

  test('a barcode header makes classification strict', () {
    final c = Sr751MessageClassifier(
      profile: const Sr751ReplyProfile(name: 'strict', barcodePrefix: 'DATA:'),
    );
    final ok = c.classify('DATA:XYZ');
    expect(ok.kind, Sr751MessageKind.barcode);
    expect(ok.payload, 'XYZ');
    expect(c.classify('FOO').kind, Sr751MessageKind.unknown);
  });

  test('a header with no payload is unknown', () {
    final c = Sr751MessageClassifier(
      profile: const Sr751ReplyProfile(name: 'strict', barcodePrefix: 'DATA:'),
    );
    expect(c.classify('DATA:').kind, Sr751MessageKind.unknown);
  });

  test('status patterns classify status lines', () {
    final c = Sr751MessageClassifier(
      profile: const Sr751ReplyProfile(
        name: 'status',
        statusPatterns: <String>[r'^STATUS '],
      ),
    );
    expect(c.classify('STATUS 00').kind, Sr751MessageKind.status);
    expect(c.classify('ABC').kind, Sr751MessageKind.barcode);
  });

  test('error patterns win over the barcode header', () {
    final c = Sr751MessageClassifier(
      profile: const Sr751ReplyProfile(
        name: 'strict',
        errorPatterns: <String>[r'^ERROR'],
        barcodePrefix: 'ERROR',
      ),
    );
    expect(c.classify('ERROR,1').kind, Sr751MessageKind.readFailure);
  });
}
