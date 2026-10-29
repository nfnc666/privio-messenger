# Photos to be viewed once

**Status:** implemented in the app and tested automatically. Not yet confirmed
on real devices. The server is unchanged.

A photo sent this way can be opened once by the person it is for, on one of
their devices, and then it is gone from that device. Nobody else can open it
again, the sender included.

## What it promises, and what it does not

It promises that **no copy is kept by the app**: not in the chat, not on the
sender's devices, not in Saved, not in a backup, and not on the recipient's
other devices once one of them has opened it.

It does **not** promise that nobody can keep a copy. The viewer says so at the
bottom, in words that depend on the phone:

* **Android:** screenshots and screen recordings are refused while the photo
  is open (`FLAG_SECURE`), whatever the account chose for the rest of the app.
  A second camera pointed at the screen is not stopped.
* **iPhone:** a screenshot cannot be stopped by any app. A screen recording or
  mirroring is detected, and the photo is covered for as long as it runs.
* **Anything else:** nothing can be blocked, and the viewer says that.

Anything stronger than this would not be true, so the app does not claim it.

## On the wire

A new payload type, `once`, inside the sealed message. It carries what an
ordinary photo carries: the media id, the key, the download token, the type
and the size. It has no caption: a caption would stay in the chat after the
picture had gone.

Its own type rather than a flag on `media`, and that is the important part. A
build from before this reads a type it does not know as text, and shows `b`:
"A photo that can be viewed once. Update Privio to open it.", in the sender's
language. A flag on `media` would be ignored by such a build, and the photo
shown and kept like any other.

The server sees an upload and a message, exactly as for any photo. Which kind
of photo it is lies inside the sealed payload.

## Who holds the key, and when

| | Key |
| --- | --- |
| Sender, while the photo waits to go | In the outbox, as for any photo |
| Sender, once it has gone | **Nowhere.** The bubble never had it; the outbox entry goes with the delivery |
| Sender's other devices | **Never.** Their copy (`once` without `id`, `k`, `tk`) says that it went, not how to open it. In a group, where the fan-out reaches them directly, they are sent the same keyless copy |
| Recipient, before opening | In the chat, in the encrypted archive on that device |
| Recipient, after opening | **Nowhere.** Dropped and written to the archive before the picture is shown |
| Recipient's other devices | Until one of them opens it. That one tells the others (a receipt of kind `opened`, sent only to this account's own devices); each then drops its key |
| A backup | **Never.** The backup writes the bubble without its attachment |

The key is dropped **before** the picture is shown, not when the viewer
closes. A viewer that never closes properly, because the app was killed or
the phone died, must not leave a photo that opens a second time. A fetch that
fails leaves the photo unopened, so it can be tried again.

The ciphertext stays on the server until its ordinary expiry, as for any
attachment. Once every key is gone it is bytes nobody can open.

## Refused

* **Saved.** A note to oneself that vanishes when read is not one, and the
  preview does not offer the switch there.
* **Saving to Saved from a chat.** The action is not offered, and the
  controller refuses it with a reason if it is asked anyway.
* **Copying.** There is no text to copy, and nothing in the viewer saves or
  shares.

## Copies from this account's own devices

Building this showed that a copy "from another of this account's devices" was
accepted from anybody. Any contact could send one, and the app would file it
as written by this account, take back this account's messages, move a group's
timer past the admin check, or (with this change) mark its photos opened. Such
a copy is now taken only when it comes from this account.

## Tests

`app/test/view_once_test.dart`: the payload, two devices of one account
against a fake server, sending and receiving in the controller, the bubble,
the preview, the viewer and the screen protection, and the chat screen. Every
rule there was broken on purpose once and its test went red.
