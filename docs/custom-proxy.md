# Custom SOCKS5 proxy

Native iOS/Android settings and the welcome screen expose one editable,
device-wide SOCKS5 profile: host, port, optional username/password, enabled.
The Web build deliberately hides this feature; browsers manage their own proxy.
MTProto and HTTP CONNECT proxies are not supported by this feature.

API calls (including login, contact/group/channel lists, uploads, downloads and
backups) and the realtime WebSocket share the routing policy. Target DNS goes
through SOCKS5. The proxy hostname itself is resolved locally. HTTPS/WSS and
normal certificate validation remain mandatory in proxy mode; there is no
automatic direct fallback. Switching policy closes old HTTP and WebSocket
connections. A successful settings save is not reported as a successful test.
The test probes the configured Privio API without an account token.

Proxy credentials live in platform secure storage, not account backups or logs.
SOCKS5 username/password authentication itself is NOT encrypted. Users must trust
the path to their proxy. Proxies observe source IP, destination, timing and size.
This is not a VPN or an anonymity guarantee. OS push delivery and user-opened
external browser links are outside this policy. Calls are blocked while proxy
mode is enabled; changing settings during an active call is rejected.

Ordinary logout preserves device routing. Account deletion and duress wiping
retain their existing secure-storage wipe semantics. No account-content or
crypto-storage persistence changes are included in this patch.

## Validation before release

- Run `flutter pub get`, `flutter gen-l10n`, `flutter analyze`, `flutter test`.
- Build iOS, Android, and Web; test on physical iPhone and Android devices.
- Test SOCKS5 with/without auth, IPv4/IPv6, bad password, dead host and timeout.
- Observe proxy traffic for login, contacts, groups, channels, messages,
  attachments, downloads, backups and WebSocket reconnect.
- Stop the proxy: no direct API/WebSocket traffic must occur.
- Verify destination TLS rejects untrusted certificates and DNS goes through
  SOCKS5. Confirm settings changes close old connections.
- Restart, logout/login, edit, disable and remove the profile. Test before login.
- Calls must not open microphone/ICE while enabled; active calls prevent edits.
- Verify five languages, small iPhone layout and large accessibility text.

Local Flutter execution was unavailable when authored; CI and device checks are
required. Do not merge based on static source checks alone.
