# What the Privio server can see

Message *content* is not on this list, and that is the point of the list. Bodies,
attachments, group names, channel post bodies, voice recordings and captions are
sealed on a device before they are sent; the server holds ciphertext and the
routing it needs to move it. Everything below is what is left over, and some of
it is more revealing than people expect.

This is a review, not a claim of privacy. **Where something is visible, this
document says so.** Nothing here is described as hidden unless it is.

Classifications used:

| Mark | Meaning |
| --- | --- |
| **required** | The service cannot route messages without it |
| **stored** | Written to the database and kept |
| **transient** | Held only for the life of a request, a socket, or a log rotation |
| **reducible** | Could be cut down without redesigning anything |
| **hideable** | Could be removed by a design change, with real cost |

---

## 1. IP addresses

**Required (transient) · stored in logs · reducible**

Every HTTP request and WebSocket connection arrives from an address, and the
server sees it. `trustProxy` is on, so it is the client's address rather than
the reverse proxy's.

* Not in any table. There is no column anywhere in `server/migrations/` holding
  an IP.
* **In the application log.** `src/app.ts` serialises `remoteAddress:
  request.ip` on every request, at `LOG_LEVEL` `info` by default. Anyone with
  access to the logs can reconstruct which address connected, when, and to which
  endpoint — including `/v1/keys/:username`, which is a lookup of a specific
  person. **This is the single largest gap between what Privio promises about
  content and what its operator can observe about behaviour.**
* Used in memory for rate limiting.

**Reducible:** the log serialiser could drop `remoteAddress`, or hash it with a
per-day server secret so rate-limit debugging still works and correlation across
days does not. That is a small change and it is not made yet.

**Not hideable** by Privio alone — the network layer sees the address. Tor or the
existing SOCKS5 proxy (`docs/custom-proxy.md`) is the only real answer, and that
moves the observation to the proxy operator rather than removing it.

## 2. Connection timestamps and presence

**Required · stored · reducible**

* `accounts.last_seen_at` and `devices.last_seen_at` are written on activity.
  Who may *see* last-seen is a user setting; the server holds it regardless.
* `sessions.last_used_at`, `created_at`, `expires_at`.
* An open WebSocket is, by its nature, a statement that a device is online now.

**Reducible:** `last_seen_at` could be rounded to the hour or the day for storage
purposes. The current value is minute-accurate and is written on every request.

## 3. Push tokens

**Required for push · stored · not hideable while push exists**

`devices.push_provider` and `devices.push_token`, in the clear. A push token is
a stable identifier issued by Apple or Google for a specific app installation.

Two consequences worth stating rather than glossing:

* The token links a Privio account to a device registration at Apple or Google.
* Sending a push tells Apple or Google that *this installation* has traffic now,
  even though they cannot read the content. Privio sends no message text in a
  push payload, but the timing is visible to them by construction.

The Libre build's UnifiedPush path moves this to a distributor the user chose
rather than to Google. It does not remove it.

## 4. Message timing

**Required · stored until delivery · reducible in retention only**

`envelopes.created_at`, one row per recipient device. The server necessarily
learns when a message was accepted and when it was fetched. Rows are deleted on
delivery (`services/delivery.ts`) and swept after `ENVELOPE_TTL_DAYS` (default
30) if never collected.

**Not hideable.** A store-and-forward server that did not know when things
arrived could not forward them.

## 5. Ciphertext size

**Visible · not stored beyond the row · partly mitigated**

`envelopes.content` has a length, and `media_objects.byte_size` is stored
outright. Length leaks more than it looks: a one-word reply and a paragraph are
distinguishable, and a photograph's size is close to a fingerprint of the
photograph.

Privio pads message payloads (`app/lib/crypto/padding.dart`) to bucket
boundaries, which removes the fine-grained signal for text. **Media is not padded
** — `byte_size` is the real length, and it is stored. That is a known gap.

## 6. Sender and recipient routing

**Required · stored until delivery · not hideable in this design**

`envelopes.recipient_device_id` and `envelopes.sender_account_id`. The server
knows who sent what to whom, at the account level, for as long as the row exists.

This is the most important line on the page. Privio has **no sealed sender**:
there is no equivalent of Signal's construction where the server learns the
recipient but not the sender. A conversation's content is private; the fact that
it happened, between whom, and when, is not.

**Hideable in a future design** — sealed sender is the published answer — and
doing so would need delivery tokens, a different abuse-control story, and a
review. It should not be claimed until it exists.

## 7. Group membership

**Required · stored**

`group_members` maps accounts to groups, and `groups.group_id` appears on
envelopes. The server knows who is in which group even though group *names* are
sealed (`groups.name` is a client-encrypted blob).

**Not reducible** without a redesign: the server fans a group message out to
member devices, so it must know the members.

## 8. Channel membership

**Required · stored**

Channel subscriptions are rows. For a **public** channel the title, handle,
description and picture are stored unencrypted by design — they are on a web
page — and the subscriber list is server-side. Posts stay end-to-end encrypted.

The verified official channel (`docs/official-channel.md`) is a normal channel
with a flag; membership in it is as visible as any other.

## 9. Call signalling metadata

**Required · transient**

Call setup rides through `envelopes` as `call_signal`, so the server sees that a
call was offered between two accounts and when. **SDP and ICE are inside the
sealed payload**, so candidate IP addresses are not visible to the Privio server
— but see `docs/calls-security.md`: media is peer-to-peer or through a TURN
server, and a TURN server sees both endpoints' addresses and the call's duration
and bitrate.

No call log is stored server-side. The call history on the device is local.

## 10. Device information

**Required · stored**

`devices.name` (a name the user typed), `devices.platform` (`ios`/`android`/
`desktop`/`web`), `registration_id`, `identity_key`. Public keys by design —
X3DH needs them. `sessions.user_agent` is stored as sent.

**Reducible:** `user_agent` is not used for anything the app needs and is a
fingerprint. It could be dropped or coarsened.

## 11. Phone number and contact discovery

**Reduced by design · stored as a keyed hash**

`phone_links.discovery_hash` is `HMAC(server pepper, HMAC(public context,
E.164))`. An address book never reaches the server as plaintext, and a stolen
table is useless without the server's secret.

**What this is not:** it is not anonymity and it is not private set
intersection. The inner context key is public and phone numbers are a small
space, so a server that holds the pepper can brute-force its own table. The
daily per-account lookup budget (`contact_lookup_budget`) is the real defence
against enumeration, not the hashing. `docs/phone-contacts.md` says the same
thing at more length, and this document does not upgrade it.

`phone_links.hint` stores a calling code and the last two digits, for a settings
screen. It is never shown to anybody but the owner.

## 12. Account identifiers

**Required · stored**

`accounts.username` is public by design — it is how people find each other.
`display_name` likewise. `privacy` (jsonb) holds the user's own settings.

## 13. Administrative and operational

* Backups: `recovery_blob` and the backup blobs are client-sealed. The server
  sees size and time.
* Media: `media_objects` holds an owner, a size and an expiry. Contents are
  sealed, and the media token is stored only as a hash.
* Licences, sticker packs, bots: rows exist and are visible. **Bot conversations
  are not end-to-end encrypted at all** and their message bodies are stored in
  `bot_messages` in the clear — this is stated in `docs/bots.md` and on screen,
  and it is the one place in Privio where the server can read a message body.

---

## Summary of the honest gaps

Five things on this page are worth acting on, in this order:

1. **IP addresses in the request log.** The cheapest real improvement available,
   and currently the largest observation surface.
2. **No sealed sender.** The server knows who talks to whom. Design work, not a
   patch.
3. **Media size is unpadded and stored.** Text is padded; attachments are not.
4. **`sessions.user_agent`** is a stored fingerprint nothing needs.
5. **`last_seen_at` precision** is finer than any feature requires.

## What must not be claimed

* That Privio hides who is talking to whom. It does not.
* That contact discovery is anonymous. It is a keyed hash with a lookup budget.
* That bot chats are encrypted. They are not.
* That metadata is "minimal" without pointing at this page.

Anything on this list that changes should change this document in the same pull
request.
