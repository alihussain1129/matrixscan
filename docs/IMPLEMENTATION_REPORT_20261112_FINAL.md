# Exalted final GUI and release-readiness report

Date: 2026-11-12

## Implemented in this pass

- Added a searchable desktop workspace palette, opened by the toolbar's **Go to** action or `Ctrl+K`. It covers Dashboard, Scanner, Decode & OCR, History, Devices, Synchronization, Verification, Diagnostics, Settings, Inspection, and image import for OCR. Existing `Ctrl+digit` navigation remains available.
- Added a phone overview **Quick tools** row that directly opens Scanner, Decode & OCR, Inspection, and Verification, including when the companion has no desktop connection. The destinations reuse the existing mobile screens and navigation state.
- Added external Android release signing inputs: `EXALTED_ANDROID_KEYSTORE`, `EXALTED_ANDROID_STORE_PASSWORD`, `EXALTED_ANDROID_KEY_ALIAS`, and `EXALTED_ANDROID_KEY_PASSWORD`. When all are supplied, release uses that keystore. Set `EXALTED_REQUIRE_PRODUCTION_SIGNING=true` to make Gradle fail clearly if any are missing. With no external credentials, a normal release build still uses the existing debug key for development; it is not production signed. No key or password is stored in the repository.
- Fixed phone-width Settings information rows: they stack label and value on narrow screens and use columns on wider screens. Added a 411-pixel widget regression test after emulator inspection exposed overflow and cramped wrapping.
- Corrected Android notification preference defaults so the global “Desktop notifications” setting starts off, matching the service's opt-in state. Added a preference regression test.
- Fixed FTP passive-mode replies when Windows reports the wildcard listener address for loopback connections. PASV now advertises `127.0.0.1` for a loopback peer; for a wildcard listener and one unambiguous non-loopback IPv4 interface it uses that interface, and fails closed with a configuration hint when the address is ambiguous. The real reconnect test now waits for ten retry attempts (up to five seconds) rather than assuming they occur within 800 ms.
- Existing desktop and phone shells already supply separate responsive navigation, operational dashboards, history, scanner, OCR, inspection, verification, devices, synchronization, diagnostics and settings workflows. This pass adds to that shell without replacing those features.

## Verification performed

- `flutter analyze`: passed, no issues.
- `flutter test`: passed, 696 tests.
- `git diff --check`: passed.
- Eight existing native C++ test executables: passed.
- Android Gradle production-signing gate: verified to reject missing credentials with the required variable names and without printing signing values.
- Android debug APK: built successfully (`build/app/outputs/flutter-apk/app-debug.apk`).
- Android release APK: built successfully (`build/app/outputs/flutter-apk/app-release.apk`, 97.6 MB), using the debug key. It is explicitly **not production signed**.
- Linux release: built successfully (`build/linux/x64/release/bundle/exalted`).
- Focused FTP and reconnect integration tests passed locally: `keyence_ftp_hardening_test.dart`, `keyence_ftp_receiver_test.dart`, and `keyence_sr751_client_robustness_test.dart`.

## Real-world validation performed

- Android emulator: AVD `Medium_Phone_API_37.0`, `sdk_gphone64_x86_64`, Android release 17, API 37. This is an emulator, not a physical device.
- App installed and launched; Overview quick tools rendered. Scanner navigation opened the live emulator camera after granting camera access. No fatal crash was observed.
- Settings → General was visually inspected. Before the fix, the card overflowed horizontally and its rows were cramped; after the fix the rows stack legibly and no Flutter overflow/fatal-crash lines appeared in the checked logcat window.
- Notification settings were exercised in-app. The global setting was initially off. Denying `POST_NOTIFICATIONS` left it off and displayed the Android settings guidance. A subsequent request was accepted; Android reported the permission granted and the app switch on.
- No desktop was paired to this AVD, so no real event notification, notification tap routing, live companion stream, remote command, sync, or cursor recovery could be exercised end to end.

## Windows CI evidence and remaining scope

- GitHub Actions run [Exalted Windows Release #10](https://github.com/alihussain1129/matrixscan/actions/runs/42779661377) succeeded on commit `9df0975db4f322c2d9bdafdc16d292031ef7ec76`. It ran selected OCR tests, Windows x64 release compilation, Tesseract packaging, and installer packaging. It did not launch the app or test camera, pairing, WebSocket, remote controls, or persistence.
- GitHub Actions run [windows #2](https://github.com/alihussain1129/matrixscan/actions/runs/42779661364) on the same commit failed five tests: four FTP passive-mode tests received `0.0.0.0` from PASV; the reconnect integration assertion expected more than ten attempts after a fixed 800 ms. Targeted fixes and corresponding tests now pass on Linux, but the updated local workspace has not yet run on Windows.
- The current working tree contains extensive uncommitted modifications and untracked files relative to that commit. The remote CI result therefore validates the prior committed source, not the exact current workspace. This host is Linux and has no Windows runtime/compiler environment; no Windows application startup or hardware validation is claimed.

## Android delivery guarantees

- **Foreground:** the app can receive authenticated events while its process is active and the desktop is reachable.
- **Background, process retained:** the event socket may remain alive, but Android Doze/OEM policy can suspend or terminate it. No persistent foreground service keeps it alive.
- **After process termination:** no delivery occurs until the app is started again and reconnects. The stored cursor and event IDs support deduplication/recovery on reconnect, but require the paired desktop to retain and serve events.
- **No network:** delivery cannot occur. Recovery depends on later network restoration, app execution, desktop availability, and retained events.
- WorkManager is suitable for deferred reconciliation, not immediate event push. A foreground service would need an explicit user-visible start/stop mode, ongoing notification, applicable service type/permissions, and physical-device testing. Guaranteed wake-up after process death requires a push backend plus authenticated device registration and server infrastructure; neither exists in this project. No delivery guarantee is claimed.

## Not verified on this host

- No physical Android phone was attached. The emulator checks do not establish device-specific camera behavior, Doze delivery, lock-screen behavior, OEM battery policy, notification-tap routing, app process death/restart, remote command execution, revocation, or offline recovery.
- Keyence SR-751 supports the existing `LON` trigger/read, `LOFF` stop-reading, and `T1`/`T2` software-trigger methods. `sendCommand` success means the socket write succeeded; it is not a device-level acknowledgement. These do not map to desktop camera pause/resume, and no new remote companion Keyence command was added.
- Production signing is configured but not completed because the owner-managed keystore and credentials were not supplied. The source tree contains no production signing material.

## Owner actions for production

Supply the four signing environment variables in a protected release environment, set `EXALTED_REQUIRE_PRODUCTION_SIGNING=true`, and run a release build there. Rerun the Windows workflows on the current source and perform Windows interactive/hardware checks. Complete the physical Android test matrix. For delivery after process termination, provide an authenticated push service/backend or productize an explicit foreground connection mode with a persistent notification and device testing.

## Background delivery reference

- Android documents WorkManager as persistent scheduled work whose exact execution depends on constraints and system optimization: [WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent).
- Android requires a foreground service to be launched under the applicable restrictions and, for modern target SDKs, with the right service type/permissions: [Launch a foreground service](https://developer.android.com/develop/background-work/services/fgs/launch), [Background start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start).
