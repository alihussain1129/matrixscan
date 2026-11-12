import 'package:exalted/features/scanner/scanner_analyzer.dart';
import 'package:exalted/ffi/decode_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty format selection means all formats', () {
    expect(decoderFormatsMask(const []), 0);
  });

  test('selected formats map to their native bit flags', () {
    expect(
      decoderFormatsMask(const ['dataMatrix', 'qrCode', 'rmQr']),
      BarcodeKind.dataMatrix.flag |
          BarcodeKind.qrCode.flag |
          BarcodeKind.rmQr.flag,
    );
  });

  test('new industrial formats have unique flags', () {
    final flags = {
      BarcodeKind.rmQr.flag,
      BarcodeKind.dxFilmEdge.flag,
      BarcodeKind.dataBarLimited.flag,
    };
    expect(flags.length, 3);
    expect(
      decoderFormatsMask(const ['dxFilmEdge', 'dataBarLimited']),
      BarcodeKind.dxFilmEdge.flag | BarcodeKind.dataBarLimited.flag,
    );
  });
}
