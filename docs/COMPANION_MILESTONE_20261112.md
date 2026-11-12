# Companion milestone — 2026-11-12

This milestone builds on the authenticated live event stream documented in `COMPANION_LIVE_EVENTS_20261112.md`.

## Current companion capabilities

- TLS certificate pinning, HMAC request authentication, timestamp validation, and nonce replay checks.
- Durable event cursor, event ID deduplication, event replay, reconnect backoff, and polling fallback.
- Android opt-in notifications for inspections, desktop/scanner connection transitions, sync results, and confirmed remote-command results.
- Host-owner permission per paired Android device for camera scanner commands. Permission defaults off and survives link-store reloads.
- Signed start/stop/pause/resume requests, server-side authorization and revocation checks, unique command IDs, append-only audit history, restart recovery, and final scanner-state confirmation.
- Android command confirmation/result UI and desktop authorization/audit UI.

## Verified

- `flutter analyze`: passed.
- Full `flutter test`: passed (694 tests).
- Authenticated TLS transport tests cover opt-in enforcement, replay rejection, audit persistence, and replay after LinkServer restart.
- Android debug and release APKs built; Linux release bundle built.
- Eight rebuilt native C++ test executables passed.

## Still open

- Physical Android permission, notification tap, background/Doze, and network-change workflows.
- Reliable notifications after Android process death; this needs a supported background delivery mechanism beyond the in-process LAN event stream.
- Physical desktop camera start/stop/pause/resume integration. Keyence SR-751 remote control remains unsupported.
- Windows release build and runtime verification on a Windows-capable runner.
- Production APK signing with the owner's existing production signing configuration. The release build used the repository's current debug signing setup.
