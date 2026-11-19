# KEYENCE SR-750 / SR-751 protocol implementation notes

## Evidence used

The SR-750 Series User's Manual (Rev. 8.0, sections 7-4, 7-5, 8-1 and 8-2) documents the following behavior. The SR-751 is part of the SR-750 Series.

- Ethernet uses TCP for socket communication.
- Factory Ethernet address: `192.168.100.100`, subnet `255.255.255.0`, gateway `0.0.0.0`.
- Holding TUNE for at least 5 seconds enters temporary IP-address mode.
- The command port is a TCP server port. Factory default is `9004`.
- Data Port 1 can be a TCP server or client. Factory default port is `9004`; command and data can share that port when configured that way.
- Command and Data Port 1 interfaces default to RS-232C, not Ethernet. Ethernet must be selected in the reader configuration for TCP command/read-data use.
- The documented identity command is `KEYENCE`; the response is `OK, KEYENCE, SR-***, <main-unit-system-version>`. It does not return a serial number.
- Commands are ASCII. The command terminator is CR with LF appended (`\r\n`); responses terminate with CR (`\r`, no LF).
- `LON` and `LOFF` are documented timing ON/OFF commands. `ERRSTAT` is the documented error-status query.
- The default read-data terminator is CR. Header defaults to none.
- FTP supports image transfer; FTP image transfer depends on reader-side saving/FTP configuration. The reader can operate as FTP client or server. The manual documents FTP server anonymous access and up to two simultaneous connections.

## Implemented in the 2026-11-18 source snapshot

1. The SR-750 manual's default command framing is no header plus CR terminator. Exalted sends CR-only commands and tolerates CR, LF, or CRLF on receive. STX/ETX mode is not implemented.
2. Identity handshake now requires the exact documented `OK, KEYENCE, SR-***, version` response. It no longer accepts generic TCP banners or assumes the first response field is the model.
3. Serial number is left unset because the documented identity response does not contain one.
4. Default app allow-list permits only `KEYENCE`, `ERRSTAT`, `LON`, and `LOFF`. Configuration-changing and unverified commands remain blocked.
5. Discovery uses the documented read-only identity command when allowed; explicitly empty command allow-lists retain connect-only mode. The application default allow-list contains only `KEYENCE`, `ERRSTAT`, `LON`, and `LOFF`.
6. Command Port and Data Port 1 are handled separately when configured with different ports. The command connection performs identity verification; the second Data Port 1 connection is listen-only. If both ports match, the command connection is reused. The supported Data Port 1 topology is reader-as-server; reader-as-client mode is not implemented.
7. Automatic discovery includes a private IPv4 `/24` Ethernet sweep. This is a known limitation: the current cross-platform implementation does not read the real interface prefix/netmask, so non-/24 subnets may be missed.
8. UI controls for `T1`, `BEEP`, and `FTPOUT` are disabled until their exact SR-751 command semantics are verified. Automatic commissioning does not send `LON` or `LOFF` because those can alter an active production read.
9. The FTP receiver now defaults to TCP 21 and requests local source port 20 for active-mode data connections. The listener port is configurable in Settings > FTP Receiver. Binding ports below 1024 may require a system capability on Linux; never run Exalted as root.

## Still not verified

- Physical SR-751 connection, barcode delivery, reconnect behavior and image transfer.
- The user's actual scanner IP, subnet, command-port setting, Data Port 1 setting and FTP settings.
- Robust subnet enumeration for non-/24 networks and Windows interface-prefix discovery.
- Physical Data Port 1 delivery, reconnect behavior, and reader-as-client topology.
- The FTP receiver's compatibility with the reader's actual FTP mode, OS privileged-port binding, and real image upload behavior.
- Any command not listed above. Do not send guessed commands or change reader configuration automatically.

## Operational setup required

For Exalted to receive barcode data, configure the reader's Command Port and Data Port 1 interfaces as Ethernet and set Data Port 1 to server mode (remote IP `0.0.0.0`). Set the command and data ports to the same value or enter the separate Data Port 1 port in Exalted. Configure the reader's read-data output. If the scanner is still at factory network settings, the documented default address is `192.168.100.100/24`; the PC must be on the same subnet. Do not change the PC's network settings automatically.
