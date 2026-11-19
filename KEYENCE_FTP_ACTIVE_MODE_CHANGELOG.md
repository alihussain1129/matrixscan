> Historical changelog: this document records an earlier implementation state. Current corrections (default command framing None/CR, FTP port 21/source port 20, and separate Data Port 1 handling) are documented in `docs/KEYENCE_IMPLEMENTATION_CORRECTIONS_20261118.md`.

# KEYENCE FTP active-mode implementation — 2026-11-17

- Added FTP `PORT h1,h2,h3,h4,p1,p2` command parsing.
- Restricts the advertised IPv4 address to the control connection peer.
- Rejects data ports below 1024 and malformed PORT arguments.
- For `STOR`, Exalted opens the active data connection to the validated peer endpoint.
- Retains passive `PASV` uploads.
- Advertises `PORT` and `PASV` in `FEAT`.
- Added focused tests for a same-host active upload and rejected bounce/privileged-port endpoints.

## Limitations

- The configured receiver default remains TCP 2121 in this snapshot; the SR-750 manual lists FTP service port 21. The complete repository's app-config defaults and UI must be reconciled before hardware use.
- The OS-selected source port for the active data connection has not been verified against the reader's expected active-FTP behavior.
- No physical SR-751 transfer has been tested. FTP remains NOT hardware-ready.
- Dart/Flutter tooling is unavailable in this environment; tests and formatting have not been run.
