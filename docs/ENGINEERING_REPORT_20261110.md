# Engineering report, 2026-11-10

## Environment limits (important)
The session had no Flutter SDK (its artifact host was unreachable), so these
were **not run**: `flutter analyze`, `flutter test`, any Flutter build,
screenshots, Android, Windows. A Dart 3.13.7 SDK (conda-forge) and GCC 13 /
CMake were available. Dart tests were run with small local stand-ins for
`flutter_test`, `ffi`, `flutter/foundation` and `flutter_riverpod` (not part of
this project) against real sockets and the real native library. Please re-run
the full suite with your real toolchain.

## Changes
| Area | File | Change |
|---|---|---|
| Lints | `lib/features/link/link_client.dart`, `link_pairing.dart`, `lib/features/settings/auto_restart_card.dart` | Added curly braces at the 3 reported sites; behaviour unchanged |
| Native tests | `cpp/utah_test.cpp`, `cpp/tests/datamatrix_traversal_test.cpp` | Tests were wrong (wrong corner function / invented coordinates). Rewritten from ISO 16022 corner tables, cross-checked with vendored zxing-cpp. Decoder code NOT changed. Walking-bit checks added; all 32 single-coordinate mutations of the decoder are caught |
| Native ABI | `cpp/src/ffi_api.cpp`, `cpp/include/exalted/ffi_api.h` | `static_assert`s pinning format flags to ZXing; added RMQR / DX Film Edge / DataBar Limited flags |
| Native tests | `cpp/tests/exalted_decode_test.cpp` | Mask semantics (0, Data Matrix, QR-only, multi-bit) and text-buffer overrun test |
| FFI loading | `lib/ffi/native_library_loader.dart` (new), `exalted_bindings.dart`, `decoder_service.dart` | Multi-location loader with diagnostics; `loadedFrom`; clear error for outdated library |
| KEYENCE | `lib/features/devices/core/reconnect_backoff.dart` (new), `keyence_sr751_client.dart` | Bounded jitter; injectable timer/clock/socket/random; quick-drop penalty so a flapping reader cannot cause a fast loop; identical consecutive status events suppressed |
| Tests | `test/ffi/*`, `test/keyence_reconnect_deterministic_test.dart` (new) | See below |
| Docs | `docs/NATIVE_BUILD_AND_FFI.md`, this report | New |

Originals of every modified file: `backups/20261110-093846/`.

## Results actually obtained
* Native: library builds; 8/8 native test executables pass (before: 2 failed).
* Native mutation check of the corner tests: 32/32 caught.
* Dart loader tests: 13/13 pass, including 2 against the real built library
  through `dart:ffi` (API version, blank-frame decode, bad-buffer rejection).
* KEYENCE existing tests (robustness 6, client 2, simulator/protocol 7): 15/15
  pass before and after the client changes.
* New deterministic reconnect tests: 14/14 pass. Mutation check: removing the
  quick-drop penalty and removing timer cancellation on disconnect are each
  caught. **Removing the status de-duplication is not caught**: no current code
  path emits an adjacent duplicate, so that guard is defensive and unproven.
* `dart format` is clean on all changed files.

## Finding: "5 ms reconnect intervals"
Not a product defect. `keyence_sr751_client_robustness_test.dart` passes a 1 ms
base and 5 ms max delay on purpose. Production defaults are 1 s doubling to 16 s.
`reconnectJitter` defaults to 0 (existing behaviour); pass e.g. 0.2 where
several clients may retry together.

## Not done / unverified
* Flutter analyze/test/build for any platform; screenshots.
* GUI redesign, design system, desktop/mobile shells.
* Link pairing and sync audit and hardening; Android/desktop pairing workflow.
* Beep platform channel; OCR; verification services; FTP re-audit.
* Real SR-751 hardware (only the simulator was used).
* Android release signing currently uses the debug key
  (`android/app/build.gradle.kts`); not changed, needs your signing config.
