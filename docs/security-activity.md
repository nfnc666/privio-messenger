# Security activity, and the privacy overview

Two screens under **Settings → Privacy & Security**, and one rule they share:
neither of them says anything it has not been told.

## Security activity

`Settings → Privacy & Security → Security activity`

A list of things that happened to this account's security, kept **on this device
only**, sealed with the same key as the message archive.

### Why there is no server-side log

Every other messenger has one, and it is the obvious thing to build. It is also
a record of when each account's owner changed a password, linked a phone number,
added a device or verified a contact — held by the one party the rest of Privio
is designed not to trust with content. Privio does not have it and should not
grow one.

The cost is real and is written on the screen rather than left to be discovered:
**an event another of your devices saw appears there and not here.** A password
changed on a laptop is in the laptop's list.

### What is recorded

`SecurityEventKind` (`app/lib/models/security_event.dart`). Each row is a kind,
a timestamp, and at most a name the user already knows — a device they named, a
contact they have a chat with.

**No IP address, no city, no user agent, no message content.** "Signed in from
Zurich, 1.2.3.4" is the shape these logs usually take, and it is a movement
history filed under security. See `docs/metadata-privacy-review.md`.

| Event | Raised by |
| --- | --- |
| Device added / removed | `SecurityController._noticeDeviceChanges`, by diffing the server's list against what this phone last saw |
| Two-factor on / off | `SecurityController.confirmTotp` / `disableTotp` |
| Backup restored | `BackupScreen`, after a restore succeeds |
| Proxy on / off | `ProxyController.save` |
| Contact's key changed | `ConversationController._raiseKeyChanges` |
| Contact verified / verification withdrawn | `SafetyNumberScreen` |
| Screen lock changed, duress code changed | `AppState`, `SecurityController` |
| Password changed | **nothing yet** — the server route exists, the app has no screen for it |

Two of these are marked as warnings and nothing else is: a contact's key
changing, and the second factor being switched off. Marking more would make the
mark mean nothing.

### Noticing a device somebody else added

This is the only one that is detection rather than record-keeping. The server
tells every client the same device list; noticing that it *grew* is what turns
it into a warning, and that needs the previous list. `SecureStore.readKnownDevices`
holds device ids — ids only, no names, no platforms, no timestamps.

The first load after this shipped emits nothing. With nothing to compare
against, every device present would read as newly added, and a security screen
that cries wolf on its first run is read once. `security_events_test.dart` holds
that, and holds that a device is reported once rather than on every refresh.

### Storage

`EncryptedSecurityLog` seals AES-GCM with the **archive key**, and stamps the
owning account id *inside* the sealed payload. Consequences, each of them
tested:

* what sits at rest contains neither the device name nor the account id;
* a second account on the same phone reads an empty list;
* a wrong key is an empty list rather than half a history;
* with no archive key yet, the event is **dropped rather than written in the
  clear** — an unencrypted list of when this account changed its password is
  exactly what must not exist on a lost phone;
* the log is capped at 200 events, oldest first out;
* signing out, deleting the account and the duress wipe all delete it, because
  it shares the message history's lifecycle exactly.

## Privacy Dashboard

`Settings → Privacy & Security → Privacy Dashboard`

Where this account actually stands, in one screen. **Every value is read from
something**: the two-factor row is what the server last said, the device count
is the same list the Devices screen shows, the phone rows come from
`PhoneController`, routing from `ProxyController`, and the verified-contacts
count is recomputed against the keys pinned *right now* — so a contact whose key
changed drops out of it without anything having to clear a flag.

A value that has not arrived is drawn as **—**, never as "Off". A dashboard that
says "Protected" because somebody typed "Protected" into it is worse than no
dashboard: it is a reassurance with nothing behind it, on the one screen people
open when they are worried. `privacy_dashboard_test.dart` pins this; hardcoding
the two-factor row turns two of its tests red.

Two rows state architecture rather than settings — messages and calls are
end-to-end encrypted because of how Privio is built. Both carry their exception
on the row rather than in a footnote: **bot conversations are not end-to-end
encrypted**, and a call is only as good as the safety number behind it.

The note at the foot of the screen says the thing the rest of the screen could
be read as denying: content is encrypted, but the fact that a message went from
you to somebody, and when, is not. `docs/metadata-privacy-review.md` is the long
version.
