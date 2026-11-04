import 'dart:typed_data';

import 'package:exalted/features/scanner/captured_frame.dart';
import 'package:flutter_test/flutter_test.dart';

CapturedFrame gray(List<int> v, int w, int h, {int rot = 0, int? stride}) =>
    CapturedFrame(
      bytes: Uint8List.fromList(v),
      width: w,
      height: h,
      stride: stride ?? w,
      isBgra: false,
      rotationDegrees: rot,
    );

List<int> reds(FrameRgba f) => [
  for (var i = 0; i < f.pixels.length; i += 4) f.pixels[i],
];

void main() {
  test('BGRA becomes RGBA', () {
    final f = CapturedFrame(
      bytes: Uint8List.fromList([1, 2, 3, 255]),
      width: 1,
      height: 1,
      stride: 4,
      isBgra: true,
      rotationDegrees: 0,
    );
    expect(convertFrame(f).pixels, [3, 2, 1, 255]);
  });

  test('rotations make the image upright', () {
    final r90 = convertFrame(gray([10, 20], 2, 1, rot: 90));
    expect((r90.width, r90.height), (1, 2));
    expect(reds(r90), [10, 20]);
    final r270 = convertFrame(gray([10, 20], 2, 1, rot: 270));
    expect(reds(r270), [20, 10]);
    final r180 = convertFrame(gray([10, 20], 2, 1, rot: 180));
    expect((r180.width, r180.height), (2, 1));
    expect(reds(r180), [20, 10]);
  });

  test('crop keeps only the region', () {
    final f = convertFrame(gray([1, 2, 3, 4], 4, 1), left: 0.5);
    expect(f.width, 2);
    expect(reds(f), [3, 4]);
  });

  test('row padding is skipped', () {
    final f = convertFrame(gray([1, 2, 9, 3, 4, 9], 2, 2, stride: 3));
    expect(reds(f), [1, 2, 3, 4]);
  });
}
