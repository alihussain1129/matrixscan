> Historical changelog: this document records an earlier implementation state. Current corrections (default command framing None/CR, FTP port 21/source port 20, and separate Data Port 1 handling) are documented in `docs/KEYENCE_IMPLEMENTATION_CORRECTIONS_20261118.md`.

# Exalted KEYENCE SR-751 automatic discovery changes

This is a focused source patch against the supplied KEYENCE audit snapshot.

## Changes

- Startup now tries a saved reader endpoint automatically when `autoConnect` is enabled.
- If the saved endpoint cannot be reached, the coordinator starts safe automatic discovery.
- Safe discovery tries saved endpoints, the possible `192.168.100.100` address, ARP neighbours, and a bounded private `/24` sweep on Ethernet interfaces only.
- The scan checks only the configured reader TCP port (default 9004), uses short connection timeouts, batches connection attempts, and observes the overall discovery time limit.
- Safe discovery sends no application payload and does not send `KEYENCE`, `LON`, `STAT`, `T1`, or any other command.
- A successful TCP connect is explicitly labelled **unverified**. It is not presented as proof that the endpoint is an SR-751.
- The saved scanner port is applied to discovery.
- A regression test verifies that startup connects to a saved endpoint without sending commands.

## Important limitations

- The supplied archive is a focused audit snapshot, not the complete MatrixScan repository. It omits required app/core files and platform project files, so the full Flutter suite and Windows build cannot be run from this snapshot.
- Dart and Flutter SDK executables are not available in this execution environment. Tests and `dart format` were therefore not run.
- No physical SR-751 is attached to this environment. Real-device discovery, barcode reception, and image transfer remain unverified.
- Automatic identification is intentionally not claimed. To identify the scanner rather than merely detect a reachable TCP endpoint, the SR-751's actual configured port and a documented, non-disruptive identity/status response must be verified against the official manual and the device configuration.
- The private `/24` sweep is a pragmatic fallback for direct Ethernet setups. If the PC interface uses a different subnet mask, the full subnet may not be searched. The app does not change the PC's IP configuration.

## Files changed

- `lib/features/devices/keyence/keyence_scanner_discovery_service.dart`
- `lib/features/devices/keyence/keyence_scanner_coordinator.dart`
- `test/keyence_listen_only_wiring_test.dart`
- `test/keyence_coordinator_config_test.dart`
- `docs/KEYENCE_SR751_HARDWARE_READINESS.md`
