# Photos in a chat

Taking a picture and sending it, and choosing pictures and sending them. Both
end in the same place as every other attachment: `ConversationController`, the
outbox, and `AttachmentCipher`. Nothing here is a second media path.

## The two ways in

| Button | Opens | Code |
| --- | --- | --- |
| Camera, next to the text field | the system camera, directly | `_ChatScreenState._capture` |
| Plus → **Choose photos** | the system photo picker, directly | `_ChatScreenState._pickPhotos` |
| Plus → **Send a file** | the file browser, as before | `_ChatScreenState._attachFile` |

The disappearing-messages timer keeps its place in the composer and its
behaviour. It is the one button in that row whose state somebody can be hurt by
not noticing, so the camera went beside it rather than over it.

## What happens to a picture before it is sent

`PhotoImage.prepare` (`app/lib/media/photo.dart`), in this order, and the order
is load-bearing:

1. `MetadataScrubber.scrub` runs on the **original**, only to produce the report
   the chat's existing notice shows.
2. `ImageDecode.any` decodes the original — Dart's decoder first, the platform's
   codecs second. **This is what reads HEIC**, which is what an iPhone writes by
   default.
3. `img.bakeOrientation` turns the pixels the way the EXIF tag said they should
   be shown. This must happen before the tag is removed; doing it the other way
   round arrives with every portrait photo on its side. `photo_test.dart` holds
   it: a JPEG tagged orientation 6 comes out 600×800, and the test failed when
   the two steps were swapped.
4. Resized so the longest edge is at most 2048 px, never upscaled.
5. `image.exif = ExifData()` — the location, the camera model, the timestamp,
   all of it. `photo_test.dart` checks the file that comes out rather than
   trusting the encoder.
6. Encoded as JPEG at quality 82, dropping to 65 and then 50 and then shrinking
   further if it is still over 8 MiB — deliberately under the server's own
   limit, because the point is to arrive.

The file name is invented: `photo-1.jpg`, `photo-2.jpg`. **Never the name off
the camera roll and never a path.** A camera-roll name can carry a date and a
counter; a path can carry a person's name. Neither is needed to draw a picture.

Several pictures are prepared **sequentially**, not with `Future.wait`, so the
order they were chosen in is the order they are sent in.

## Access, and what is deliberately not asked for

`ImagePickerPhotoSource` passes `requestFullMetadata: false`. On iOS that keeps
Privio out of the photo library: `PHPickerViewController` hands back the pictures
that were chosen and nothing else, and the app never asks to read the library.
The camera permission is requested by the plugin at the moment the camera is
opened, which is the only moment it is wanted.

A refusal comes back as `PhotoRefused`, and the screen offers the one thing that
can be done about it — both platforms stop showing their dialog after the first
no, so the settings page is the answer and "ask again" is not. `SystemSettings`
opens it. **The Android half of `openSettings` did not exist** until this change:
the notification screen had shipped that button with nothing behind it on
Android. `AppSettings.kt` is the handler.

Nothing is written to the public gallery. A capture goes to the app's own
temporary directory; a library selection is *copied* into that same private
directory before the path is handed over. `_readAndTidy` reads the bytes and
deletes that copy — **the original in the library is never touched.**

## Sending

`ConversationController.sendPhotos` queues each picture in the **outbox**, the
road a voice message takes, rather than the one `sendAttachment` takes. The
difference is what the user sees:

* the bytes are sealed before anything is persisted, so the only copy that can
  be written to disk is ciphertext;
* the upload happens once and the media id and token are written back into the
  queue entry, so a retry after a failed *send* does not upload again;
* the queue is keyed on the client id, which the server also treats as the
  idempotency key — **a retry cannot produce a second picture in the chat.**
  `sendAttachment` had none of this: a failed photo sat on "sending" forever
  with nothing to do about it.

The caption goes on the first picture only. Six photos with the same sentence
repeated under each is not what anybody means by adding a caption.

States under one's own photos: **Sending**, **Waiting for a network**, **Sent**,
**Not sent** — the last with the long-press retry the outbox already had. `Sent`
is not permanent noise: a delivery receipt moves the message to `delivered` and
the line goes with it.

A disappearing-messages timer applies to pictures, and the clock starts when the
server takes the photo, not when it was chosen. A picture queued with no signal
has no expiry at all, or it would vanish from the sender's own chat before it had
been anywhere and then send.

## The account guard

A picker is open for as long as somebody takes to choose, and a preview for as
long as they take to write a caption. Both are ample time to switch accounts.
`sendPhotos` takes the account the photos were chosen in and drops them if it is
no longer the current one — re-checked after every seal, not once at the top.
The chat screen checks the same thing before scrolling. `photo_send_test.dart`
holds it.

## Looking at one

A picture in a bubble is a thumbnail; tapping it opens `PhotoViewer` with pinch
and pan. The viewer was private to the channel feed and the chat had nothing —
one widget now, used by both. It is handed bytes that are already decrypted, so
opening it fetches nothing and writes nothing.

There is deliberately **no "save to gallery"**: that would copy a message out of
the app's storage and past the disappearing-messages timer, into a folder every
other app on the phone can read.

## Encryption

Unchanged, and that is the point. `sendPhotos` seals with `AttachmentCipher` and
sends a `MessagePayload.media` exactly as voice does. The key travels inside the
end-to-end encrypted payload; the server sees a blob and a token. There is no
fallback path that sends a picture unencrypted, and none was added.

The pictures are held in `_attachmentCache` in memory while a chat is open and
are never written to disk in the clear.

## Tests

`app/test/photo_test.dart` (13) — decoding, orientation, resizing, the size
limit, the invented name, order, one unreadable file among several, and that a
GPS tag does not survive.

`app/test/photo_picker_test.dart` (14) — what each exception from the picker
means, a build with no camera, and the preview: cancel sends nothing, send hands
back the pictures and the trimmed caption, removing one leaves the rest in order,
removing the last is a cancel, and Retake is its own answer.

`app/test/photo_send_test.dart` (10) — a photo arrives as a picture, order,
caption on the first only, the invented name, queueing with no network, a retry
that sends once more rather than a second photo, the account switch, and the
disappearing timer on both sides of the send.

Falsified, then reverted: removing the account check turns the switch test red;
putting the caption on every picture turns the caption test red; swapping the
scrub and the decode turns the orientation test red. The empty-preview crash was
found by its own test rather than by reasoning about it.

## Not done here — device testing

Everything above is automated tests and the analyzer on a build machine. **None
of it has been run on a phone.** Still open, and needed before this is called
finished:

* an actual capture on iOS and on Android, front and back camera, flash;
* HEIC from a real iPhone camera roll, and a portrait photo's orientation;
* multi-select in the real system picker, and the "selected photos only" case on
  iOS 14+;
* a refused camera permission on both platforms — in particular whether Android
  reports it as `camera_access_denied`, which is what `photoPickFailure` maps;
* `openSettings` landing on the right page on both;
* a large photo over a slow connection: the progress, the failure, and the retry;
* receipt and decryption on a second account.
