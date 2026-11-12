# Exalted implementation report — 2026-11-11

## Work completed in this batch

- Moved TLS identity material and paired-device HMAC secrets out of
  `link_state.json` into the platform secure-storage provider. Format 3 uses
  digest-addressed vault entries so interrupted writes leave the previous
  credential generation loadable until the atomic metadata commit. Format 2
  and legacy plaintext state both migrate without changing paired identities.
  POSIX state directories, state files, and migration backups are restricted
  to owner access. Migration failures leave the original file recoverable.
- Added focused coverage for secret separation, legacy and format 2 migration,
  vault integrity failure, interrupted vault writes, and corrupt-state
  preservation. The focused link store, TLS pairing, replay, revocation, and
  controller test set passed (32 tests).

- Reorganized the shared navigation around Dashboard, Scanner, Decode & OCR,
  History, Devices, Synchronization, Verification, Diagnostics, and Settings.
  Desktop sidebar groups and Ctrl+number shortcuts cover every destination.
  Mobile keeps the compact bottom bar with remaining destinations under More.
- Added the existing inspection audit table as a direct Inspection destination
  in both shells. Desktop Ctrl+0 selects it; Android users can open it from the
  Overview tools menu. The workspace reads the real inspection log and retains
  search, PASS/FAIL/REVIEW filters, details, and CSV export. The dashboard
  inspection metric now opens that workspace instead of navigating to itself.
- Corrected dashboard status badges that implied an air-gapped engine or a
  ready scanner when telemetry had not established those states. The dashboard
  now identifies opt-in online lookups and reports KEYENCE discovery/offline
  state explicitly.
- Added a dedicated Verification screen. Local structure and URL checks are
  identified separately from opt-in online catalogues. The persisted source
  switches now live there instead of being duplicated in Settings.
- Split Settings into eleven horizontally navigable sections: General,
  Appearance, Scanning, Decoder, OCR, Verification, Devices & Sync,
  Network & FTP, Notifications & Feedback, Advanced, and About. Existing
  storage integrity, backup, restart, FTP, appearance, scan feedback, and device
  controls remain available in their respective sections.
- Added a Diagnostics screen backed by current camera, KEYENCE, sync, OCR, and
  native-library state. The native library is loaded only when Diagnostics is
  opened. Android ML Kit is described as checked on first recognition rather
  than being reported as ready before it has run. The screen also shows local
  IPv4 interfaces, actual FTP listener state, crash-log status, and a Copy Log
  action.
- Consolidated Dashboard history reads: a refresh reads scan history once,
  derives both the total and recent rows from that result, and reads inspection
  totals concurrently.
- Added 100-record “Load next” pages to Decoder and OCR History, while keeping
  list rows lazy. OCR data is loaded once per screen lifetime and reloaded after
  edits or clearing instead of re-reading on every search rebuild. Added a
  paging-boundary widget test. It refreshes after detail edits/deletes and on
  OCR-tab selection so records changed elsewhere do not stay stale.
- Cached verification responses now retain their original fetch timestamp
  through the shared result model. Result provenance labels cached data and its
  age; cache hits refresh the check time without misrepresenting the source
  fetch time. Added cache expiry and UI provenance tests.
- Online verification HTTP replies now retain response headers. A shared
  rate-limit handler recognizes numeric and HTTP-date `Retry-After` values,
  retries once only when the requested wait is at most four seconds, and leaves
  longer waits as unavailable instead of retrying early. This is wired into
  Open Food Facts, the Open Facts catalogues, openFDA, Open Library, and NHTSA.
- Wired persisted decoder symbology choices into every live frame decode.
  Added rMQR, DX Film Edge, and GS1 DataBar Limited to the Dart decoder/config
  models and added a Settings control for selecting formats. Changing the
  setting updates the existing analyzer immediately; selecting all restores
  the native all-formats mask.
- Made the Android orientation request non-blocking and added a first-frame
  startup timing log (`[EXALTED][STARTUP]`). Startup instrumentation separates
  config setup, Dart-entry-to-first-frame time, and first-frame build/raster.
- Changed the Linux default renderer to Skia after a release A/B on this host.
  Added the CMake option `EXALTED_USE_IMPELLER=ON` for target hardware where
  Impeller measures better; both renderer branches compile.

## Verification results

- `flutter analyze`: clean.
- Full Flutter suite after native Data Matrix integration and deferred desktop
  service initialization, sync conflict review, and progress corrections:
  677 passed, 0 failed, 0 errors, 0 skipped.
- A widget regression test confirms the initial desktop toolbar and status bar
  do not initialize scanner, KEYENCE, or synchronization services.
- Sync conflicts are now listed in Devices & Sync. Each decision is appended
  to a separate resolution journal; users can keep the current record or save
  the incoming payload as a separate local history record. Both source
  versions remain in the immutable sync evidence journal.
- Synchronization sessions are appended to `link_sync_sessions.jsonl` for both
  successful and failed runs. The journal reloads the entries after restart,
  exposes newest-first history, and Devices & Sync shows the latest 20 sessions.
  Failed sessions offer Retry when their peer is still linked; retry goes through
  the regular sync path and records a new session, preserving the earlier failure.
- A Devices & Sync widget test verifies that failed session details and Retry
  appear when the associated peer remains linked; it does not start a transfer.
- Transfer progress now reports processed image/record counts with an
  indeterminate indicator when the remote total is unknown; it no longer
  reports `done of done` while later pages are still pending.
- Focused navigation and verification widget tests: passed.
- Focused decoder format mapping and live analyzer update tests: passed.
- Devices & Sync screen widget tests: 3 passed after replacing platform plugin
  initialization in UI-only cases with a deterministic controller fake. Pairing,
  replay, revocation, and journal persistence remain covered separately.
- Focused History pagination, search/export, and clear tests: passed.
- Focused OCR History refresh and no-reload-on-search widget test: passed.
- Focused verification cache age and provenance tests: passed.
- Focused numeric/date `Retry-After` behavior and online source tests: passed.
- Settings category and persisted symbology interaction widget test: passed.
- Earlier full Flutter suite: 679 passed, 0 failed. Formatting verification
  (`dart format --output=none --set-exit-if-changed lib test`) found 319 files
  already formatted; `flutter analyze` reported no issues.
- Continuation full Flutter suite: 691 passed, 0 failed after fixing the two
  linked-device widget tests, adding storage interruption coverage, and adding
  the mobile Inspection tools-menu test.
  `flutter analyze` is clean; 322 Dart files passed format verification.
- Native C++ release build: passed; all 8 native test executables passed.
- Rebuilt native C++20 library and reran all 8 executables in this continuation;
  all passed. Real-library Dart FFI integration tests passed (13 tests) with
  `EXALTED_FFI_PATH=build/native/libexalted_ffi.so`.
- CTest has no registered cases in this project; all 8 native test executables
  were run directly and passed.
- Android debug APK: rebuilt at `build/app/outputs/flutter-apk/app-debug.apk`.
- Android release APK: built at `build/app/outputs/flutter-apk/app-release.apk`
  (96.7 MB). This verifies packaging and native compilation, not device behavior.
- Linux release application: rebuilt at
  `build/linux/x64/release/bundle/exalted` with the Skia default. The opt-in
  Impeller CMake branch also compiled in the earlier A/B work.
  This host needed its generated CMake cache pointed at installed GCC/JDK paths;
  the JNI plugin still emits incompatible-pointer warnings with GCC 15. These
  were build-only settings and did not change tracked platform source.
- After the final credential-store continuation, Android debug and Linux
  release builds were rerun and passed. Windows remains unbuildable on this
  Linux host.
- After the Inspection navigation update, Android debug and Linux release
  builds passed again.
- Android release APK was also rebuilt after the migration at
  `build/app/outputs/flutter-apk/app-release.apk` (97.2 MB).

## Measurements and limits

The unused native Data Matrix decoder stub is now implemented as a reusable,
stride-aware C++ decoder and is used by the FFI when callers request only Data
Matrix. It applies the decoder flags for inversion, rotation, downscaling, and
binarization, and returns decoded text, symbol corners, and decode time. Mixed
format requests keep the existing multi-format ZXing route. The golden native
tests cover both the specialized route and the existing generic route.

The desktop shell now defers scanner/decoder and KEYENCE provider activation
until those destinations are visited. The initial desktop status bar does not
poll the scanner, and synchronization storage starts when its screen is opened.
Dashboard KEYENCE and OCR availability checks begin after the first frame.
Launching the final Linux release build confirmed that its first-frame log has
no scanner creation or native FFI load. This removes eager work from the shell;
it does not establish navigation or camera latency.

The earlier lazy-shell Linux x86_64 release sample on this Wayland host measured
first process 475.4 ms, then 446.7 ms median / 465.9 ms p95; RSS was 136.0 MB
median. First-frame build was 2.82 ms median and raster was 40.87 ms median /
49.68 ms p95. Against the earlier Skia-default sample, warm median startup fell
from 513.9 ms to 446.7 ms (about 67 ms); those samples were not paired.

This continuation reran `python3 tool/benchmark_linux_startup.py --runs 10`
against the newly rebuilt release app. It measured first process 2165.4 ms;
subsequent processes were 738.8 ms median / 782.3 ms p95 (725.0–782.3 ms),
with 136.0 MB median RSS. First-frame build was 4.42 ms median; raster was
60.94 ms median / 86.22 ms p95. The first run was a fresh process, not a cold
OS page cache. These results are materially slower than the earlier sample;
the run happened after multiple native and Gradle builds, so host load and
environmental variation may contribute. No controlled before/after claim is
made from this rerun. Raster remains above a 16.7 ms 60 Hz frame budget.

The scanner's existing test instrumentation recorded 640×480 fixture-frame
scan-to-result samples from 3–48 ms and native decode values rounded to 1.0 ms.
These are automated test fixtures, not camera hardware measurements. Native
Data Matrix traversal test cases reported roughly 39–194 μs on this host.
They do not establish camera-to-result latency on production devices.

On the Linux x86_64 release build in this Wayland session (Intel Core i7-8650U,
Freedesktop SDK 25.08), the repeatable procedure is
`python tool/benchmark_linux_startup.py --runs 10`. A current Skia-default
10-run sample measured process launch to first frame at 525.3 ms on its first
fresh process and 513.9 ms median / 563.8 ms p95 across the following nine.
Resident memory after first frame was 137.7 MB median; first-frame build was
0.85 ms median and raster was 37.52 ms median / 39.75 ms p95. Support-directory
setup took 0 ms at millisecond resolution and config load 1–2 ms. This is a
fresh app process, not a guaranteed cold OS page cache. First-frame raster still
exceeds a 16.7 ms 60 Hz budget; sustained scrolling and jank are unmeasured.

In a separate ten-process release A/B, Skia measured 509.9 ms median / 527.7 ms
p95 for subsequent launches, 137.5 MB median RSS, and 37.17 ms median first
raster. Impeller measured 582.4 ms median / 607.3 ms p95, 152.9 MB RSS, and
37.26 ms raster. On this host Skia reduced warm startup by about 72 ms and RSS
by 15 MB, with essentially unchanged first-raster time. The runs used the same
application sources but were collected in renderer build order on one host;
target hardware may favor Impeller.

The script is at `tool/benchmark_linux_startup.py`. These measurements are a
host-specific before/after renderer comparison, not a guarantee of performance
on production hardware.

The History repository was also measured against a generated 5,000-record JSON
file using its normal file read, isolate JSON decode, and model conversion path.
Five loads measured 85, 49, 35, 29, and 33 ms (35 ms median, 85 ms p95). This
is a synthetic file benchmark on the same host; image decoding and Flutter row
rendering are intentionally outside this repository-load measurement.

Interactive navigation latency, OCR processing, verification latency under
controlled network conditions, history loading time, sustained frame jank, and
Android memory/startup remain unmeasured. This session has Wayland but no
screenshot utility or desktop input automation; the desktop portal screenshot
request returned cancellation status 2, so screenshots were not captured.
No Android device or Windows compiler/runtime/target is available. Android
debug and release APKs build, but have not been exercised on a device. The
Windows release command was attempted and Flutter reported that Windows builds
are only supported on Windows hosts. KEYENCE SR-751 and FTP hardware workflows
still need physical validation.

History renders in 100-row chunks but its current controller still loads up to
the 5,000-entry JSON cap into memory before filtering. The 5,000-record
repository benchmark above measures this current load behavior; it is not
evidence of paged storage queries. Sync history is durable, but session details
remain a compact summary; partial counts from a run that throws before returning
its summary are not available for the failure entry.

## Remaining release work

- Secure-storage migration has been verified with an in-memory vault in unit
  tests. Platform credential backends have not yet been exercised on physical
  Android, Windows, or a Linux desktop with Secret Service. POSIX permissions
  are applied and enforced by the store; Windows isolation depends on the
  `flutter_secure_storage_windows` user-scoped backend and still needs Windows
  runtime verification.

- Run interactive Linux and Android workflows on target devices and obtain
  screenshots; validate Windows on a Windows build host.
- Use the Linux startup figures as a host baseline; collect navigation, OCR,
  verification, history, scan, and sustained frame metrics on target devices.
- Investigate the slower startup and first-raster measurements from the latest
  Linux rerun under controlled host load before claiming a performance gain.
- Exercise camera lifecycle, pairing, sync interruptions/conflicts, FTP, and
  real SR-751 communications with hardware.
- Release signing configuration and hardware validation remain outstanding.
  Existing source archives, including `Exalted-source-2026-11-11.zip` and
  `Exalted-source-2026-11-11-final.zip`, were retained. A new uniquely named
  archive, `Exalted-source-2026-11-12-inspection-navigation.zip`, passed CRC
  and contents checks. It excludes build/cache trees, local databases,
  credential files, and nested ZIPs. No signing key or credential was
  regenerated.
