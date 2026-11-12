# KEYENCE SR-751 hardware readiness

Labels: [REPO] read from Exalted's code. [GUIDE] claimed by
docs/KEYENCE_SR751_GUIDE.md, not checked against the official manual.
[CONFIRM] must be read from the SR-750 series manual or the reader itself.
[ASSUMED] a reasonable guess, unverified. Nothing here has been tested on a
physical reader.

## First-contact rules
- Read-only. No reset, no IP change, no mode change, no program (PRG) change,
  no "Send Configuration", no overwriting of settings.
- Send no command to the reader until its exact form is confirmed from the manual.
- Back up the reader's current configuration before anyone changes anything.

## 1. Power and Ethernet
- [GUIDE] 24 VDC (+/-10%) through the I/O cable. [CONFIRM] supply current, I/O
  cable pinout and part number. Use a regulated supply, not a PC port.
- [GUIDE] M12 D-coded Ethernet. [CONFIRM] connector type and link speed.
- [ASSUMED] A direct PC-to-reader cable works; a small unmanaged switch on an
  isolated network is the safer first setup.

## 2. Finding the reader's IP address (read-only)
1. [CONFIRM] Read it from the unit's label, display, or the person who set it up.
2. Watch passively while the cable is plugged in:
   `sudo tcpdump -i <interface> -n arp`, then `ip neigh`.
3. [CONFIRM] Open KEYENCE's configuration software and only view the settings.
4. [GUIDE] The guide names 192.168.100.100 as a default. [CONFIRM] before relying on it.
5. Do not port-scan. Do not change the PC's main address. If the PC must share
   the reader's subnet, add a temporary secondary address on the PC only
   (`sudo ip addr add <addr>/<mask> dev <interface>`, undo with `ip addr del`).

## 3. TCP command and barcode-data link
- [REPO] Exalted is the TCP client. Host and port come from the device
  identity; there is no built-in default. 9004 is only a suggestion.
- [GUIDE] Reader is a TCP server on 9004 with a CR delimiter.
- [CONFIRM] Server or client mode, port, delimiter, header/footer, whether
  data and commands share one port, the command list and every reply format.
- [REPO] `receiveTerminator` (CR, LF, CRLF) is a device setting; unset accepts
  all three.
- [REPO] Commands present in code but unverified: LON, LOFF, T1, T2, PRG,
  FTPOUT, BEEP, KEYENCE, STAT, RESET.
- [REPO] Replies are classified by `Sr751ReplyProfile`. The default profile
  treats every non-error line as barcode data; command replies cannot be
  separated until real reply formats are configured.

## 4. FTP image transfer
- [REPO] The receiver listens on 2121 on all IPv4 interfaces. It supports
  USER/PASS, PASV, STOR, TYPE, QUIT. PORT is not implemented, although the
  guide lists it. Allowed extensions: jpg, jpeg, png, bmp, tif, tiff. Upload
  cap is 20 MB. Data connections must come from the control client's IP.
- [REPO] The default provider sets no credentials, so any login is accepted.
  Credential storage needs a decision (secure-storage dependency).
- [REPO] Passive data ports are chosen by the OS, so a firewall rule needs a
  fixed port range (not implemented).
- [GUIDE] The reader logs in as exalted/exalted, directory "/".
- [CONFIRM] Passive or active mode, file naming, when it sends (on read, on
  failure), image format, and whether any field links an image to its read.
  Without such a link, pairing a barcode with an image by arrival time is a guess.

## 5. Configuration software
- [GUIDE] "AutoID Navigator". [CONFIRM] exact product name, version, and
  operating system support for the SR-750 series. [ASSUMED] it is
  Windows-only, so a Windows machine on the reader's network may be needed.
- Use it to view and export the current configuration first.

## 6. RS-232C (later, design only)
- Add a small transport interface (open, close, write bytes, bytes stream).
  The TCP client becomes one implementation, serial another.
- Reuse `MessageFramer`, `Sr751MessageClassifier` and the adapter unchanged.
- [CONFIRM] baud rate, data bits, parity, stop bits, flow control, delimiter.
- A serial package is a new dependency and needs approval first.

## 7. Test ladder
- G0 Offline: simulated loopback tests only (done; not hardware evidence).
- G1 Power and link light only. Nothing sent.
- G2 IP discovery (section 2).
- G3 Connect-only capture: connect, send nothing, log timestamped bytes
  (hex and text). Trigger reads with the reader's own trigger.
- G4 First command, only after it is confirmed from the manual, one at a time.
- G5 FTP image transfer, after the reader's FTP settings are set by the user
  in the configuration software.
- G6 Full pipeline.
