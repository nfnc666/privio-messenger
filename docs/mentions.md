# Mentions

`@max` in a message is a name you can tap. This is what counts as one, what
happens when it is tapped, and what it deliberately does not do.

## One tokenizer

`MessageText.split` takes a body apart into plain, link and mention runs, and it
is the **only** place that decides which is which. Links and mentions compete
for the same characters — `@` inside a URL, a name inside a code block — and two
passes would disagree about who owns them.

Its guarantee: joining every run's text gives the original back, unchanged. That
is what keeps selection, copying, custom emoji and the existing link handling
working; nothing is rewritten, only marked.

| Written | Linked | Why |
| --- | --- | --- |
| `Schreib bitte @max` | `@max` | |
| `Hallo @max!` | `@max` | Punctuation belongs to the sentence |
| `Frag @max.` | `@max` | A trailing full stop is a sentence, not part of a name |
| `@max.mueller kommt` | `@max.mueller` | A dot inside a name is part of it |
| `@max und @lena` | both | |
| `@Max` | `@Max`, resolved as `max` | Names are stored lower-case and cannot differ by case |
| `max@example.com` | nothing | A word character before the `@` makes it an address |
| `@max@example.com` | nothing | An `@` straight after the name says the same |
| `https://example.com/@max` | the URL only | Inside an address, `@` belongs to the address |
| `` `@max` `` and ```` ```…``` ```` | nothing | Quoted text is shown, not interpreted |
| `@@max`, `@ab`, a name of 33 characters | nothing | Not a name this app would link |

The length ceiling is a trailing lookahead, not a truncation: thirty-three
characters is **not a name**, rather than a shorter name that happens to exist.

Drawn in the account's accent, in semibold, and with **no underline** — an
underlined name reads as a web address, which is the one thing a mention must
not be mistaken for, because the two do completely different things when tapped.

## What a tap does

1. Resolves the username through `GET /v1/users/:username` — the ordinary
   authenticated route.
2. Checks the answer is about the name that was tapped. A reply about anybody
   else opens **nothing**; the failure mode is a message, never the wrong
   profile.
3. Opens the existing `ContactProfileScreen` **by account id**.

So the profile is the one every other entry point shows, with the same actions:
message, voice and video call, add or remove contact, block, report. Nothing is
sent, added or dialled automatically.

**Message** reuses the conversation that exists. From a group or a channel it
replaces the profile route with that person's chat, leaving the group
underneath — so going back returns to the group at the position it was at, with
its unsent draft intact. From that person's own one-to-one chat it simply goes
back, rather than stacking a second copy of the conversation already below.

A name that resolves to nothing — never registered, or an account since
deleted — says so in one sentence and opens nothing. The two cases are the same
404 and read the same, because to whoever tapped, they are the same thing.
Offline says to check the connection.

## What it is not

**Not a lookup while reading.** Detection is local, on plaintext already
decrypted on the device; no message text is sent anywhere to find out what is in
it. Nothing asks the server whether a name exists until somebody taps it — a
chat full of names would otherwise be a burst of profile requests, telling the
server who is reading which conversation and when, for names nobody may ever
tap. `mention_tap_test.dart` asserts that opening a chat containing `@max` makes
no request at all.

**Not a grant.** The tap uses the same route, with the same session, as every
other profile screen. Visibility, blocking and contact and call restrictions are
decided server-side exactly as before. Writing somebody's name in a message
cannot open a door that was shut, and it discloses no phone number and no hidden
profile field — the reply is `publicProfile`, unchanged.

**Not a notification.** No mention push, no badge, no new event of any kind.
That is a separate decision with its own consequences and is not smuggled in
here.

**Not a structured payload.** A mention is the characters in the message; there
is no account id travelling beside them. Nothing new goes on the wire, so an
older build shows exactly the text that was typed. If a structured form is ever
added it belongs **inside** the sealed content and must be validated against the
username it claims — the id and the name disagreeing is the case that would open
the wrong profile.

## Typing one

An `@` in the chat composer offers suggestions from two lists this account
already holds:

* its own address book, and
* in a group, the members the **server** decided this account may see, fetched
  once per open chat and only after somebody actually types an `@`.

Each row shows the picture, the display name and the `@username`, because the
display name is what somebody recognises and the username is what gets inserted
— and two people may share a display name. Picking one inserts the whole name
and a space.

**No prefix search reaches the server.** There is no route that answers "who
starts with ma", and this feature does not add one: that is a tool for reading
off the user list. Channel composers offer nothing at all, because the only list
there would be the subscribers, which is private.

A name can always be typed out in full by hand, whether or not it was suggested
— the suggestions are a convenience, never the only way in.

## What is tested

`app/test/mentions_test.dart` (41) covers the tokenizer and the composer logic:
every row of the table above, several mentions in one message, the rejoin
guarantee across nine samples, which `@word` the caret is inside, who is offered
and in what order, two people sharing a display name staying two people, and
what a pick puts in the field.

`app/test/mention_tap_test.dart` (12) covers the tap, through a server that
answers by username: a one-to-one chat, a group, a channel post, a photo
caption, two mentions in one message each opening their own profile, the accent
colour on the span, an unknown account, a deleted account, offline, a reply
about a different name, a name the server will not even look up, and `@MAX`
reaching `max`. It also asserts that **reading** the chat made no request.

Falsified: dropping the "the answer must be about the name that was tapped"
check turns that test red; resolving mentions while the text is built turns the
no-lookups test red.

## Not verified on a device

Everything above is widget and unit tests. Rows M1–M6 of
[`device-beta-checklist.md`](device-beta-checklist.md) are what a phone has to
answer: a tap target big enough for a thumb, the suggestion bar over a real
keyboard, and text selection across a mention on each platform, where the two
behave differently.
