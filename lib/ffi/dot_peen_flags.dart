/// Native decode flags for dot-peened Data Matrix codes: the separate dots are
/// merged into solid modules before decoding. Flag bits: 8 = no downscale,
/// 16 = global-histogram binarizer, bits 10-12 = dark-dot grow radius in
/// pixels (1..7), 256 = grow light dots instead (needs 2 = invert).
///
/// The radius has to match the dot spacing, so the list spans several radii.
/// Order: most likely first.
const List<int> dotPeenFlags = [
  3096, // dark dots, global histogram, radius 3
  4104, // dark, local binarizer, radius 4
  4120, // dark, global, radius 4
  5144, // dark, global, radius 5
  2056, // dark, local, radius 2
  1032, // dark, local, radius 1
  3354, // light dots, global, radius 3
  4362, // light, local, radius 4
  4378, // light, global, radius 4
  2314, // light, local, radius 2
];
