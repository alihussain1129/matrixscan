# KEYENCE SR-750 / SR-751 Integration Guide

Version: 1.2.0 (separate data channel and FTP corrections; physical hardware not yet validated)
Product: Exalted Industrial Machine Vision Platform
Target: KEYENCE SR-750 Series, including SR-751

> This guide distinguishes documented SR-750 protocol facts from Exalted's
> current implementation. A simulator passing tests is not proof of physical
> scanner compatibility.

## 1. Network and hardware

The SR-751 supports 10BASE-T/100BASE-TX Ethernet and PoE Type A/B. It can also
be powered through the control port at 24 VDC ±10%; do not use both power
methods simultaneously.

Documented Ethernet defaults:

- Reader IP: `192.168.100.100`
- Subnet: `255.255.255.0` (`/24`)
- Gateway: `0.0.0.0`
- Holding TUNE for at least 5 seconds enters temporary IP-address setting mode.

These are defaults, not proof of the settings on a used reader. Exalted must
not change the host PC's primary network settings automatically. Confirm the
actual reader address, power, cable and link LEDs first. Set the Command Port
header/terminator to `None / CR`.

## 2. TCP socket protocol

The SR-750 manual documents TCP socket communication.

| Function | Factory default | Notes |
|---|---:|---|
| Command Port | TCP 9004 | Reader listens; control host connects |
| Data Port 1 | TCP 9004 | Read-data output; server/client behavior is configurable |
| FTP service | 21 | FTP service port listed by the manual |
| FTP active data | 20 | Active FTP data port |

Command Port and Data Port 1 can share TCP port 9004 or use different configured
ports. Crucially, both interfaces default to RS-232C. Ethernet must be selected
in the reader's Communication 2 settings before Exalted can use them over TCP.
Exalted supports Data Port 1 in reader-as-server mode (the reader listens and
Exalted connects); set the reader's Data Port 1 Remote IP to `0.0.0.0` for
server-only operation. Reader-as-client mode is not implemented.

### Command framing

- Command header/terminator factory default: no header / CR. Exalted sends ASCII command bytes ending with CR only.
- Responses use the same header/terminator framing as the command.
- The alternate STX/ETX framing mode is not implemented.
- Default read-data header: none.
- Default read-data terminator: CR.

### Documented commands used by Exalted

| Command | Documented purpose | Exalted policy |
|---|---|---|
| `KEYENCE` | Return model and main-unit system version | Read-only; used for discovery/identity |
| `ERRSTAT` | Obtain reader error status | Read-only; allowed |
| `LON` | Timing ON / start read operation | Operator-triggered only |
| `LOFF` | Timing OFF / finish read operation | Operator-triggered only |
| `RN` / `WN` | Read/write communication configuration | Not sent automatically; configuration changes require review |
| `SAVE` | Persist communication configuration changes | Not sent automatically |

The documented `KEYENCE` response is:

```text
OK, KEYENCE, SR-***, <main-unit-system-version>
```

The response does not contain a serial number. Exalted therefore leaves the
serial-number field empty rather than inventing one.

The following commands previously shown in this guide are not established by
the SR-750 User's Manual reference used for this implementation and remain
blocked/disabled in the app: `T1`, `T2`, `PRG`, `FTPOUT`, `BEEP`, `STAT`, and
other guessed command names. Do not use them on production hardware.

## 3. Exalted's current TCP behavior

- Saved command endpoint is tried first when startup auto-connect is enabled.
- Command Port is verified with the read-only `KEYENCE` query.
- If Data Port 1 equals the command port, the same TCP connection carries
  command responses and read data. If it is configured separately, Exalted
  opens a second listen-only TCP connection to Data Port 1; it sends no
  commands on that connection.
- For this client connection mode, configure the reader's Data Port 1 as an
  Ethernet server (remote IP `0.0.0.0`). Reader-as-client mode, where the
  scanner initiates a connection to Exalted, is not implemented.
- Discovery checks the documented default address, saved endpoints, ARP
  neighbours, and private Ethernet `/24` candidates on the configured command
  port. It verifies candidates with the documented identity response.
- An explicitly empty command allow-list retains connect-only mode.
- TCP reconnection uses exponential backoff.
- The current subnet sweep assumes `/24`; it does not yet read every platform's
  actual interface prefix/netmask. Discovery is therefore best-effort, not
  guaranteed to find every configured address.

## 4. FTP image transfer: not yet hardware-ready

The SR-750 manual documents FTP client/server operation. FTP image transfer
requires the reader's saving and FTP settings to be configured. The manual
lists FTP service port 21, active data port 20, and says passive mode defaults
to disabled. The reader's FTP client credentials default to `admin` / `admin`.

Exalted's embedded receiver supports authenticated `USER`/`PASS`, binary
`TYPE I`, `STOR`, passive `PASV`, and active `PORT` negotiation. Its default
control port is now `21`; active data connections request local source port
`20`, matching the manual's port table. Active mode restricts the advertised
data address to the control peer and rejects privileged client data ports to
reduce FTP bounce risk.

On Linux, binding local ports 20 and 21 may require `CAP_NET_BIND_SERVICE`.
Do not run Exalted as root. Use a reviewed, least-privilege system capability
or approved OS-level port forwarding. Android may not be able to bind these
ports under the normal app sandbox. The receiver reports a bind/transfer error
rather than silently claiming success.

The SR-750 FTP client defaults its remote directory name to `image`. Exalted
accepts a safe single-segment virtual directory such as `image`; the uploaded
file is stored in Exalted's managed media storage, never under a client-supplied
filesystem path.

Image transfer remains unverified until an actual SR-751 upload succeeds.
Configure the scanner's FTP destination to the PC's Ethernet address, confirm
active/passive mode and credentials, and test a real image before production
use. The receiver refuses to start unless explicit credentials are configured.

## 5. Inspection pipeline status

Exalted contains barcode, FTP image, OCR/OCV and history pipeline components.
However, image/barcode association by arrival order is not a verified
transaction key. Production use requires a stable correlation mechanism and
physical validation of image delivery, file format, read timing and OCR output.

## 6. Hardware validation sequence

1. Confirm scanner power and Ethernet link.
2. Confirm actual IP/subnet and PC routing without changing host networking.
3. Confirm Command Port and Data Port 1 are configured for Ethernet.
4. Verify the documented identity response from `KEYENCE`.
5. Verify a real barcode arrives on Data Port 1 with the configured framing.
6. Test `LON` / `LOFF` only in a safe machine state.
7. Resolve FTP port and active/passive compatibility, then test a real image.
8. Validate barcode/image correlation, OCR/OCV and durable inspection history.

No physical SR-751 test is claimed by this guide.
