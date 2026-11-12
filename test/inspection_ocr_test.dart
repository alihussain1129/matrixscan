import 'dart:io';

import 'package:exalted/features/inspection/inspection_log.dart';
import 'package:exalted/features/inspection/inspection_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late InspectionLog log;
  const raw = '(01)09504000059101(21)SN7(10)L7(17)271231';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('exalted_ocr_rows_');
    log = InspectionLog(
      directory: () async => dir,
      clock: () => DateTime(2026, 11, 3),
    );
  });
  tearDown(() async => dir.delete(recursive: true));

  test('OCR that matches none of the fields needs review, not fail', () async {
    final r = await log.recordDecode(
      raw: raw,
      symbology: 'Data Matrix',
      source: 'live',
      ocrText: 'completely unrelated words',
    );
    expect(r!.status, RowStatus.review);
  });

  test('a plain code ignores OCR text', () async {
    final r = await log.recordDecode(
      raw: 'HELLO',
      symbology: 'QR Code',
      source: 'live',
      ocrText: 'something',
    );
    expect(r!.status, RowStatus.pass);
  });

  test('note and image path are kept', () async {
    final r = await log.recordDecode(
      raw: raw,
      symbology: 'Data Matrix',
      source: 'live',
      ocrNote: 'OCR skipped: busy',
      imagePath: '/tmp/x.png',
    );
    final back = (await log.loadAll()).single;
    expect(back.ocrNote, 'OCR skipped: busy');
    expect(back.imagePath, '/tmp/x.png');
    expect(r!.status, RowStatus.pass);
  });
}
