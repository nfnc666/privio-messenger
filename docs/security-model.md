# Privio Security Model

This document says plainly what Privio protects, what it does not, and where the
current implementation is not yet where it needs to be. A privacy product that
overstates itself is worse than one that says nothing.

## The rule that governs every decision

**No custom cryptography.** Privio composes audited implementations and writes
none of its own primitives. Where this document names an algorithm, it names a
library that implements it.

| Purpose | Choice | Where |
| --- | --- | --- |
| Message encryption | Signal Protocol (X3DH + Double Ratchet) | `libsignal_protocol_dart` on the client — see gap 1 |
| Password hashing | Argon2id, 64 MiB, t=3, p=1 | `@node-rs/argon2` (RustCrypto) |
| Session tokens | 256-bit random, stored as SHA-256 | `node:crypto` |
| Transport | TLS 1.3 | Platform TLS |
| Local history | AES-256-GCM | `package:cryptography` on the client |
| Attachments | AES-256-GCM with a per-file random key, padded | Client |
| Backups | AES-256-GCM under a key from a recovery phrase | Client |
| Two-factor | TOTP, RFC 6238 | `otplib` |

## Threat model

### Defended against

**A compromised or hostile server.** The server holds ciphertext and public
keys. An attacker with full database access reads no messages. This is the
central claim and everything else is subordinate to it.

**A network attacker.** TLS 1.3 in transit, and the message layer is encrypted
independently of it — breaking TLS yields ciphertext.

**A stolen, locked phone.** The local database is encrypted at rest and the app
is locked by PIN or biometrics. Keys live in the Keychain or Android Keystore,
hardware-backed where the device offers it.

**Coerced unlock.** The wipe code destroys devices, sessions, queued messages,
contacts, group membership and backups, and returns the same error a mistyped
password returns. Someone watching cannot tell the wipe happened.

**Account takeover by password alone.** Optional TOTP. Changing the password
revokes every other session.

**Enumeration of the user base.** Lookup is by exact username only. There is no
prefix search, no directory, and no address-book upload.

**Learning that you blocked someone.** A blocked sender's messages return an
ordinary success and are dropped.

### Not defended against

**A compromised endpoint.** Malware with your unlocked device reads your
messages. No messenger solves this.

**Traffic analysis.** The server sees who exchanges envelopes and when. Message
*length* is padded away (below), so size no longer distinguishes a word from a
paragraph, or a photo from a sentence. Sealed sender would narrow the remaining
who-and-when; a global passive adversary correlating timing is out of scope.

**A malicious recipient.** Anyone you message can screenshot, copy or forward
it. "Restrict content saving" raises the effort; it is not a security control
and is not presented as one.

**A lost recovery key.** Backups cannot be recovered without it. This is the
cost of the server not holding a key, and it is the right trade.

**Targeted platform compromise.** A zero-day in iOS or Android, or a malicious
OS update, defeats any app on it.

## Metadata

Encryption protects content. Most of what identifies a person is not content.

### Files are stripped on the way out

A photo straight from a phone carries GPS coordinates, the camera make and model,
a body serial number and the second it was taken. End-to-end encryption does not
touch any of it — it delivers all of it, intact, to the recipient. Privio removes
it before the file is encrypted, on every send, with no setting that can be left
off:

| Format | Removed |
| --- | --- |
| JPEG | EXIF and XMP (GPS, camera, serial number, timestamps), IPTC/Photoshop, ICC profile, comments |
| PNG | `tEXt` / `zTXt` / `iTXt` chunks, embedded `eXIf`, `tIME`, `iCCP` |
| MP4 / MOV | `udta` boxes (GPS, make, model), `meta` tags, `uuid` vendor boxes, creation and modification times in `mvhd` / `tkhd` / `mdhd` |

Only container structure is rewritten. Pixel and audio data are copied through
untouched, so nothing is re-encoded and no quality is lost. Scrubbing is
idempotent — a second pass finds nothing.

**A format Privio does not recognise is passed through unchanged and reported as
not cleaned.** Silently corrupting a file would be worse, and silently claiming
it was cleaned would be worse still.

The known gap: formats without a scrubber (WebP, GIF, PDF, Office documents)
carry their metadata through. The report tells the user, but the right answer is
to write scrubbers for them.

### Message length is padded away

Ciphertext length tracks plaintext length, and the server sees every ciphertext.
Unpadded, a "yes" is distinguishable from a paragraph, a shared address from a
link, and a repeated exchange of fixed-size messages is a fingerprint in itself.

Every payload is padded to a bucket before it is sealed, using ISO/IEC 7816-4
padding (a `0x80` marker, then zeros). Buckets start at 256 bytes and double,
capping the overhead at under 2x while collapsing observable sizes to a handful
of values.

Be precise about what this buys. For messages it is close to total: everything
under 256 bytes — which is most of what people send — is byte-for-byte
indistinguishable. For a large attachment, doubling buckets mean an observer
learns the size only to within a factor of two. That is a real improvement over
an exact byte count, and it defeats matching against a catalogue of known file
sizes, but it is not invisibility and should not be described as such.

Because text and attachment messages share one payload format, and both are
padded, the server cannot tell a sentence from a photo — only that something was
sent.

### Profile pictures are not an exception

An avatar is the one image a user hands to everyone they talk to, so it gets the
same treatment as a message, not a lesser one:

- Sealed with AES-256-GCM under a long-lived **profile key**, held in the
  keystore and never sent to the server.
- The key reaches contacts inside end-to-end encrypted messages — attached to
  every message sent — so only someone who has been written to can open the
  picture. A stranger, and the server, hold ciphertext.
- Re-encoded to a 512×512 JPEG before sealing. That strips metadata a second
  time on top of the scrubber, and stops a full-resolution photograph of
  someone's surroundings from becoming their avatar.
- The server stores a pointer and refuses to accept one that is not the caller's
  own upload — otherwise anyone could adopt an object id and learn, from whether
  the request succeeded, that it exists.

What the server does learn: that an account has an avatar, when it last changed,
and roughly how large it is. Rotating the profile key after removing a contact
is not implemented; today a former contact keeps the key they were given, which
matters when the picture changes rather than when it does not.

### Groups

The server keeps a membership list, because it has to fan messages out. It does
not keep anything else about a group in the clear:

- The **name** is sealed with a group key, generated by whoever creates the
  group and shared with members on the group's messages. The server stores a
  group it cannot name.
- **Messages** use no group-wide key at all: every member device gets its own
  Signal ciphertext. Removing a member therefore removes their ability to read
  what comes after, with nothing to re-key.
- A sender fetches prekey bundles only for devices it has no session with,
  because fetching one consumes a one-time prekey from the other side's pool.

The limits, stated: a member who is removed keeps the group key, so they could
still open a name they already had — and the name is not re-keyed on removal.
Group membership itself is visible to the server, as it must be for delivery.

### Channels, and what "public and encrypted" can honestly mean

A channel is one author and many readers, so a post is sealed **once**, under a
channel key, rather than once per member device. That is what makes a channel
cheap to run, and it decides everything else about its security.

**What encryption buys here:** the server cannot read a post. It stores
ciphertext, cannot search it, cannot scan it, and cannot hand over its contents.
That holds for public and private channels alike.

**What it does not buy:** secrecy from the audience. If anybody may join, then
anybody may hold the key — that is not a flaw in the design, it is what
"broadcast" means. A public channel's contents are as public as its membership.

**Why the server still cannot join.** Joining grants membership, not the key.
An invite link is meant to be shared in public, which rules out putting the key
in it: a key pasted into a public timeline is not a key any more. So the link
carries only a code, and the key catches up afterwards.

The handshake is two rows and a message. A device that joins records a key
request (`key_requests`, keyed by scope, scope id and device id — per device,
because a key is sealed to one device at a time). Any member who already holds
the key sees the request, seals the key into an ordinary end-to-end encrypted
message to that account, and clears the row. The server relays the request and
the reply without being able to read the second one. Delivery is open to any
member rather than to admins alone: making it wait for an admin to open the app
would leave new members looking at padlocks for days.

Three consequences worth naming. A joiner sees padlocked posts until somebody
who can read the channel next opens the app — visible waiting, not a silent
failure. A member who is removed has their pending request deleted, so a request
from a non-member is never answered. And a channel whose every key-holder has
gone is unreadable to newcomers forever; there is no copy on the server to fall
back on, which is the same trade as any end-to-end encrypted system.

Were the key delivered by the API instead, the server could simply subscribe to
everything, and the encryption would be decoration.

**What is deliberately in the clear.** Search cannot run over ciphertext, so a
public channel's handle, title, description and category are plaintext columns.
Nothing else is: the posts are not, and a private channel's title is sealed like
a group's. A private channel is also never listed, never searchable, and answers
a stranger asking about it exactly as it answers about a channel that does not
exist.

**Who may do what.** A single "admin" bit is too blunt for a channel: someone
who should be able to publish is not necessarily someone who should be able to
hand out permissions or delete the whole thing. Each capability is its own flag —
post, edit the channel, delete posts, manage members, delete the channel — and
two rules keep delegation from becoming takeover:

1. **You cannot grant a permission you do not hold.** Otherwise "may appoint
   admins" is simply "may take the channel over, one step later".
2. **You cannot demote or remove someone who holds something you do not.** An
   admin cannot clear the more privileged admin out of the way first.

The owner holds everything, cannot be demoted or removed, and cannot walk out of
their own channel. Deleting the channel is off by default even for admins,
because it is the one action nothing undoes; an owner can grant it deliberately.

**The limits, stated plainly:**

- A member who leaves — or is removed — keeps the key, and so keeps every post
  they could already read. Rotating the key on removal and re-sharing it to the
  remaining members is not implemented, which means removal stops future posts
  from reaching them but does not take back the past.
- Membership is visible to the server, as it must be for delivery.
- "Restrict saving" is a hint the client honours. Anyone who can read a post can
  copy it; it raises effort and is not a security control.

### File names stay inside the envelope

The upload is bytes and nothing else. The name, the type and the key travel
inside the end-to-end encrypted message, so `passport_scan.pdf` is never a string
the server holds.

### What the server still learns

Which accounts exchange envelopes and when; group membership; that an account
uploaded a file of roughly some size. Removing the sender identifier needs sealed
sender, which is listed under known gaps.

## Authentication

Registration takes a username and a password — no phone number, no email, so
there is no identifier to correlate against other services and nothing to leak
in a breach.

- Passwords: minimum 10 characters, hashed with Argon2id server-side.
- Login failures answer identically for a wrong password and an unknown user,
  and an unknown user still pays an Argon2 verification so the timing matches.
- Sessions are opaque 256-bit tokens; the database stores only SHA-256. A
  database leak yields no usable session.
- The realtime socket carries its token in the query string, because a browser
  cannot set a header on a WebSocket handshake. The server redacts it from
  request logs — a token written into a log file outlives the request and grants
  a working session to whoever reads it.
- Rate limits: 10 attempts per 5 minutes per address on the auth endpoints, 300
  per minute per device elsewhere.

The PIN is a **local** lock on an already-encrypted database, not the account
password. It never leaves the device.

## Key management

Each device has a stable per-account index, a long-term identity key, a
rotating signed prekey, and a pool of one-time prekeys. The index is what the
protocol addresses a session by; it is never reused, even after a device is
revoked, so an old session can never be pointed at a new device. The server stores public halves only and hands out one
bundle per device on request, deleting the one-time prekey atomically so it is
never reused. An exhausted pool still yields a usable bundle from the signed
prekey — weaker forward secrecy for those sessions until the client tops up,
which clients do well before the pool empties.

Peer identity keys are trusted on first use and pinned thereafter. A key that
changes afterwards is **refused on send** — a server that swaps in its own key
cannot silently read the conversation, because the user has to accept the new
safety number first. Incoming messages from a changed key are still accepted, so
a peer who reinstalled can reach you, and the change is surfaced rather than
hidden. This is tested: see `a swapped identity key is refused on send` in
`app/test/crypto_test.dart`.

## Data retention

| Data | Retention |
| --- | --- |
| Delivered envelopes | Deleted the moment the device acknowledges |
| Undelivered envelopes | 30 days, then purged |
| Attachments | 30 days from upload, unconditionally |
| Backups | One per account, replaced on each upload |
| Sessions | 365 days, or until revoked |
| Deleted accounts | Tombstoned; all content deleted immediately |

## Voice messages

A recording is the most personal thing this app carries: it is someone's voice,
and it identifies them in a way text does not. Three properties follow.

**It is sealed before it can be persisted.** `ConversationController.sendVoice`
seals the recording in memory before anything else happens — before the queue,
before the archive, before the upload. By the time any code path could write it
down, the only copy that exists outside the moment is ciphertext under a fresh
random key.

**Nothing decrypted reaches the disk.** On a phone the platform encoder must
write a file to produce AAC or Opus; that file is overwritten with random bytes
and deleted as soon as it has been read, because a deleted file on flash storage
is not a gone file. Playback runs from memory through a `StreamAudioSource`
rather than a cache path. In a browser there is no file at any point.

**What the server learns is bounded on purpose.** It sees a padded blob of a
bucketed size and an envelope, the same as for a photo. The duration and the
waveform — both of which describe speech — are inside the sealed payload. The
5-minute cap and the 2 MB limit are enforced on the sending device, so an
oversized recording is refused rather than uploaded and rejected.

**Retry without duplication.** A send that times out may already have been
queued, so the client retries — and stamps each send with an id of its own that
the server records (`sent_message_keys`). The second attempt is answered with
the first one's result. The id is opaque to the server, scoped to the sending
device, and says nothing about the message. Without it the honest choice would
be between losing recordings and delivering them twice.

**Disappearing messages.** The timer is carried inside the sealed payload and
applied by both devices from their own clocks. The server is not asked to delete
anything on a schedule, because a server asked to forget is a server trusted to.
What that does *not* buy: a recipient who wants to keep a message can keep it —
by recording the screen, by holding a second phone up to the speaker, by
patching their own client. A timer is a courtesy between people who both want
it, and Privio says so rather than implying otherwise.

## Receipts and typing

**They are messages, cryptographically.** A receipt and a typing notice go
through the same Signal session, padded and sealed per device. The server sees
that an envelope was sent between two accounts — which it sees for every
message anyway — and nothing about what it says.

**The switches are reciprocal.** Turning read receipts off stops this device
sending them and stops it showing other people's. This is the behaviour people
expect from the setting, and the alternative — seeing without being seen — is a
different feature that should not hide behind this one's label.

**What they still leak.** A typing notice is traffic: someone watching the
network learns that a device sent something small to another account at that
moment, which is a finer-grained timing signal than messages alone. Turning
typing indicators off removes it. This is worth stating because "it's
encrypted" does not answer it.

## Replies and reactions

**A reaction is a sealed message like any other.** It carries the id of the
message it applies to and one emoji, inside the same padded, per-device
envelope. The server sees an envelope between two accounts and cannot tell a
reaction from a sentence — the padding buckets make them the same size.

**A reply carries its own copy of the quote.** The alternative — a pointer the
server resolves — would hand the server the graph of which message answers
which, on top of the traffic it already sees. Carrying the quoted line inside
the sealed payload costs a few hundred bytes and keeps that graph on the
devices. It also means a quote still renders where the other side has deleted
the original.

**A reaction to a message this device does not have is dropped.** Not rendered
as a placeholder, not stored for later. A bubble conjured out of a control
message is a message the app did not receive and cannot show the contents of,
and inventing one is a way for a server that reorders or replays envelopes to
put marks in someone's chat.

## Backup

**The server holds bytes it cannot open.** A backup is sealed on the device with
AES-256-GCM under a key derived from the recovery key. There is no reset, no
recovery flow and no support ticket that opens one — that is the guarantee, and
it is also the whole risk. The screen says so instead of implying a safety net.

**The recovery key is generated, not derived.** A key derived from a password is
only as good as the password, and this one has to stand alone: 32 bytes from a
secure generator, kept in the platform keystore so an automatic backup does not
have to ask for it weekly. The device's copy goes with the device — which is the
situation a backup exists for, and why the key is shown to be written down.

**A backup carries no key material.** No identity key, no ratchet state, no
session. This is deliberate: restoring the same ratchet state onto two devices
breaks both of them, and does so silently, in a way that looks like network
trouble rather than a bug. So a restore returns the history and the new device
registers its own identity for what comes next.

**A failed restore changes nothing.** The wrong key throws rather than restoring
an empty history — silently replacing a device's conversations with nothing,
because the key was mistyped, would be the worst possible failure mode here.

## Known gaps in the current implementation

These are real and tracked. Nothing here is hand-waved as "future work" without
naming what is missing today.

1. **The protocol implementation is a port, not the audited original.**
   Messages *are* end-to-end encrypted: `app/lib/crypto/` performs X3DH and the
   Double Ratchet, and the round trip is covered by tests that assert a third
   party holding the ciphertext cannot open it. But it runs on
   `libsignal_protocol_dart`, a pure-Dart port of libsignal rather than the
   official audited Rust build. A port can diverge from the original in ways
   that matter, and this one has not been audited.

   The pre-launch target is the official `libsignal` behind FFI. Every call site
   goes through `PrivioCrypto`, so that swap is contained to one file — but
   until it happens, this is the single largest caveat on Privio's central
   claim, and it should be stated to users rather than glossed.
2. **The local history is one sealed blob, not a database.** Conversations
   survive a relaunch and are sealed at rest with AES-256-GCM under a 256-bit
   key held in the platform keystore — the archive is ciphertext, down to the
   contact names. What it is not is a database: it is rewritten whole on every
   change, so it will not scale to a long history, and a keystore is not built
   for bulk data. SQLCipher is the destination; `ArchiveStorage` is the port
   that keeps that swap to one file.
3. **The PIN is compared, not stretched.** It is stored in the platform
   keystore, which is the security boundary; V2 moves it into the native crypto
   layer where it derives a key-encryption key with Argon2id.
4. **No sealed sender.** Envelopes carry a sender account id, which the server
   uses for blocking and rate limiting. Removing it needs delivery tokens. Now
   that length is padded away, this is the largest remaining metadata leak.
5. **Only three formats have metadata scrubbers.** JPEG, PNG and MP4/MOV are
   cleaned on every send. WebP, GIF, PDF and Office documents are passed through
   as they are — the app reports that it could not clean them, but reporting is
   not the same as fixing.
6. **The file-picking step is unverified.** Everything after it — scrubbing,
   padding, sealing, upload, download, decryption and display — is covered by
   tests that run the real code paths. The OS file dialog itself is a platform
   plugin: its native iOS and Android implementations cannot run in the
   development sandbox, and its web implementation did not register there. The
   call is guarded by a timeout so a picker that never answers surfaces an error
   instead of a button that silently does nothing, but it needs checking on a
   real device before release.
7. **TOTP secrets are stored in plaintext in the database.** They should be
   encrypted with a server-held key so a database leak alone does not defeat the
   second factor.
8. **Attachment ids are the download capability.** Any authenticated user who
   learns an id can fetch the (encrypted) bytes. Ids are unguessable and objects
   expire, but per-recipient authorisation would be stronger.
9. **The link domains are not registered.** Links are generated against
   `privio.channel` for channels and `privio.group` for groups, neither of
   which this project owns, so nothing on the open internet answers them. This
   is not a security hole: the app reads the invite code out of the link's
   *path* and never fetches the URL, so a link works between Privio users
   either way, and the code it carries is the same unguessable capability it
   always was. It is also why the parser keys off `/c/` and `/g/` rather than
   the host — a link that has been shortened, wrapped by a mail scanner or
   re-hosted still names the same channel, and the host was never the
   authorisation. But a link a recipient cannot click is a worse link.
   Registering the domains, confirming both TLDs are available, and shipping a
   `privio://` deep link beside them is a launch task; each host is one
   constant, `ChannelService.channelLinkHost` and `groupLinkHost`.
10. **The web build still fetches emoji glyphs from Google.** The renderer and
    the typeface now ship inside the build, so a page load announces itself to
    nobody — but emoji are not in the bundled font, and CanvasKit asks Google's
    font CDN for the glyphs it lacks. That is a request naming the viewer's
    address at the moment they open a chat containing an emoji. The fix is a
    bundled emoji font, which costs ~10 MB; the iOS and Android builds are
    unaffected because the system supplies emoji, and that is the target
    platform. Worth re-checking on a real device, where the reaction chips are
    the first place a missing emoji font would show.
11. **No independent audit.** Before any public release, the crypto integration
    needs review by someone who was not involved in writing it.

## Reporting a vulnerability

Set up `security@privio.app` with a published PGP key before launch, commit to a
response window, and say so in the app's About screen. A privacy product without
a disclosure channel is not credible.
