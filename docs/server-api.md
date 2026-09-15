# The server API the client speaks

This is the contract between the Privio client and a Privio server. It exists
so the client can be built, tested and forked by somebody who has no access to
the server's source — which is the point of the split described in
[`distribution.md`](distribution.md).

Nothing here is a promise about *our* server's internals. It is the shape of
the requests the app makes and the answers it can cope with. A different
implementation that answers these is a server this client will talk to.

## What the server can and cannot see

Worth stating before the table, because it is the reason most of these routes
look the way they do. Every message, post, group name, private channel name,
backup and attachment arrives already sealed. The server stores and forwards
bytes it cannot read, and the routes below never carry a key: the one place a
key travels is inside an ordinary end-to-end encrypted message, relayed by
`POST /v1/messages` like any other.

One exception, named here rather than buried: a **reaction** on a channel post
is not sealed. The server holds `(post_id, account_id, emoji)` in the clear,
because a count has to be counted somewhere and an anonymous one could neither
be taken back nor stopped from being cast ten times. It says nothing about what
the post contains. `docs/security-model.md` sets out what follows from that.

See [`security-model.md`](security-model.md) for what that does and does not
buy, stated honestly.

## Authentication

A bearer token from `POST /v1/sessions`, sent as `Authorization: Bearer …`.
Tokens belong to one device. Routes marked **licensed** additionally require
the account to hold an entitlement on a server that sells access; the server
decides that, never the client.

## Routes

| Route | Notes |
| --- | --- |
| `DELETE /v1/accounts/me/avatar` | |
| `DELETE /v1/accounts/me` | |
| `DELETE /v1/backup` | |
| `DELETE /v1/blocks/:id` | |
| `DELETE /v1/channels/:id/avatar` | needs `canEditChannel` |
| `DELETE /v1/channels/:id/key-requests/:deviceId` | |
| `DELETE /v1/channels/:id/members/:accountId` | |
| `DELETE /v1/channels/:id/members/me` | |
| `DELETE /v1/channels/:id/posts/:postId` | |
| `DELETE /v1/channels/:id/bans/:accountId` | lets them speak again |
| `DELETE /v1/channels/:id/join-requests/:accountId` | turns them away |
| `DELETE /v1/channels/:id/posts/:postId/reactions` | `?emoji=` — removes only the caller's own |
| `DELETE /v1/channels/:id/posts/:postId/comments/:commentId` | the author, or `canDeletePosts` |
| `DELETE /v1/channels/:id` | |
| `DELETE /v1/contacts/:id` | |
| `DELETE /v1/devices/:id` | |
| `DELETE /v1/groups/:id/key-requests/:deviceId` | |
| `DELETE /v1/groups/:id/members/:accountId` | |
| `DELETE /v1/groups/:id` | |
| `DELETE /v1/media/:id` | |
| `DELETE /v1/messages` | |
| `DELETE /v1/sessions/current` | |
| `GET /v1/accounts/me/recovery` | |
| `GET /v1/accounts/me` | |
| `GET /v1/backup/content` | |
| `GET /v1/backup` | |
| `GET /v1/blocks` | |
| `GET /v1/calls/ice` | |
| `GET /v1/channels/:id/key-epochs/current` | |
| `GET /v1/channels/:id/key-requests` | |
| `GET /v1/channels/:id/members` | `?limit&cursor&q&role=admins`; `complete: false` means staff-and-self, not the audience |
| `GET /v1/channels/:id/posts` | `?scheduled=true` for the author's own queue |
| `GET /v1/channels/:id/posts/:postId/comments` | members only |
| `GET /v1/channels/:id/bans` | admins only — as a list it would name the audience |
| `GET /v1/channels/:id/join-requests` | admins only; people who are not members |
| `GET /v1/channels/:id/stats` | needs `canEditChannel`; deliberately carries no view count |
| `GET /v1/channels/:id` | |
| `GET /assets/channel/:handle` | **no auth** — a public channel's picture, for the invite page and its link preview. Served by magic number; anything that is not a PNG, JPEG, WebP or GIF is a 404 |
| `GET /v1/channels/discover` | |
| `GET /v1/channels/invite/:code` | |
| `GET /v1/channels` | |
| `GET /v1/contacts/invite` | |
| `GET /v1/contacts` | |
| `GET /v1/devices` | |
| `GET /v1/groups/:id/devices` | |
| `GET /v1/groups/:id/key-requests` | |
| `GET /v1/groups/:id` | |
| `GET /v1/groups/invite/:code` | |
| `GET /v1/groups` | |
| `GET /v1/keys/:username` | |
| `GET /v1/keys/count` | |
| `GET /v1/licenses/me` | |
| `GET /v1/media/:id` | |
| `GET /v1/messages` | |
| `GET /v1/users/:username` | |
| `GET /v1/users/id/:accountId` | |
| `GET /v1/ws` | |
| `PATCH /v1/accounts/me` | |
| `PATCH /v1/channels/:id` | also `{reactionEmojis, commentsEnabled}`; needs `canEditChannel` |
| `PATCH /v1/channels/:id/posts/:postId` | the author only — an admin may delete, not rewrite |
| `PATCH /v1/groups/:id` | |
| `POST /v1/accounts/me/totp/setup` | |
| `POST /v1/accounts` | |
| `POST /v1/accounts/me/duress-code` | |
| `DELETE /v1/accounts/me/duress-code` | |
| `PUT /v1/accounts/me/password` | |
| `DELETE /v1/accounts/me/totp` | |
| `POST /v1/accounts/me/totp/enable` | |
| `POST /v1/accounts/me/wipe` | |
| `POST /v1/licenses/redeem` | The one client-facing way to become licensed |
| `POST /v1/media` | `?expiresInSeconds` only shortens the retention, never lengthens it; ignored for avatars |
| `POST /v1/blocks` | |
| `POST /v1/channels/:id/join` | |
| `POST /v1/channels/:id/key-epochs` | |
| `POST /v1/channels/:id/key-requests` | |
| `POST /v1/channels/:id/posts` | `{publishAt}` schedules it; `{poll}` is its *shape* only |
| `POST /v1/channels/:id/posts/:postId/comments` | needs the channel to have comments on |
| `POST /v1/channels/:id/invite/rotate` | revoking is replacing; the old code dies at once |
| `POST /v1/channels/:id/owner` | `{accountId, currentPassword}` — the password, not the session |
| `POST /v1/channels/:id/report` | `{reason}` from a fixed set; never free text |
| `POST /v1/channels/:id/members` | direct-add; answers `{added, invite}` — only where their own `whoCanAddMeToGroups` allows it |
| `PUT /v1/channels/:id/read` | `{postId}`; only ever moves forward, so a stale device cannot un-read |
| `PUT /v1/channels/:id/mute` | per account, not per device; `{until}` or nothing for no end |
| `DELETE /v1/channels/:id/mute` | |
| `GET /v1/channels/:id/live` | `available: false` where no media server is configured — see docs/channels.md |
| `POST /v1/channels/:id/live` | `canManageLivestreams`; 503 `livestream_unconfigured` with no SFU |
| `DELETE /v1/channels/:id/live` | |
| `POST /v1/channels/:id/inbox` | sealed by the sender; closed unless `directMessagesEnabled` |
| `GET /v1/channels/:id/inbox` | `canManageMembers` only |
| `PUT /v1/channels/:id/inbox/:messageId` | marks one handled |
| `POST /v1/channels/:id/join-requests/:accountId` | lets them in |
| `POST /v1/channels` | |
| `POST /v1/contacts` | |
| `POST /v1/groups/:id/join` | |
| `POST /v1/groups/:id/key-requests` | |
| `POST /v1/groups/:id/members` | |
| `POST /v1/groups` | |
| `POST /v1/internal/licenses/revoke` | |
| `POST /v1/internal/licenses` | |
| `POST /v1/keys/one-time` | |
| `POST /v1/messages/group/:groupId` | `{expiresInSeconds}` bounds how long an undelivered envelope is kept |
| `POST /v1/messages` | same; clamped to 30 days, and it is a retention hint, not the chat's timer |
| `POST /v1/sessions/revoke-all` | |
| `POST /v1/sessions` | |
| `PUT /v1/accounts/me/avatar` | |
| `PUT /v1/accounts/me/recovery` | |
| `PUT /v1/backup` | |
| `PUT /v1/channels/:id/members/:accountId/role` | |
| `PUT /v1/channels/:id/avatar` | `{mediaId}`; needs `canEditChannel`. Always `kind=channel_avatar` — a channel picture is not sealed. A private channel's is served only to its members |
| `PUT /v1/channels/:id/posts/:postId/pin` | |
| `PUT /v1/channels/:id/posts/:postId/reactions` | `{emoji}` — must be one the channel offers |
| `PUT /v1/channels/:id/bans/:accountId` | silences without removing; needs `canManageMembers` |
| `PUT /v1/channels/:id/invite` | expiry, use limit, ask-first; needs `canManageMembers` |
| `PUT /v1/channels/:id/posts/:postId/votes` | `{options}` is the whole answer; empty takes it back |
| `PUT /v1/devices/current/push` | registering a token **takes** it: any other device holding the same one is cleared, because a vendor token is one app install |
| `PUT /v1/groups/:id/members/:accountId/role` | |
| `PUT /v1/keys/signed-prekey` | |

### Not part of this contract

`/v1/internal/*` is the issuing side — minting and revoking licence keys for
orders taken on the website. It authenticates with an issuer token that no
client has and no client should have, and it belongs with the private half of
the split. It is listed above only because it is registered by the same file;
a client never calls it.

## Entitlement, and who decides it

The client never decides whether it is licensed. There are exactly two ways an
account becomes entitled:

* `POST /v1/licenses/redeem` with a key the server hashes and looks up. Used by
  the `libre` and `direct` builds, which are paid for on the website.
* An issuer-side grant against a verified store purchase, for the `play` and
  `appstore` builds. **This is not implemented** — see
  [`distribution.md`](distribution.md) for exactly what it needs. There is no
  endpoint that accepts a receipt today, deliberately: one that took a receipt
  without verifying it would be a free pass wearing a lock.

`GET /v1/licenses/me` reports the answer. A client that ignores it can still
sign in and read what has already arrived; sending is what the server gates. A
build with the activation screen deleted therefore gains nothing.

## Testing a client against it

No production server is needed and none should be used. The client's own suite
runs against `MockClient` fakes of these routes — see
`app/test/support/fake_server.dart` — which is enough to drive registration,
sending, groups, channels, key delivery, calls and backup end to end.

That is deliberate: a contributor who wants to change the app should not have
to be trusted with a server, and a test that needs one is a test nobody runs.
