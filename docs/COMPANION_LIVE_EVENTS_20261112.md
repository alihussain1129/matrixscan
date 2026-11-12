# Companion live event delivery — 2026-11-12

## Implemented

- Added an authenticated `GET /v1/companion/events` WebSocket endpoint. The existing TLS certificate fingerprint validation, HMAC request signature, timestamp window, and per-request nonce replay protection protect the upgrade request.
- Event messages carry durable journal cursors and stable record IDs. Pairing captures the initial journal cursor, and reconnects resume from the last persisted cursor. Events are replayed from the journal, exclude the receiving device's own records, and are deduplicated by the mobile controller.
- Added bounded concurrent streams, replacement of an older stream for the same device, periodic heartbeat frames, ping keepalive, and cleanup on disconnect/server stop.
- Added a pinned-TLS/HMAC mobile WebSocket client, reconnect backoff, cursor persistence, and periodic snapshot polling fallback. The companion UI distinguishes live event delivery from polling fallback in its connection details.
- Added a loopback TLS integration test that pairs a phone, saves a desktop record after stream subscription, and verifies the record and cursor arrive over the authenticated stream.

## Verification

- `flutter analyze`: passed (repository-wide).
- `flutter test test/link/link_core_test.dart`: passed, including the live WebSocket transport test.
- `flutter test`: passed, 692 tests.
- `flutter test test/companion_mobile_test.dart`: passed, 4 tests.
- `git diff --check`: passed.

## Remaining companion work

Android notifications and authorized remote scanner commands are not implemented in this change. Background notification delivery, Android release builds, and Windows release validation also remain outstanding. Do not treat this milestone as completion of the broader Windows/Android production-readiness request.
