# Stickers and custom emoji

A pack is a list of pictures somebody made, and a link that hands it to other
people. This is what that costs and what it does not.

## Read this first: sticker pictures are not encrypted

An ordinary Privio attachment is sealed with a key that travels inside the
message. A sticker cannot work that way, and the reason is the feature itself:
**a pack is shared by link with people who hold no key of the author's.** Sealing
it would mean either shipping the key inside the link — which is the same as not
sealing it — or a preview that cannot show what it is previewing.

So the decision is made once, openly, and said in the app before anybody shares
anything:

- Sticker images are stored unencrypted. This server can read them, and so can
  anybody the link reaches.
- They are the **one** upload whose contents the server inspects — type,
  dimensions and animation, read from the bytes rather than from what the client
  claims. That is possible precisely because they are not sealed, and it is worth
  doing because a pack is public-ish by construction.
- Everything else is unchanged. Messages, attachments, voice notes, group and
  channel posts are still sealed and the server still cannot open any of them.

### Who can fetch a picture

Any signed-in account that can name its media id.

That is wider than "the owner and whoever installed the pack", and the narrower
rule was tried first and did not work. A sticker is *sent to people*, and almost
nobody you send one to has installed the pack it came from — under the narrow
rule their client fetched, got a 404, and drew the fallback character. Sending a
sticker outside your own pack's audience did nothing at all.

What the wider rule does **not** open, which is what keeps it worth having:

| | |
| --- | --- |
| The pack | Its title, its other stickers and installing it all still want ownership, an install, or a live share code. |
| An unattached upload | Still its uploader's alone, so an id is not a download until a pack points at it. |
| Who received it | The id travels only inside sealed envelopes. The server never learns who was sent one. |

The id is a random uuid: unguessable, and a capability in the same sense a
private channel's invite code is one. A recipient can pass it on — exactly as
they could pass on the picture itself.

## The fallback is a real character, always

This is the single rule the whole message format rests on, and it is repeated in
three places because it is what keeps old clients, missing packs and deleted
packs from turning a conversation into empty squares.

- **A sticker message** puts the emoji it stands for in the payload's `body`. A
  client that has never heard of the `sticker` tag decodes it as an ordinary
  text message and shows that emoji. No negotiation, no version check.
- **Custom emoji in a sentence** travel as an *overlay*. The body already
  contains the fallback characters; a separate list says which spans a reader
  holding the pack may draw as pictures instead. An older build shows a
  perfectly ordinary sentence. So does a reader whose pack was deleted.
- **A custom-emoji reaction** still sends a real character. The picture is an
  extra, never a replacement.

The alternative — a marker in the text like `[[emoji:8f21…]]` — is how these
usually end up rendering in somebody's notification. The overlay is more code
and it is the reason that cannot happen.

Spans are validated against the text when a message is decoded, and again when
it is read back from the archive. A span from another device that ran past the
end of the body would be a range error inside a message list — a crash, on a
message somebody sent you. An invalid one is dropped and its fallback character
stays visible, which is the worst this can do.

## What a tap on a sticker can and cannot do

It opens the pack when this account owns it or has added it. Otherwise it says
the pack is not available.

It cannot do better, and this is the limit rather than an omission: a pack is
reached by its **share code**, not by its id, and the code is what an owner
revokes. A sticker carries the id — enough to fetch the picture and to recognise
the pack, not enough to open one that was never shared with this reader. Putting
the code into every message would make revoking it useless, because it would
already be in everybody's history.

## Editing and deleting a pack

Deleting is a soft delete. The row and the images stay, and that is deliberate:
stickers from the pack are already in other people's conversations, and turning
those into empty squares to tidy up a picker would be the wrong trade. What
deleting does is unshare it and take it out of the picker.

Reordering, renaming and adding do not disturb anything already sent: a message
points at an **item id**, which is stable for the life of the item.

## Where things live

| | |
| --- | --- |
| `server/migrations/028_sticker_packs.sql` | packs, items, installs, uses |
| `server/src/services/image_header.ts` | PNG and WebP header parsing, by hand |
| `server/src/routes/stickers.ts` | CRUD, sharing, installs, favourites |
| `app/lib/core/sticker_controller.dart` | packs per account, and the picture cache |
| `app/lib/media/sticker_image.dart` | crop, resize, PNG with transparency |
| `app/lib/widgets/sticker_picker.dart` | the composer's Emoji / Stickers / Mine tabs |
| `app/lib/widgets/custom_emoji_text.dart` | the overlay, and the sticker view |

The picture cache is in memory and nowhere else. That is what makes "kept apart
between accounts" true rather than intended: there is no file left behind, and a
switch empties the map.
