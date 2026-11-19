> Historical changelog: this document records an earlier implementation state. Current corrections (default command framing None/CR, FTP port 21/source port 20, and separate Data Port 1 handling) are documented in `docs/KEYENCE_IMPLEMENTATION_CORRECTIONS_20261118.md`.

# KEYENCE protocol correction changelog — 2026-11-17

## Confirmed from the SR-750 Series User's Manual reference

- `KEYENCE` is a documented read-only model/system-version query.
- Its documented reply is `OK, KEYENCE, SR-***, <version>`; it does not include a serial number.
- Commands are sent with CR+LF; replies end in CR only.
- TCP command port and Data Port 1 default to 9004, but both interfaces default to RS-232C and must be switched to Ethernet for TCP operation.
- `LON`, `LOFF`, and `ERRSTAT` are documented. The previous guide's `T1`, `T2`, `PRG`, `FTPOUT`, `BEEP`, and `STAT` claims were not substantiated by the manual reference and are now blocked/disabled by default.
- The manual describes FTP active mode as the default, lists FTP service port 21, and lists active data port 20. Exalted's configured default remains 2121; this focused update adds PORT negotiation and retains PASV, but physical transfer and source-port compatibility remain unverified.

## Source changes in this focused snapshot

1. TCP command writes now use CRLF.
2. The identity parser requires the exact documented KEYENCE reply shape and parses the model/version from the correct fields.
3. Serial number remains unset rather than inferred from a non-existent field.
4. The application default command allow-list is `KEYENCE`, `ERRSTAT`, `LON`, `LOFF` only.
5. Discovery uses the read-only identity query when allowed and only accepts the documented response.
6. Discovery sweeps private IPv4 Ethernet `/24` candidates, not Wi-Fi/public interfaces; ARP candidates are filtered to private entries on recognized Ethernet interfaces.
7. Command envelopes such as `OK, ERRSTAT, none` and `ER, ...` are filtered from barcode data.
8. Automatic commissioning no longer sends `LOFF`, which could interrupt a production read.
9. Unverified UI controls for T1, BEEP and FTPOUT are disabled; the health query uses ERRSTAT.
10. The guide/readiness documents have been corrected and the remaining FTP port/source-port and physical-validation gaps are explicit.
11. The embedded FTP receiver now supports same-peer IPv4 PORT negotiation for active-mode uploads, while retaining PASV. A focused integration test covers active upload and rejects FTP bounce/privileged-port attempts.

## Validation status

- Source edits and focused tests were updated in the snapshot.
- Dart/Flutter are not installed in this execution environment, so `dart format`, `flutter analyze`, `flutter test`, and Windows build were not run.
- No physical SR-751 was connected; barcode, FTP, and production behavior are unverified.
- This is a focused audit snapshot, not the complete MatrixScan repository. Compare each file against the current working tree and back it up before integration.
