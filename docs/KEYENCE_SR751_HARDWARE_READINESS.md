# KEYENCE SR-751 hardware readiness

Labels: [CODE] read from this Exalted source snapshot. [MANUAL] supported by the
SR-750 Series User's Manual (Rev. 8.0; applies to SR-751). [VERIFY] must be
confirmed on the actual reader because its current configuration is unknown.
Nothing in this document claims a physical SR-751 test has passed.

## First-contact rules
- Do not reset the reader, change its IP, change operating mode, alter banks,
  send configuration, or overwrite reader settings automatically.
- Discovery may send only the documented read-only `KEYENCE` identity query.
- `LON` and `LOFF` are documented operational controls, but are sent only after
  an explicit operator action. Automatic commissioning must not trigger or
  stop a production read.
- Back up the reader's current configuration before any user-approved change.

## 1. Power and Ethernet
- [MANUAL] SR-751 supports 10BASE-T/100BASE-TX and PoE Type A/B. The control
  port can alternatively be powered at 24 VDC ±10%; do not apply both power
  methods simultaneously.
- [MANUAL] Ethernet defaults: `192.168.100.100`, subnet
  `255.255.255.0` (`/24`), gateway `0.0.0.0`.
- [MANUAL] Holding TUNE for at least 5 seconds enters temporary IP-address
  setting mode.
- [VERIFY] Confirm the unit's actual power method, link LEDs, IP and subnet.
  Do not change the PC's main network configuration automatically.

## 2. TCP command and barcode-data link
- [MANUAL] Socket communication uses TCP.
- [MANUAL] Command Port and Data Port 1 have factory-default port `9004`.
  They can share the port when configured that way, or be assigned different
  ports. Command Port is server-only; Data Port 1 supports server/client mode.
- [MANUAL] Important: Command Port and Data Port 1 interfaces default to
  RS-232C. Ethernet must be selected in Communication 2 before TCP command or
  barcode-data communication can work.
- [MANUAL] `KEYENCE` is the read-only model/version identity command. Expected
  response: `OK, KEYENCE, SR-***, <main-unit-system-version>`. This response
  does not include a serial number.
- [MANUAL] The default command header/terminator is no header / CR. Responses
  use the same framing as the command. Exalted sends CR-only commands and
  accepts CR, LF or CRLF response line endings. Default read-data header is none and
  default read-data terminator is CR.
- [MANUAL] `LON` / `LOFF` are timing ON/OFF controls. `ERRSTAT` obtains the
  reader error status. `SAVE`, `WN`, and `RN` are documented configuration
  commands; Exalted does not send configuration commands automatically.
- [CODE] Default app allow-list permits only `KEYENCE`, `ERRSTAT`, `LON`, and
  `LOFF`. `LON`/`LOFF` are available only through explicit operator controls.
  Unverified commands remain blocked; CR/LF injection is rejected.
- [CODE] Command Port and Data Port 1 are now separate settings. When the ports
  differ, Exalted opens a second listen-only TCP connection to Data Port 1 and
  routes barcode messages from that connection. When they match, one connection
  is reused. No commands are sent on the data connection.
- [CODE] The supported Data Port 1 topology is reader-as-server (Exalted
  connects to the reader). Reader-as-client mode is not implemented.
- [CODE] Discovery checks saved endpoints, the documented default address,
  ARP neighbours, and private IPv4 Ethernet `/24` candidates on the configured
  command port. It verifies candidates using the exact `KEYENCE` response
  shape. An explicitly empty allow-list retains connect-only mode.
- [VERIFY] The actual command/data port, interface mode, data output format,
  header/terminator and whether both channels share one port must be checked
  on the reader.
- [LIMIT] The current automatic sweep assumes `/24` and recognises Ethernet
  interfaces by common interface-name prefixes. It may miss non-`/24` networks
  or interfaces with unusual names. Windows and Linux physical discovery still
  need runtime validation.

## 3. FTP image transfer: implementation corrected; hardware still unverified
- [MANUAL] The SR-750 supports FTP client and FTP server operation. Its FTP
  service port is listed as `21`; active FTP data uses port `20`. Passive mode
  is a configurable reader setting and defaults to disabled.
- [MANUAL] The reader's FTP client defaults to username/password `admin` /
  `admin`. FTP server mode on the reader is documented as anonymous, with up
  to two simultaneous connections.
- [CODE] Exalted's embedded receiver supports authenticated `USER`/`PASS`,
  binary `TYPE I`, `PORT` active-mode negotiation, `PASV`, and `STOR`. Active
  mode only accepts the control peer's IP and an ephemeral advertised client
  data port. The outgoing active data socket requests local source port `20`.
- [CODE] The default FTP control/listener port is now `21`, matching the manual.
  The listener port is configurable in Settings > FTP Receiver. The reader's
  default remote directory (`image`) is accepted as a safe virtual FTP folder;
  uploaded files still go to Exalted-managed media storage.
- [VERIFY] Image upload is still NOT hardware-ready. Verify that the OS permits
  binding local ports 20 and 21, that the scanner is configured with the PC's
  correct FTP destination address and credentials, and that a real image upload
  succeeds. On Linux, privileged-port binding may require a narrowly scoped
  `CAP_NET_BIND_SERVICE`; do not run Exalted as root. Android app sandbox
  restrictions may prevent this configuration. The receiver refuses to start
  without configured credentials.
- [CODE] Image/barcode pairing by arrival order is not a verified transaction
  correlation mechanism. A stable device-side identifier or timing protocol
  is still required for reliable production traceability.

## 4. Configuration software
- KEYENCE's official SR-750 support portal lists the User's Manual, Additional
  Function Manual, Script Reference and Instruction Manual. AutoID Network
  Navigator may be used for initial configuration, but it is not required as
  an Exalted runtime dependency.
- Use the configuration software to inspect and export current settings first.
  Do not transmit changed settings until they have been reviewed and backed up.

## 5. Test ladder
- G0 Offline: simulator tests only. This is not physical hardware evidence.
- G1 Power/link: confirm power method and Ethernet link LEDs.
- G2 Network: confirm actual reader IP/subnet and same-subnet PC route.
- G3 Identity: verify TCP connection and the documented `KEYENCE` response.
- G4 Data: configure Data Port 1 as Ethernet and verify a real barcode arrives
  with the configured header/terminator.
- G5 Controls: test `LON` and `LOFF` only in a safe machine state with an
  operator present.
- G6 FTP: first resolve active/passive mode and port compatibility, then test
  one real image upload and inspect its bytes/file format.
- G7 Pipeline: verify barcode/image correlation, OCR/OCV and durable history.

Physical SR-751 connection, barcode delivery, reconnect, and image transfer
remain unverified until the above steps are completed on the actual unit.
