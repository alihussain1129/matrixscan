# Companion milestone — final GUI and release readiness

Date: 2026-11-12

## Completed

- Added desktop `Ctrl+K` searchable navigation across every workspace, plus direct image import into OCR.
- Added visible Overview shortcuts for Scanner, Decode & OCR, Inspection, and Verification; each opens its existing mobile workflow.
- Fixed and emulator-verified narrow phone Settings layout; corrected the global notification opt-in switch so its default matches the service-off state.
- Android emulator permission test: notification denial kept the setting off with guidance; subsequent acceptance granted `POST_NOTIFICATIONS` and enabled the setting.
- Fixed Windows-observed FTP PASV wildcard address behavior for loopback tests; made the real retry test wait for the expected retry count rather than a fixed short duration. The relevant socket integration tests pass on Linux.
- Kept the established phone navigation (Overview, Activity, History, Devices, Settings) and existing overview shortcuts to Scanner, Decode & OCR, Verification, and Diagnostics.
- Added opt-in external Android release signing and a production-required Gradle guard. No credentials or signing keys were generated or committed.
- Regression results: 696 Flutter tests, Flutter analysis, formatting, whitespace check, and all eight existing native C++ executables passed.
- Android debug/release and Linux release builds passed. Android release remains debug-signed.

## Current reliability boundary

Companion event delivery currently depends on the Android process and the paired desktop being reachable on the local network. Event cursor persistence, deduplication, reconnect, and polling fallback protect recovery while the app runs, but do not create a wake-up path after process death. WorkManager can schedule deferred recovery and is not an immediate LAN socket listener. A foreground service would need an explicit user-visible start/stop experience, persistent notification, API-specific service declarations/permissions, and physical-device testing. This service is not implemented, so background delivery after process death is not guaranteed.

## Validation outstanding

- Windows Actions release packaging passed on the prior committed revision; see [run #10](https://github.com/alihussain1129/matrixscan/actions/runs/42779661377). This current working tree is not committed and has not been built on Windows. Full Windows interactive and hardware validation remain outstanding. The prior full-test workflow [run #2](https://github.com/alihussain1129/matrixscan/actions/runs/42779661364) exposed the PASV address and retry-timing issues; targeted tests pass locally after correction, but Windows CI has not yet rerun.
- Android API 37 emulator checks passed for app startup, scanner camera permission/preview, notification permission deny/accept, and Settings layout. No physical phone was attached, and there was no paired desktop for live event or remote-control checks.
- Android production-signed release: not produced; owner-managed credentials were not available. The Gradle gate's missing-credentials failure was verified.
- Real Keyence scanner: not attached. Existing software tests pass. `LON`/`LOFF` and `T1`/`T2` are read/trigger commands; their socket-write success does not confirm a device acknowledgement. No camera pause/resume mapping was invented for SR-751.
- Notifications after process termination remain unavailable until app restart/reconnect; the project has no push backend or persistent foreground service.

## Android platform references

- [Android persistent work](https://developer.android.com/develop/background-work/background-tasks/persistent)
- [Launching foreground services](https://developer.android.com/develop/background-work/services/fgs/launch)
- [Foreground service background-start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
