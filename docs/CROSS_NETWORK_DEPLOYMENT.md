# Cross-network companion deployment

## Current capability

The checked-in companion service is an offline-first, local-network system. The
desktop serves pinned-certificate HTTPS, and a paired phone authenticates
requests with a per-device HMAC secret. Pairing advertises private IPv4
addresses. The server rejects peers outside the private/loopback address
ranges. This preserves local Wi-Fi and wired-LAN pairing; it does not connect
devices across NATs, cities, or unrelated networks.

There is currently no signaling service, STUN/TURN configuration, public
rendezvous endpoint, or relay deployment in this repository. A successful LAN
pairing must not be interpreted as cross-network support.

## Infrastructure required for cross-network operation

Cross-network support needs an independently deployed service and a transport
upgrade on both desktop and Android. The desktop should establish an outbound
authenticated session so the deployment does not require inbound port
forwarding. A signaling service exchanges short-lived ICE candidates. ICE first
tries a direct WebRTC data channel using STUN discovery, then uses TURN over
UDP/TCP/TLS when NAT or firewall policy prevents a direct path. A managed
relay can be used where TURN is unavailable, but it must forward only
application-encrypted frames.

The signaling and relay service must not become the history database. History,
OCR, inspection records, images, event journal, and synchronization cursor
remain on the paired endpoints. For any transport path that terminates TLS at
infrastructure, add application-level end-to-end encryption between the
paired endpoints; TLS to the relay alone does not prevent the relay operator
from reading records.

## Required trust and delivery properties

- Pairing remains owner-approved and one-time. The QR carries a short-lived
  rendezvous offer and the desktop certificate identity, never a reusable
  device secret.
- Endpoints authenticate one another using the existing pairing trust plus a
  newly specified, reviewed key agreement. Derive separate keys for event
  frames and blob transfers; bind device IDs, session ID, sequence number, and
  message type as authenticated data.
- Use authenticated encryption with replay protection. Rotate session keys
  and expire signaling offers. TURN credentials are short-lived and scoped to
  one session. Keep private credentials out of logs and client-visible error
  text.
- Relay frames retain durable journal IDs and cursors. The receiver validates
  and persists each event before advancing its cursor. Acknowledgements,
  duplicate suppression, and replay after reconnect remain endpoint-owned.
- Preserve local HTTPS as the preferred path. A failed or unavailable cloud
  rendezvous must not disable offline history or local-network sync.

## Deployment checklist

1. Operate a public HTTPS/WSS signaling endpoint with abuse controls, request
   limits, short-lived session tokens, and no record/blob persistence.
2. Operate redundant STUN and TURN endpoints. Enable TLS TURN for restrictive
   corporate networks; issue per-session credentials from an authenticated
   endpoint and rotate the TURN shared secret.
3. Configure desktop and Android with the service URL at build/release time.
   Do not embed TURN shared secrets or long-lived relay credentials in either
   application.
4. Add a versioned encrypted-frame protocol and retain the existing
   local-network protocol for backward compatibility during rollout.
5. Test direct ICE, TURN fallback, cellular-to-Ethernet, network changes,
   desktop sleep/restart, app background/termination, revoked devices, replay,
   malformed frames, and interrupted large-image transfer.
6. Monitor connection success, route type, latency, and byte counts without
   recording OCR content, image data, pairing secrets, authentication headers,
   or encryption keys.

No service endpoint, TURN credentials, or deployment account is configured in
this source tree. Until that infrastructure and the endpoint transport are
implemented and tested, cross-network pairing and synchronization remain
unavailable. Local pairing and synchronization continue to work without cloud
login.
