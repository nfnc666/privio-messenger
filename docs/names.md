# Two names

Every account has two, and almost everything here follows from keeping them
apart:

| | `@username` | Display name |
| --- | --- | --- |
| Chosen | once, at sign-up | whenever you like |
| Unique | yes, case-folded | no |
| Contents | `a-z 0-9 _ .`, 3–32 | anything, up to 50 visible characters |
| May be empty | no | yes — then the `@username` stands in |
| Used to address anything | yes | never |

## Why the username cannot change

It is the address. It is what an invite link carries, what somebody types to
find you, and the one thing on a profile row that cannot be made to look like
somebody else's — a display name can be set to "Support" by anybody, and
`@support` cannot.

That guarantee is only worth what enforces it, so it is enforced three times
over, and the order matters:

1. **There is no route.** Nothing in the API renames an account, and
   `PATCH /v1/accounts/me` now **refuses out loud** when a `username` key is
   present rather than stripping it and answering 200 — a caller that asked to
   be renamed used to be told it worked.
2. **There is a trigger.** `035_username_is_permanent.sql` raises on any
   `UPDATE` that changes `accounts.username`. A future handler, a migration
   script or somebody at a psql prompt all pass through it. "No endpoint does
   this" is a fact about today's routes; this is a fact about the account.
3. **There is no button.** The account screen shows the username as a row with
   a copy icon and nothing to tap, next to a display name that opens an editor.
   Somebody who wants to "change their name" finds out in one glance which of
   the two they can change.

### The one exception, stated precisely

Deleting an account renames it to `deleted.<id>` so the name it held can be
used again. That is why the rule is a trigger rather than a revoked column
privilege: the trigger allows a rename **only on the transition from live to
tombstone** — `OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL` — and a
tombstone cannot be renamed again. A lock that broke account deletion would be
a worse bug than the one it prevents, and
`server/test/names.test.ts` fails if either half of that stops being true.

### Case

The column accepts `^[a-z0-9_.]{3,32}$` and the API lowercases on the way in,
so `Lighthouse` and `lighthouse` are one name. Nothing was added for this — it
is asserted rather than implemented, because two accounts indistinguishable in
a chat list is exactly what a unique address is for.

### Racing for a name

Two registrations that ask "is it free?" at the same moment both hear yes. What
separates them is the `UNIQUE` constraint and nothing else: the loser's insert
raises `23505` and is turned into the same `username_taken` the polite check
would have given. The test drives both requests concurrently and asserts one
201, one 409, and exactly one row.

### Asking before committing

`GET /v1/usernames/:name` answers `{available, reason}` — `taken`, `format`, or
free. It discloses that a name exists, which registration already discloses by
answering `username_taken`, so it adds no new fact; what it adds is a cheaper
way to ask, so it is on the same per-address budget as a password attempt.
There is still no way to *list* names: one at a time, and no prefix search
exists anywhere in this API. A reserved name answers `taken` like any other,
because confirming the reserved list to whoever is probing it would be the
disclosure that actually matters.

The sign-up screen asks when the field loses focus — not per keystroke, which
would be a request per letter — and the answer is advisory. A name the server
has not answered about is never refused locally: registration is the authority,
and an offline check must not stop somebody signing up.

## Why the display name can be anything

It is what a person calls themselves. Spaces, umlauts, scripts of every kind
and emoji all work, two people may have the same one, and it can be changed as
often as anybody likes — there is no waiting period and nothing to pay for.

Two things are done to it, and both are about what cannot be seen:

* **Invisible characters are removed.** Controls, the soft hyphen, the bidi
  marks, overrides and isolates, the zero-width space, the byte order mark. A
  right-to-left override reorders the line it is drawn in — including the
  `@username` beside it, which is the one thing on that row that is supposed to
  be unforgeable. Zero-width padding also buys a longer name than the limit
  allows.
* **The joiners are kept.** ZWJ and ZWNJ hold an emoji family together as one
  glyph and separate letters in Persian, Hindi and others; the variation
  selectors choose between a character's text and emoji shape. Removing those
  would misspell a name rather than clean it.

**Fifty characters as a reader counts them.** `String.length` makes one family
emoji eleven characters and one flag eight, so the limit is measured in grapheme
clusters — `Intl.Segmenter` on the server, `Characters` in the app. The two
copies of this rule are deliberate: the server's decides what is stored because
it is the only one an attacker cannot skip, and the app's exists so the field
can say "too long" while somebody can still do something about it.

**Empty is an answer.** Clearing the field removes the name and the account is
drawn as its `@username` again. This needed a real change on both sides:

* the server's `COALESCE(display_name, …)` could not tell "not mentioned" from
  "set to nothing", so nobody could ever delete their display name;
* the app's `KnownUser.merge` treats a missing value as "no news", which is
  right for a fact that arrived inside a message and wrong for a contact list —
  so `upsertUser` takes an `authoritative` flag, and only an answer that
  describes the whole person may remove a name. Without it, somebody's
  discarded name would stay on other people's screens forever.

## What a name is not

Nothing is keyed on either name except the address book lookup that exists to
turn one into an id. Chats, contacts, group membership, blocks and every
encryption key hang off the account id — which is why a rename keeps the
conversation, its history and its safety number, and why two people called
"Alex Taylor" are two people.

Verified badges stay UI: they are drawn from what the server says about an
account, never from anything inside a name.

## Where each name is drawn

The display name is the name — chat list, chat header, group member lists,
contact profiles. The `@username` sits underneath it in the contact profile and
in the member list, and in search results both are shown, so two people with
the same display name stay distinguishable. Most of this needed no change:
`Conversation.title` was already `displayName ?? username`, and the contacts
list already put `@username` in the subtitle.

PRIVIO has **no per-contact local alias** — the server has never accepted one
(migration 013 keeps nicknames off the server deliberately) and the app has
never offered one. There was nothing to respect here, and nothing was invented
to fill the gap.

## What is tested

`server/test/names.test.ts` (13) and `app/test/profile_name_test.dart` (17).

On the server: a free name, a taken name, the same name in shouted case, two
registrations racing, the API refusal with nothing else in the request applied,
a direct `UPDATE` refused by the trigger, deletion still releasing the name and
the tombstone still locked, then the display name — accents and emoji kept and
reloaded, cleared and distinguished from absent, fifty family emoji accepted
and fifty-one refused, a bidi override dropped, two accounts sharing a name,
and nobody able to edit anybody else's.

In the app: the shared cleaning rules, the controller (load, save, clear,
refuse-too-long, a failed save that is not shown as saved, an answer dropped
after an account switch), the store (two identical names staying two people, a
rename keeping the history, a removal reaching this device, a message-borne
fact never removing a name), and the screen (username copyable not editable,
Save and Cancel offered only when something changed, too long refused before
any request).

Falsified: removing the API's refusal, the trigger's deletion exception, and
the authoritative clearing each turn their own test red.

## Not verified on a device

Rows **N1–N5** of [`device-beta-checklist.md`](device-beta-checklist.md): the
sign-up flow on a real keyboard, an emoji name typed with a system picker,
what a 50-character name does to a chat-list row, and a name changed on one
phone appearing on another.
