# Exalted Companion Milestone — 2026-11-11

## Delivered

### Credential-storage continuation

The follow-up migration stores desktop TLS identity material and paired-device
HMAC secrets through the platform secure-storage plugin. `link_state.json` now
contains versioned public metadata and digest-addressed vault references, so
interrupted writes leave the prior credential generation loadable until the
atomic metadata commit. Format 2 and legacy credentials are migrated without
regenerating identities. POSIX state and backup files are owner-only. Focused
tests passed for secret separation, migration, interrupted writes, state
preservation, pairing, replay rejection, and revocation. The OS backends still
require runtime verification on Android, Windows, and Linux Secret Service.

The Android app now has a phone-first companion experience with Overview, Activity, History, Devices, and Settings destinations. Overview shows the selected paired desktop, platform, actual connection/stale state, heartbeat age, measured request round-trip time, record-backed daily scan/OCR/inspection counts, pending sync count, available hardware telemetry, and recent activity. Phone scanning remains available and desktop activity remains distinguishable from locally created or imported records.

The existing searchable inspection audit table is now reachable as a first-class destination from both the desktop sidebar and the Android Overview tools menu. The dashboard inspection metric links to that real record view. Desktop navigation provides Ctrl+0 for the added tenth destination; keyboard/sidebar navigation coverage and the mobile tools menu are tested.

The desktop link host exposes an authenticated companion snapshot endpoint. It is served over the existing pinned-certificate HTTPS transport after request authentication and replay checks. The snapshot contains desktop identity, live counts, recently active linked devices, available hardware status, and durable journal activity. Mobile polling updates every three seconds when healthy and backs off after failures (up to 30 seconds); a failed connection retains cached data and labels it stale/offline. A selected paired desktop can be refreshed or changed. Desktop records are swept into the journal at startup and periodically while hosting, so the feed uses application data rather than fabricated sample events.

Activity can be filtered by scans, OCR, and inspections. The dashboard offers a real synchronization request, local scan entry, and access to OCR, Verification, and Diagnostics. Unsupported remote scan control and Android notification delivery are not presented as working controls. Hardware status is shown only when an existing provider is active and reports it; otherwise the UI says it is unavailable.

Imported decoder and inspection records retain origin-device identity. Sync journaling skips records with remote origin metadata and records whose exact IDs already exist, preventing re-import loops and duplicate journal entries. Existing secure pairing, revocation, durable sync, retry, and conflict review remain in place.

Linux and Windows use the shared Dart desktop link host, so the companion endpoint is not Linux-specific. Existing desktop shell/navigation and scanner capabilities were preserved. This milestone focused on implementing the companion workflow and did not comprehensively redesign every desktop screen.

## Verification

- `flutter analyze`: passed.
- Full Flutter suite before credential continuation: 685 tests passed; the
  latest continuation full suite passed with 691 tests.
- FFI integration tests: 13 passed.
- Native C++ release configuration/build: passed; all 8 native test executables passed.
- `dart format --output=none --set-exit-if-changed lib test`: passed; 321 files checked, no changes needed.
- Linux release build: passed (`build/linux/x64/release/bundle/exalted`).
- Android debug APK build: passed.
- Android release APK build: passed (97.0 MB).
- Android API 37 emulator: debug APK installed and launched; `com.exaltedcoding.exalted` was the resumed activity. No Flutter or Android runtime errors were present in the checked error logs.
- `git diff --check`: passed.

## Limits and remaining acceptance work

- Windows release build could not run on this Linux host: Flutter reports that `build windows` is supported only on Windows hosts. No Windows build success is claimed. Run `flutter build windows --release` on a Windows machine with the required Visual Studio C++ workload, then validate native library packaging and runtime loading there.
- Android verification used an emulator. Physical camera/scanner behavior, Android notification permission flows, and hardware integration were not verified on a physical device.
- Companion live delivery currently uses authenticated polling of a structured snapshot, rather than a push stream. The activity feed reflects supported durable journal records; it does not yet provide every requested event class such as arbitrary application errors or hardware disconnect transitions.
- Remote start/stop/pause/resume commands and Android notification delivery are not implemented in this milestone. No remote-control action is exposed as functional.
- Pairing, secure transport, revocation, durable synchronization, import deduplication, and UI flows have automated coverage, but cross-network-change behavior and phone-to-Windows pairing need execution on their target devices/platforms.
- Linux release build and automated tests passed; Pop!_OS/COSMIC/Wayland behavior was not manually exercised in this run.

## Archive

The continuation source archive is
`Exalted-source-2026-11-12-inspection-navigation.zip`. It excludes `.git`,
build outputs/caches, local databases, credential and environment files, and
nested ZIP archives. Its integrity is checked. Existing archives are left
untouched.
