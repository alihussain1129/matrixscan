# Native decoder: build, packaging and loading

Only behaviour verified in the 2026-11-10 session is documented as verified.
Everything else is marked **unverified**.

## Source of truth
`cpp/` is the native tree used by the Linux, Windows and Android builds
(`linux/CMakeLists.txt`, `windows/CMakeLists.txt` and the Android Gradle config
all reference `../cpp`). `native/exalted_core/` is an older copy that nothing
builds; do not edit it.

## Building and testing on Linux (verified: GCC 13, CMake 4, Ninja)
```bash
cmake -S cpp -B build/native -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C build/native
# test executables (each returns 0 on success)
build/native/utah_test
build/native/datamatrix_encoder_test
build/native/exalted_decode_test
build/native/exalted_dotpeen_test
build/native/tests/datamatrix_traversal_test
build/native/tests/datamatrix_symbol_test
build/native/tests/datamatrix_symbol_info_test
build/native/tests/datamatrix_placement_test
```
Result 2026-11-10: library builds; all 8 test executables pass.

Release `libexalted_ffi.so` is about 1.0 MB; a Debug build is about 11.8 MB.
Check which one you are shipping with `ls -l` before packaging.

Verified properties of the Release library:
* exports exactly `exalted_api_version`, `exalted_probe`, `exalted_decode`;
* depends only on libstdc++, libm, libgcc_s and libc (`ldd`).

## C ABI
Defined in `cpp/include/exalted/ffi_api.h`; the Dart typedefs are in
`lib/ffi/exalted_bindings.dart` and match.

* `formatsMask == 0` means **all supported formats** (see `toFormats` in
  `cpp/src/ffi_api.cpp`). A non-zero mask restricts decoding to those formats.
* Mask bits are ZXing's `BarcodeFormat` values. `ffi_api.cpp` contains
  `static_assert`s, so a ZXing upgrade that renumbers formats fails the build
  instead of silently decoding the wrong symbologies.
* `exalted_decode` returns -5 when the text buffer is too small; `info[1]` then
  holds the size needed and nothing is written past the buffer.

## Loading from Dart (`lib/ffi/native_library_loader.dart`)
Search order:
1. `EXALTED_FFI_PATH` (a file, or the directory containing the library);
2. next to the executable: `<exe dir>/lib/` then `<exe dir>/` (Linux bundle),
   `<exe dir>/` (Windows);
3. debug/profile builds only: `build/<platform>/<arch>/<mode>/bundle/...` under
   the working directory (disabled in release/profile so a library cannot be
   planted relative to the working directory);
4. the bare library name (operating-system loader; this is how Android loads it).

If nothing loads, the error lists every location tried and why it failed. The
loader never falls back to a mock. `DecoderService.loadedFrom` is null unless a
real library was loaded, so tests can tell real from unavailable.

Run the real-native tests against a build:
```bash
EXALTED_FFI_PATH=build/native flutter test test/ffi
```
Without the variable these tests are skipped and say so.

## Platform packaging
* Linux: `install(TARGETS exalted_ffi LIBRARY DESTINATION lib)` places it in
  `bundle/lib/`. **Unverified**: no Flutter build was run.
* Windows: the DLL installs beside the executable, which is where `LoadLibrary`
  looks. **Unverified**: no Windows build was run.
* Android: built by the Gradle external native build; ABIs per Gradle config.
  **Unverified**: no Android build was run.
