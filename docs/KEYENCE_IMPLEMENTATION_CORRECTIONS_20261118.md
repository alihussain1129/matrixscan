# Exalted implementation corrections — 2026-11-18

This change set addresses source-level defects found in the complete source
snapshot. It does **not** claim that a physical KEYENCE SR-751 has been tested.

## KEYENCE networking

- The configured `dataPort` was previously persisted but never consumed.
  The coordinator now treats Command Port and Data Port 1 separately:
  - equal ports reuse one connection;
  - different ports open a second listen-only TCP client;
  - no application commands are sent on the Data Port 1 connection;
  - barcode events from either subscribed channel use the same classifier and
    scanner/history pipeline.
- Manual connection setup now exposes Data Port 1. Leaving it blank reuses the
  command port. A successfully verified profile persists the distinct port.
- The supported Data Port 1 topology is reader-as-server (Exalted connects to
  the reader). Reader-as-client mode is not implemented.
- Outgoing command framing now follows the manual's default no-header / CR terminator (not CRLF); incoming CR, LF and CRLF line endings remain tolerated.
- Identity replies now require exactly the documented four fields. A barcode
  or unrelated status line received while the identity query is pending no
  longer consumes the handshake response.
- The command sender rejects embedded CR/LF and control bytes, and the
  production allow-list rejects arguments on the permitted commands. This
  prevents an allowed command name from carrying an extra command line.
- Discovery now applies its configured timeout to each probe batch and does
  not report a timed-out scan as a successful completion. The existing `/24`
  sweep limitation remains.
- Commissioning reuses an existing live command connection rather than opening
  a second command socket. Its result is described as command-channel
  verification, not production readiness; Data Port 1, trigger behavior and
  real FTP transfer remain separate hardware checks.

## FTP image receiver

- New-install default control port is TCP `21`, matching the SR-750 manual.
  The port is editable and persisted in Settings > FTP Receiver.
- Active-mode data sockets request local source port `20`, matching the
  documented active FTP data port. The data connection still validates the
  peer address and rejects privileged advertised client ports.
- Common FTP negotiation commands `OPTS UTF8 ON`, `CLNT`, `STRU F`, `MODE S`,
  `CWD`, `CDUP`, `MKD` and `ALLO` are handled. The SR-750's default remote
  directory `image` is accepted as a safe virtual directory; client paths are
  never used as filesystem paths. Image uploads require binary `TYPE I`.
- Startup failures now retain a diagnostic reason instead of being reduced to
  a generic missing-credentials message.
- Linux binding of ports 20 and 21 may require `CAP_NET_BIND_SERVICE`. Do not
  run Exalted as root. Android's normal app sandbox may prevent this setup.

## Exalted design system and shells

- `ExaltedSuccessBurst`, `ExaltedShimmer`, `ExaltedStagger`, the selected
  bounce icon and the scanner laser respect reduced-motion changes without
  running hidden animation loops.
- `ExaltedSegmented` safely handles an empty options list and an unknown
  selected value; it no longer divides by zero or falsely highlights option 1.
- Removed the unreachable compact-phone navigation branch from the desktop
  shell. `AppShell` continues to select `MobileShell` on Android/iOS and
  `ExaltedShell` on Windows/Linux.
- Verified that the four font files referenced by the offline typography setup
  are present under `assets/google_fonts/`.

## Regression tests added or updated

- Separate command/Data Port 1 connection and barcode routing.
- No command bytes sent on the listen-only data connection.
- Command framing injection rejection and strict identity response shape.
- Interleaved barcode during handshake.
- FTP active data source-port selection and default control port.
- FTP listener-port settings persistence.
- Reduced-motion and segmented-control edge cases.
- Commissioning does not reconnect an already active command socket.

## Remaining hardware / platform verification

1. Verify Command Port and Data Port 1 Ethernet/server settings on the actual
   reader. The reader's factory defaults are not proof of its current settings.
2. Verify a real barcode arrives through Data Port 1, both when it shares the
   command port and when it is separate.
3. Verify FTP authentication and one real image upload in the reader's actual
   active/passive configuration. On Linux, verify the least-privilege port
   binding setup first.
4. Verify the installed Windows and Android builds. Reader-as-client mode,
   non-`/24` discovery, and barcode/image transaction correlation remain
   outside this patch.

## Validation status

The editing environment used to prepare this patch does not contain Flutter or
Dart executables. Therefore `flutter analyze`, the Flutter test suite, and
platform builds have **not** been run here. Run the commands in the handoff
instructions after applying the patch; do not treat simulator tests as physical
hardware evidence.
