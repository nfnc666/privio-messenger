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
is locked by the app-lock passcode. Keys live in the Keychain or Android Keystore,
hardware-backed where the device offers it.

**Coerced unlock.** The duress code destroys devices, sessions, queued messages,
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
| Word / Excel / PowerPoint | `docProps/core.xml` (author, last saved by, revision, created and modified dates), `docProps/app.xml` (company, manager, application, total editing time), `docProps/custom.xml`, and the modification time on every entry in the container |
| OpenDocument (`.odt`, `.ods`, `.odp`) | `meta.xml` (author, creation date, editing cycles, editing duration, generator), and the same entry timestamps |

Only container structure is rewritten. Pixel and audio data are copied through
untouched, so nothing is re-encoded and no quality is lost. Scrubbing is
idempotent — a second pass finds nothing.

**A format Privio does not recognise is passed through unchanged and reported as
not cleaned.** Silently corrupting a file would be worse, and silently claiming
it was cleaned would be worse still.

**WebP** loses its EXIF, XMP and ICC chunks, and the VP8X flags that announced
them are cleared with them — a decoder told there is a colour profile and handed
a file without one is a decoder looking at a malformed image.

**GIF** loses comment blocks, plain-text extensions and application extensions
that are not the loop block. XMP in a GIF is an application extension, so that
goes too. NETSCAPE2.0 stays: dropping it turns an animation that looped forever
into one that plays once, which alters the picture rather than removing
information about it.

**A file that cannot be walked is reported as not cleaned**, never as having
nothing to remove. A truncated or malformed container means the rest was never
read, so any metadata in it survives; a tick over that file would be the app
telling somebody their photograph is safe when nothing looked at it.

**Documents** are ZIP containers, and the parts that name a person are
replaced rather than removed. Deleting a part leaves the relationship pointing
at it and the content-type override declaring it dangling, and a word processor
handed those is entitled to call the file corrupt; an empty part of the right
type is valid everywhere the full one was. The document body, the styles and
the content types are copied through byte for byte. Two details that would
otherwise corrupt the output quietly: an OpenDocument reader wants `mimetype`
first and stored rather than deflated, and every entry in a ZIP carries the
minute it was written — a record of when somebody was working on the file —
which is flattened to one fixed instant, the same for every file Privio sends.

A ZIP that is not one of these formats is left exactly as it came and reported
as not cleaned. Rewriting an archive of unknown files is not the scrubber's
business.

The known gap now: PDF. It needs a real parser to strip safely — a document
whose cross-reference table no longer matches its body is worse than an
untouched one — and a half-done job there is worse than an honest refusal.

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

**Who the audience is.** Not the audience's business. Anyone may join a public
channel, so answering every subscriber with the roster would make joining the
user-enumeration endpoint this API otherwise refuses to have — one request and a
stranger holds the username of everyone who reads the channel. A private channel
is no better placed: its invite link is meant to be passed around, and the list
of readers should not travel with it. So `GET /v1/channels/:id/members` answers
a member who may *manage* members with everybody, and everybody else with the
people who run the channel — whose names are already on every post they
publish — plus their own row. The response says which of the two it is, and the
app labels the screen accordingly rather than passing a staff list off as the
whole membership.

A group is different on purpose: it is a mutual construct, capped and
invite-only, where every member is already known to every other. There the list
is shared in full.

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

It also holds a few things somebody typed, and they are worth naming rather than
leaving to be discovered: the **username and display name**, which are how people
are found; a **public channel's** handle, title, description and category, because
search cannot run over ciphertext; a **device's** name and platform, which the
connected-devices screen shows; and the **alias** somebody gave a contact. The
last one is the odd one out — a private nickname, useful to nobody but its
author, sitting readable in `contacts.alias`. Sealing it needs a per-account
symmetric key that survives a reinstall and reaches a second device, which the
app does not have today outside the backup recovery key; until then it is listed
here rather than implied to be encrypted.

`server/test/schema.test.ts` holds that list as an allowlist: every free-text
column in the schema with the reason it is not sealed. A migration that adds a
new one fails the test until somebody either seals it or writes down why not.

**Measured, not asserted.** `tools/db-canary-sweep.mjs` reads every value in
every column of every table and looks for phrases typed into a real client. A
run on 5 September 2026 — a direct message, a group message and a group name
sent from the browser build with the recipient offline, so the ciphertext was
still queued — found none of the three anywhere among 14,792 values in 19
tables, while finding both usernames in `accounts.username` and nowhere else.
The control is the part that matters: a sweeper that cannot find anything would
report the same clean result. The queued envelopes were 404 bytes for a
nineteen-character message, which is the padding doing its job.

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
rotating signed prekey, and a pool of one-time prekeys. The signed prekey is
replaced every 48 hours, checked at start beside the one-time top-up: it is the
key a stranger seals to when the pool is empty, the same one for everybody, so
its lifetime is the window a stolen one buys. The replacement is published
before anything is deleted, and the one it replaces is kept for 30 days —
someone who fetched a bundle and sent an hour later sealed to the old key, and
deleting it on rotation would lose that message. The index is what the
protocol addresses a session by; it is never reused, even after a device is
revoked, so an old session can never be pointed at a new device. The server stores public halves only and hands out one
bundle per device on request, deleting the one-time prekey atomically so it is
never reused. An exhausted pool still yields a usable bundle from the signed
prekey — weaker forward secrecy for those sessions until the client tops up,
which clients do well before the pool empties.

Peer identity keys are trusted on first use and pinned thereafter. A key that
changes afterwards is **refused on send** — a server that swaps in its own key
cannot silently read the conversation, because the user has to accept the new
safety number first. Incoming messages from a changed key are still accepted,
so a peer who reinstalled can reach you; refusing them would hand anyone a way
to silence a conversation by sending one message. What that costs is paid for
by saying so: the replacement is recorded, survives a relaunch, and stands
until the new number has been put in front of the user. Tested in
`app/test/crypto_test.dart` (`a swapped identity key is refused on send`) and
`app/test/safety_number_test.dart` (`a key that arrives with a message is
reported, not swallowed`).

**A session that has gone out of step repairs itself, and says so first.** An
envelope that will not decrypt cannot be retried — the same bytes fail the same
way — and the failure is not symmetric: the sender's screen says delivered while
the recipient sees nothing at all. So the conversation is given a line saying a
message could not be read, for the same reason a deletion leaves a tombstone: a
silent gap in a transcript reads as an answer nobody gave.

The session is then rebuilt. The side that could not read deletes its session
with that device and sends a payload that carries nothing — with no session left
it goes out as a prekey message from a fresh bundle, and the other side archives
its old state on receiving it, so one message puts both directions back on a
working ratchet. Nothing already lost is recovered by this; what it buys is that
the conversation does not stay dead. It is rate-limited to one per device per
hour: a reset consumes one of the other side's one-time prekeys, and a batch of
failed envelopes must not become a batch of handshakes.

This is a repair, not a downgrade. The new session is a full X3DH handshake
against the server's published bundle, subject to the same identity pinning as
any other — a server that answered with its own key would still be caught by the
safety number. And it is not a licence for the server to break sessions on
purpose: doing so destroys messages and shows the user that it happened, which
is the opposite of a quiet attack.

## Safety numbers

Everything above takes the server's word for whose key is whose. The safety
number is where that stops: sixty digits computed from both sides' identity
keys and account ids, which two people compare over something the server is not
part of. A server that substituted a key of its own cannot make the two screens
agree.

The digits are Signal's construction, computed by `NumericFingerprintGenerator`
from `libsignal_protocol_dart` — 5200 rounds of SHA-512, thirty digits a side,
concatenated in a fixed order. Privio implements none of it, and the iteration
count is part of the number rather than a setting.

**One number per device, not one per person.** Signal shows a single number
because an identity key there belongs to an account. In Privio a key belongs to
a *device* and is trusted per device, so one number would summarise several
independent trust decisions. The screen lists them.

Marking a conversation verified records the exact keys that were on screen —
not a flag. So the answer to "is this still what I checked?" is a comparison,
and it comes apart on its own in the two cases that matter:

* a key changed, and
* a device *appeared*. This is the one a per-key check misses. Nothing already
  pinned has changed; a device simply joined the account — which is also what a
  server quietly adding a device of its own looks like from here.

There is no QR code. Scanning needs a camera package Privio does not carry, and
a QR nobody can scan is decoration on a security screen. Reading the digits is
the method; a compare box takes a number sent in writing, because comparing
sixty digits by eye is where the mistake this screen exists to prevent gets
made.

What is verified by test rather than by hand: the refusal-on-send path. It
needs a server that hands out a different identity key for a device whose
session already exists, which no honest deployment does — so it is exercised in
`app/test/safety_number_test.dart`, not in a browser run.

## Data retention

| Data | Retention |
| --- | --- |
| Delivered envelopes | Deleted the moment the device acknowledges |
| Undelivered envelopes | 30 days, then purged |
| Attachments | 30 days from upload, unconditionally |
| Backups | One per account, replaced on each upload |
| Sessions | 365 days, or until revoked |
| Deleted accounts | Tombstoned; all content deleted immediately, username freed |

### Deleting the account

`DELETE /v1/accounts/me` takes the password, not just the session: a phone
somebody picked up while it was unlocked must not be able to end the account on
it. It removes the devices — and with them the sessions, the prekeys and every
queued envelope — the envelopes this account sent that have not been collected,
the contacts in both directions, the group memberships, the backup and every
media object the account uploaded. The row is then tombstoned and the username
rewritten to `deleted.<id>`, which frees the old one for somebody else.

"Deleted" means the bytes, not the row that named them. Attachments and the
backup live as files in blob storage, and the retention sweeper finds expired
attachments through `media_objects.expires_at` — so a row deleted without its
file leaves something nothing will ever reach again, sitting on disk until the
disk is thrown away. The wipe therefore collects the storage keys as it deletes
the rows and removes the files afterwards: after the transaction commits, never
inside it, because a rollback that had already deleted the files would leave
rows pointing at nothing. This matters most where the promise is strongest — a
duress code is entered with somebody standing over the phone, and there the
whole point is that the content is gone. Covered by
`server/test/erasure.test.ts`, which reads the keys before the wipe and checks
the files afterwards.

What it cannot reach is what other people have already received and decrypted.
The dialog says so, along with the username becoming available again, because
both are surprises otherwise.

The client destroys everything locally only after the server has confirmed, and
unlike signing out it wipes the identity too: there is no account left for those
keys to belong to.

### Deleting one message

*Delete for everyone* is a sealed control payload naming one client id. The
server routes it as it routes any envelope and cannot tell it from a sentence,
which also means it cannot help: a recipient who is offline gets it when they
next connect, and one who never connects again never gets it.

What it reaches: the message in the recipient's local archive, the copy on this
account's own other devices, and the decrypted bytes of any file it carried,
which are dropped from the in-memory cache. What it cannot reach: a screenshot,
a backup already restored elsewhere, anything already read, and the ciphertext
of an attachment on the server, which expires on its own 30-day clock and is
not deleted early — a deletion that also deleted the object would tell the
server that this particular message was withdrawn, which is more than it needs
to know.

A message somebody else wrote can only be deleted locally, and that rule is
enforced at both ends. Refusing to *send* such a request keeps this app honest
and does nothing about a modified one, so an arriving deletion is also checked:
it may only remove a message whose sender wrote it, and one that arrives from
this account's own other devices may only remove this account's own. Without
that, anyone you have a session with could delete your side of the argument.

The check needs to know who wrote each message, so messages now record their
sender's account id. Anything filed before that field existed has none; in a
direct chat nothing is lost, because there is only one other person, and in a
group it means an old message can still be taken back by any member of it.

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
There is no separate "the timer changed" packet, either: a change reaches the
other side on the next message, and inventing a packet for it would tell the
server that something about this conversation changed at this moment, for
nothing.

**The clock starts when the message reaches the server, not when it was
written.** On the receiving side it starts on arrival, which is the same moment
seen from the other end. This is invisible in the ordinary case, where the two
are a second apart, and it is the whole difference in two cases that are not: a
recording made with no signal waits in the outbox, and a send that failed sits
on screen with a retry. A clock started at the keyboard would empty both — the
queued message vanishing from the sender's own chat before it had been
anywhere, and then sending regardless; the failed one deleting the retry out
from under the person about to press it, and taking what they wrote with it.
Nothing that has not left the device has a timer on it.

Because the timer travels with the message, whoever sends sets it — so **every
change is announced in the conversation itself**, on both sides: "You set
disappearing messages to 1 hour", "bob set disappearing messages to 5 minutes".
A chat that quietly starts deleting itself is the one way this feature can hurt
the person using it, who keeps writing and finds it gone. Those notices are
written locally on each device from the same fact, are never sent anywhere, do
not count as unread, and do not expire — a record that deletes itself under the
rule it describes explains nothing afterwards.

An expired message takes its decrypted attachment with it. The bubble
disappearing while the photo stays in the session's plaintext cache is the
version of this that does not work.

In a group, any member can set it, not only an admin: the mechanism is the
sender's own number riding inside their own payloads, so a member who wants
their messages to go can already make that happen. A permission the protocol
cannot enforce would be a lock drawn on the screen with nothing behind it; the
announcement is the honest version of the same protection.

What none of this buys: a recipient who wants to keep a message can keep it —
by recording the screen, by holding a second phone up to the speaker, by
patching their own client. A timer is a courtesy between people who both want
it, and Privio says so — in the chooser itself, not only here.

## Two-factor secrets

**Sealed at rest.** A TOTP secret is a bearer credential that never expires:
whoever reads it can produce valid codes for as long as the factor is on. In
the clear it meant a database leak on its own — a stolen backup, a read-only
replica, one injection — defeated the second factor for every account on the
server without anybody touching the machine.

They are sealed with AES-256-GCM under `TOTP_SECRET_KEY`, which lives in the
environment. A fresh nonce each time, so the same secret sealed twice is not
the same bytes: identical ciphertext would say which accounts share a secret,
and for a re-enrolment that says which account this is. GCM's tag means a row
edited in the database is refused rather than opened into a secret of the
editor's choosing.

**What this is not.** It is not protection against a compromised server, which
holds the key by definition. It separates two things that used to be one: an
attacker now needs the database *and* the process configuration. Keep the key
out of the database and out of the backup that contains it, or this buys
nothing.

**No key, no enrolment.** A server without `TOTP_SECRET_KEY` refuses to set up
two-factor rather than storing the next secret in the clear — a secret written
unsealed is a permanent hole in that account's second factor and nobody would
ever be told. Accounts already enrolled keep working: a stored value with no
marker is read as-is.

**A secret that will not open refuses the login.** A rotated or lost key means
codes cannot be checked, and a factor whose secret the server can no longer
read must not wave logins through.

## Attachment downloads

**A capability, not a recipient list.** The server cannot know who a message
went to without being told, and telling it would hand it the metadata this
design exists to withhold. So the uploader is given an unguessable token, puts
it inside the sealed payload beside the media key, and whoever can open the
message can fetch the blob. The server authorises the bytes without ever
learning who is entitled to them.

**Why the id was not enough.** The id was the capability, and 122 random bits
of it, so it was never guessable. But it is also the primary key, sitting in
the clear next to the ciphertext: a read of `media_objects` was a set of
download capabilities for everything in it. Only the token's hash is stored,
for the reason a password's is — an attacker with database access and no blob
access now gains nothing.

**What that was worth, honestly.** The bytes were always sealed under a key the
server never had, so nothing was ever readable. What leaked was existence,
exact size, and the ability to take a copy of the ciphertext and keep it. That
last one matters most: harvested ciphertext outlives the thirty-day expiry and
any future weakness in the cipher.

**Avatars are the other kind, and are marked as such.** Their id is published
to contacts on purpose, so a token would be published with it and buy nothing.
They are authorised by the contact list instead: the owner, or an account that
has the owner as a contact. A stranger with the id is refused.

**"Not yours" and "no such thing" are the same answer.** Telling them apart
would say whether an id exists.

## Disguise mode

**What it is.** A locked device opens to a working calculator instead of a lock
screen, and the launcher entry becomes a calculator too. Any sum whose answer
is the passcode opens Privio on `=`; any sum whose answer is the duress code
does what the duress code does, through the same path as the lock screen, so
there is one place where a code is checked and not two.

**The answer is compared, not the keys.** Typing the code works because a
number evaluates to itself, and so does any sum reaching it — which means the
code need never be on the screen where it can be read over a shoulder or caught
by a camera. It also means an idle sum could in principle land on the code by
accident: one in ten thousand for four digits, one in a million for six, and
only while the phone is locked and someone is doing arithmetic on it. Worth
knowing; not worth giving up the shoulder-surfing property for.

**A wrong code is not treated as one.** No shake, no attempt counter, no pause
while something is verified — the calculator adds the number up. Anything else
is a tell, and a tell is the only thing a disguise has to avoid.

**It replaces the lock screen rather than sitting in front of it.** Two screens
to get past would be two screens to explain.

**It requires a numeric passcode**, and refuses rather than storing an
unusable setting: a passphrase cannot be typed on a keypad with no letters.
Clearing the screen lock clears the disguise, and so does a wipe — a calculator
whose code nobody holds is a locked-out phone, not a secure one.

**The launcher entry.** On Android the icon and the name both change: two
`activity-alias` entries point at the same activity, each with its own
`android:label` and `android:icon`, and the wanted one is enabled before the
other is disabled — with no enabled alias, even for an instant, some launchers
drop the app and Android may stop the process. The result is read back, because
some manufacturer builds accept the call and change nothing.

What changes is the launcher entry and only that. Android's app list, the app
info screen and the name shown in a permission prompt all read the
`<application>` label, which is fixed at build time. A home screen shows a
calculator; Settings → Apps still shows Privio. A shortcut someone pinned by
hand points at the old alias and may need pinning again.

**Not offered on iOS.** iOS can swap an icon and cannot change a name: an app's
display name is fixed at build time with no public API to change it. A
calculator icon still labelled *Privio* is a disguise that names itself, and it
invites the one question the disguise exists to prevent — so the feature is
withheld there entirely rather than shipped in the half that works. There is no
calculator, no setting and no lock-screen replacement on iOS; the platform is
not even asked, and a disguise stored by an earlier install is dropped at
start-up so no device can be left locked behind a screen it will never draw.

Withholding rather than degrading is the deliberate choice here. A partial
disguise is not a weaker version of the same protection; it is a different and
worse thing, because the user believes they have the protection.

**What it does not do.** It does not survive examination. The package is still
installed under its own application id, and its size, its files and its network
traffic are all still there. A changed icon and name defeat a glance at a home
screen, not a search. It is a defence against being looked at and against
handing over an unlocked phone, and it should be described as exactly that.

**Unverified.** The Android implementation has not been run. This environment's
egress proxy blocks `dl.google.com`, so the Android SDK cannot be installed and
the app has never been compiled for Android. The manifest has been parsed and
checked structurally; the Dart side is tested, including a device that refuses
the swap and a device the disguise is not offered on. The Kotlin is written and
reviewed and nothing more, and a real device pass belongs on the pre-release
list beside the file picker and the microphone.

## Calls

**The setup travels sealed, and that is the point.** An SDP offer enumerates
every address the device believes it has. Signalling in the open would hand the
relay both parties' addresses — most of what the call itself would have
revealed. Privio sends offers, answers and ICE candidates as ordinary sealed
payloads over the existing Signal session, so the server relays a call knowing
what it knows about a message: which two accounts, and when.

**The media is libwebrtc's.** DTLS-SRTP, keys agreed in the handshake between
the two devices, implemented by the library rather than by Privio. The rule
against writing our own cryptography applies here as everywhere.

**What a call still leaks.** Once media flows peer to peer, each side learns
the other's IP address — that is what a direct connection is. A TURN relay
moves that exposure rather than removing it: the two parties stop seeing each
other's address and whoever runs the relay sees both, along with how much is
flowing. The media stays DTLS-SRTP end to end, so a relay carries ciphertext
it holds no key for. Privio runs no relay; a deployment configures its own
through `ICE_SERVERS`, or none. Traffic analysis also gets an easier target
than with messages: a call is a continuous stream of a recognisable shape and
length.

**TURN credentials name no account.** They are minted per request under
coturn's shared-secret scheme, with the expiry as the username. The scheme
allows an account id there and Privio leaves it out on purpose: it would buy
per-account rate limiting on the relay and cost exactly the linkage — this
account placed these calls — that the rest of the server refuses to hold.

**When they are fetched is itself metadata.** Clients ask at sign-in and hold
the answer, never at the moment of a call. A request at dial time would tell
the server a call was starting, which the sealed signalling otherwise denies
it.

**The log is local.** Call history is written on the device when a call ends,
kept in the encrypted key store, capped, and erasable from the Calls screen.
The server holds none of it.

## Receipts and typing

**They are messages, cryptographically.** A receipt and a typing notice go
through the same Signal session, padded and sealed per device. The server sees
that an envelope was sent between two accounts — which it sees for every
message anyway — and nothing about what it says.

**The switches are reciprocal.** Turning read receipts off stops this device
sending them and stops it showing other people's. This is the behaviour people
expect from the setting, and the alternative — seeing without being seen — is a
different feature that should not hide behind this one's label.

**A group receipt goes to the author, not to the group.** Who has read what is
between the reader and whoever wrote it; telling everybody would also cost a
sealed copy per member device to say so. That is why the receipt names the group
inside the payload — the envelope it rides in says only who sent it, and without
the name the other side could not tell which conversation the ids belong to.

**In a group the ticks mean everyone.** Two ticks that light up because one of
seven people opened the app say something that is not true, so each member's
answer is kept separately and the ticks move only once all of them have got that
far. Until then the count is on the bubble: "delivered to everybody, read by
three" is on screen rather than implied. Where the member count is not known
yet, nothing claims everyone has seen it.

**What they still leak.** A typing notice is traffic: someone watching the
network learns that a device sent something small to another account at that
moment, which is a finer-grained timing signal than messages alone. Turning
typing indicators off removes it. This is worth stating because "it's
encrypted" does not answer it. A read receipt is the same signal, and in a
group there is one per author rather than one per group — a watcher counting
envelopes learns a little about how many people wrote in it.

**Typing notices are still 1:1.** A notice would have to be fanned out to every
member device, several times a minute, to say something a group of forty does
not benefit from knowing; and one that says "somebody" is worse than none.

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

## Devices

**The list is the server's answer, not the app's guess.** Every device signed
in to an account is a device that can decrypt what arrives for it, so "who is
signed in" is a security question and the screen that answers it renders what
`GET /v1/devices` returns. It rendered four fabricated devices until this was
written, which is the worst possible answer to give on that screen.

**Signing one out revokes its sessions and deletes its queue.** What it has
already decrypted stays on that device: the history is sealed under a key in
its own keystore, and nothing from another device can reach it. The dialog says
that rather than implying a remote wipe — the duress code is the only thing
that destroys a local copy, and only on the device it is typed into.

## The app lock

**A passcode, in one of three shapes.** Four digits, six digits, or a
passphrase — letters, with digits and symbols if you want them. The shape is
stored beside the passcode because the lock screen has to know whether to draw
a keypad or a text field before anyone has typed anything.

**No biometrics, and that is the design.** A face or a fingerprint is the one
credential that can be used while its owner is unwilling, asleep or
unconscious, and in several jurisdictions compelled by an order that could not
compel a passcode. In an app that ships a duress code for exactly that
situation, offering a biometric unlock would hand back what the duress code is
there to protect. `local_auth` is not a dependency any more.

**It guards the key, not just the screen.** Setting a passcode wraps the archive
key with Argon2id under it and deletes the readable copy; unlocking derives the
same key and opens it for the session, in memory, never written back. So there
is no stored passcode to compare against — verifying one is unwrapping the key —
and a store somebody walks off with no longer opens the history. Measured on the
web build, where the whole store is readable: before setting a lock the history
comes out in the clear; after it, `privio.archive.key` is gone, replaced by
`privio.archive.key.wrapped`, and the same recovery gets nothing.

**What it does not cover, and why.** The Signal identity and prekeys sit in the
same store and are *not* behind the passcode. Putting them there would mean a
locked device could not receive anything, which is a different app. So this
protects what was said, not the ability to impersonate the device — an attacker
with the store still has the keys, and the safety number is what catches that on
the other side.

**And what a short passcode is worth.** Four digits behind 19 MiB Argon2id is
ten thousand guesses at roughly a tenth of a second each: minutes for somebody
who wants it, on one core. That is a real cost where there was none, and it is
not a defence against a determined offline attacker. The passcode screen says as
much beside each choice, and says that a passphrase is the only one of the three
that stands up to someone with the phone and time.

**Changing it re-wraps rather than re-storing.** The second call has no
readable key to work from — the first one took it away — so it takes the key
through the unlocked session and seals it again under the new passcode. Reading
the stored entry directly instead left the old blob sealed under the old code
with the new code written beside it: the old passcode went on working, and the
new one opened nothing. Both halves are tested, and driven in a browser.

**"Locked" and "not there" are different answers.** The store raises
`ArchiveLockedException` when the key exists but is sealed, rather than
answering null. A caller that reads the two as the same thing generates a fresh
key and writes it over a history that was only waiting for a passcode — silent
and total. That is not hypothetical: it is what the first wiring of this did,
found by driving a real relaunch in a browser rather than by reading the code,
and `tools/web-unlock-check.cjs` is the run that found it.

**Forgetting it now costs the history.** Before, a forgotten passcode locked the
app while the archive stayed readable; now the archive is what the passcode
opens. The screen said so already — "what was already delivered here is gone
unless it is in a backup" — and it is exactly true rather than nearly.

**Covering and locking are two different moments.** A locked app is not a
private one if the app switcher beside it still shows the conversation that was
open: the OS takes that thumbnail on the way out, before any lock is armed, and
it stays there for whoever picks the phone up next. So the content is covered
the moment the app stops being what is on screen (`inactive`) — above the
navigator, so a pushed chat or a live call is covered too — and the lock is
armed only when the app has actually been left (`paused`). Locking at
`inactive` instead would ask for the passcode every time a notification shade
was pulled down or a call came in, and a lock that fires that often is a lock
people turn off.

The cover wears the disguise when there is one. A phone set to open as a
calculator, whose switcher thumbnail is a Privio splash, has announced exactly
what the disguise was hiding.

**A device with no passcode is never locked.** The lock screen has one way past
it, so arming it where nothing was ever set is not a stricter lock — it is a
device its own owner cannot get back into, with a reinstall as the only way out
and the local identity going with it. Backgrounding the app used to do this.

## The duress code

**It is a second password that destroys instead of opening.** Typed at sign-in,
the server deletes the account's devices — which cascades to its sessions,
prekeys and queued envelopes — along with contacts, group memberships, media
and the backup, then answers `invalid_credentials`. Someone standing over the
phone sees what a typo looks like.

**It cannot be the password.** The server refuses to store one that is, because
an ordinary sign-in would then destroy the account.

**Setting or removing it needs the password.** In both directions: an unlocked
phone is not authority over the setting that decides whether the account can be
destroyed.

**What it does not do.** The account row survives, so the username cannot be
claimed by anyone else afterwards. It also cannot reach a device that is
already signed in elsewhere — the wipe happens at the sign-in the code is typed
into, and that device's local archive stays sealed but present. A remote kill
switch is a different feature, and the screen does not imply this is one.

## Two-factor authentication

**It protects the account, not the messages.** The code is checked by the
server at login, so it stops someone who has the password from signing a new
device in. It has nothing to do with the ciphertext: that is opened by a key
held on the device, and no code can substitute for it. The screen says so,
because "two-factor encryption" is a thing people believe.

**Enabling it is two steps.** The server issues a secret; the factor only comes
into force once a code generated from that secret has been checked. Anything
else enables a factor nobody has proved they can produce, which locks out the
person who set it up.

**The secret lives in memory for as long as the setup screen does.** It is the
factor — someone who has it can produce codes forever — so it is dropped as
soon as the factor is on, and dropped again if the screen is left.

**Removing it asks for the password.** A second factor that an unlocked phone
could remove on its own would not be a second factor.

**The routes that check a credential are rate limited separately.** Ten
attempts per address per five minutes covers login, registration, the password
change, the duress code and both two-factor transitions. Reading your own account
is not on that budget: it used to be, which meant opening a settings screen a
few times could lock someone out of their own account for five minutes.

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
3. **Nothing here — this one is closed.** It used to read: the PIN is compared,
   not stretched. Setting a screen lock now wraps the archive key with Argon2id
   (RFC 9106's second recommended setting: 19 MiB, two passes, one lane) under
   the passcode and deletes the readable copy, so there is no stored passcode
   left to compare a guess against — checking one *is* unwrapping the key. See
   "The app lock" for what that is and is not worth.
4. **No sealed sender.** Envelopes carry a sender account id, which the server
   uses for blocking and rate limiting. Removing it needs delivery tokens. Now
   that length is padded away, this is the largest remaining metadata leak.
5. **PDFs have no metadata scrubber.** Everything else does: JPEG, PNG, WebP,
   GIF, MP4/MOV, and now Word, Excel, PowerPoint and OpenDocument. A PDF is
   passed through as it came, and the app says it could not clean it — but
   reporting is not the same as fixing. It needs a real parser, because a
   document whose cross-reference table no longer matches its body is worse
   than an untouched one.
6. **The file-picking step is unverified.** Everything after it — scrubbing,
   padding, sealing, upload, download, decryption and display — is covered by
   tests that run the real code paths. The OS file dialog itself is a platform
   plugin: its native iOS and Android implementations cannot run in the
   development sandbox, and its web implementation did not register there. The
   call is guarded by a timeout so a picker that never answers surfaces an error
   instead of a button that silently does nothing, but it needs checking on a
   real device before release.
7. **Nothing here — this one is closed.** It used to read: TOTP secrets are
   stored in plaintext in the database. See "Two-factor secrets" above.
8. **Nothing here — this one is closed.** It used to read: attachment ids are
   the download capability, so any authenticated user who learns an id can
   fetch the encrypted bytes. See "Attachment downloads" above for what
   replaced it.
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
10. **Nothing here — this one is closed, and was worse than it said.** It used
    to read: the web build still fetches emoji glyphs from Google, but a page
    load announces itself to nobody. The second half was false. CanvasKit keeps
    a default font of its own and downloads it from `fonts.gstatic.com` unless
    the app's manifest declares a family literally called `Roboto`; ours was
    called `Privio`, so every page load fetched Roboto from Google 760 ms in,
    with no interaction and no emoji involved. Declaring the same bundled files
    under both names stops it. The glyph-fallback base URL is now pinned to the
    app's own origin as well, so the emoji path cannot reach Google either — it
    finds nothing there and gives up, which is why emoji still render as empty
    boxes on the web build. Measured in a browser by watching every request the
    page makes, before and after.
11. **The web build has no keystore, and its local history is recoverable.**
    On iOS and Android the archive key lives in the Keychain or in
    EncryptedSharedPreferences, where the operating system holds it apart from
    everything else on the device. A browser has no such place.
    `flutter_secure_storage_web` generates an AES-256 key, stores it **raw** in
    `localStorage` under `FlutterSecureStorage`, and writes each value beside it
    as `base64(iv).base64(ciphertext)`. The app's own archive key is one of
    those values, so both layers peel with one read.

    Demonstrated, not inferred: `tools/web-storage-recovery.cjs` takes a copy of
    that origin's `localStorage` and no password, and comes back with all 112
    stored values — every Signal private prekey among them — and the
    conversation in the clear, message bodies and usernames and timestamps.

    There is no fix at this layer: a page cannot ask a browser for an
    OS-protected key. What there is, now, is a passcode: setting a screen lock
    wraps the archive key with Argon2id and deletes the readable copy, and the
    same recovery run against a locked device comes back with nothing. That is a
    mitigation and not a repair — the Signal keys are still in the clear, and a
    four-digit passcode is minutes of offline guessing — so the web build still
    says what it is on its first screen and in Privacy & Security, before
    anybody has typed anything. The phone builds are unaffected, and they are
    the target.
12. **No independent audit.** Before any public release, the crypto integration
    needs review by someone who was not involved in writing it.

## Reporting a vulnerability

Set up `security@privio.app` with a published PGP key before launch, commit to a
response window, and say so in the app's About screen. A privacy product without
a disclosure channel is not credible.
