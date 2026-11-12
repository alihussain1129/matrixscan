# Exalted implementation report — 2026-11-12

## Delivered in this continuation

### Android companion notifications

- Added an Android `Desktop companion` notification channel and native notification bridge.
- Added runtime Android 13+ notification permission requests through the existing permission plugin. Notifications are opt-in and each category can be configured in Settings.
- Authenticated inspection events, scanner/desktop connection transitions, sync results, and remote command results can post notifications. Notification content omits scan strings and inspection payloads.
- Event identities are stored in app preferences and notification posting is serialized and deduplicated. Initial snapshot observation avoids notifying old activity; stream replay and polling fallback share the same deduplication store.
- Tapping a notification opens the Live Activity destination.

### Authorized remote camera scanner controls

- Added per-phone host authorization, disabled by default and persisted in the existing protected link-state store. Enabling it requires confirmation on the desktop and revocation continues to block the existing authentication path.
- Added signed, pinned-TLS `POST /v1/companion/commands` requests for start, stop, pause, and resume. The host validates the command and permission, checks revocation again before execution, rejects ID/action conflicts, and does not queue offline commands.
- The host invokes the existing desktop `ScannerController`. It confirms actual camera readiness or the requested stopped/paused/resumed state before returning `completed`; unavailable camera backends return a failure. This control applies to the desktop camera backend. Keyence SR-751 control is not implemented and is not represented as available.
- Command IDs and accepted/executing/final states are written to an append-only JSONL audit in the protected link directory. In-flight commands are marked failed after a desktop restart and cannot be replayed into a second execution. The desktop Link screen shows recent acknowledgements.
- The Android Overview has confirmation prompts and reports the server's result; controls are disabled without a fresh authenticated connection.

### Desktop and mobile UI

- Added host authorization controls and a remote-command history section to the existing linked-device workspace.
- Added Android remote scanner controls and notification preference controls to the existing mobile Overview/Settings destinations.
- Preserved the existing live-event transport, sync behavior, scanner/decoder code, and credential vault.

## Verification performed

- Full Flutter formatter check and repository-wide analysis: passed.
- Full Flutter test suite: passed (694 tests).
- Focused link, command replay/restart, store authorization, companion UI, linked-device UI, and settings tests: passed.
- Android debug APK: built.
- Android release APK: built with the repository's existing debug signing configuration. This is not a production-signed release.
- Linux release build: built.
- C++ targets rebuilt; eight native test executables passed (decoder, DotPeen, Utah traversal, encoder, Data Matrix symbol/info/placement/traversal). The project does not register tests with CTest, so they were executed directly.
- `git diff --check`: passed.

## Limits and remaining validation

- The command endpoint and persistence/replay behavior were integration-tested over loopback TLS using a deterministic test execution callback. The production provider is wired to the real `ScannerController`, but physical desktop-camera command execution was not tested on hardware.
- Android notification rendering, permission denial/regrant, notification taps, and background operation were not exercised on a physical device. Delivery uses the app's authenticated WebSocket/polling while its Flutter process is running; there is no push relay or Android foreground service to guarantee delivery after process death or deep Doze.
- Windows release/runtime validation was not run on this Linux host. The existing Windows CI configuration was not invoked in this pass.
- This pass adds the companion authorization, command, notification, and audit workflows to the existing desktop/mobile GUI. It does not claim the entire Windows/Android product redesign or hardware qualification is complete.
