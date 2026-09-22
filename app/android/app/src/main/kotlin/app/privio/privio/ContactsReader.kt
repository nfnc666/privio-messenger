package app.privio.privio

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.provider.ContactsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The address book, read once and for one purpose.
 *
 * Three things about this are deliberate and none of them is an optimisation:
 *
 *  1. **Only the number column is projected.** `Phone.NUMBER` and nothing
 *     else — no display name, no photo, no email, no organisation. The app
 *     cannot leak a name it never asked the content provider for, and a
 *     reviewer can see that from the projection rather than having to trust
 *     what happens to the cursor afterwards.
 *  2. **The permission is requested here, when the read is asked for.** There
 *     is no status call: an app that checks whether it may read the address
 *     book before anybody asked it to is an app looking at something it was
 *     not invited to look at. Dart calls `read`, the system prompt appears,
 *     and the answer decides.
 *  3. **Nothing is stored.** The numbers go straight back over the channel and
 *     the cursor is closed. There is no cache, no file and no log line — see
 *     `docs/phone-contacts.md` for what happens to them after that, which is
 *     that they are blinded on the device and never sent in the clear.
 *
 * Built on the framework rather than androidx, like `NotificationPermissions`
 * next to it: the Libre build is audited for what it links.
 */
object ContactsReader {
    const val CHANNEL = "app.privio/contacts"

    /** The request code this activity uses for the contacts prompt. */
    const val REQUEST_CODE = 4712

    /**
     * Held while the system dialog is up, so the answer can be handed back to
     * the same Dart call that asked for it.
     */
    private var pending: MethodChannel.Result? = null

    fun attach(activity: Activity, channel: MethodChannel) {
        channel.setMethodCallHandler { call, result -> handle(activity, call, result) }
    }

    private fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "read") {
            result.notImplemented()
            return
        }

        if (granted(activity)) {
            answer(activity, result)
            return
        }

        // One prompt at a time. A second call while the dialog is up would
        // leave the first Dart future hanging for ever, which on this screen
        // looks like a button that did nothing.
        if (pending != null) {
            result.error("busy", "A contacts prompt is already open.", null)
            return
        }
        pending = result
        activity.requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), REQUEST_CODE)
    }

    /**
     * Hands the system's answer back to the Dart call that asked for it.
     *
     * Called from `MainActivity.onRequestPermissionsResult`. A refusal is
     * reported as `permission_denied`, which is the one code the Dart side
     * turns into "denied" rather than "this platform cannot do it" — the two
     * need different sentences, and only one of them should send somebody to
     * the settings app.
     */
    fun permissionResult(activity: Activity, grantResults: IntArray) {
        val waiting = pending ?: return
        pending = null
        val allowed = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (allowed) {
            answer(activity, waiting)
        } else {
            waiting.error("permission_denied", "Privio may not read the address book.", null)
        }
    }

    private fun granted(activity: Activity): Boolean =
        activity.checkSelfPermission(Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED

    private fun answer(activity: Activity, result: MethodChannel.Result) {
        try {
            result.success(numbers(activity))
        } catch (error: Exception) {
            // A provider that refused, or a device whose contacts database is
            // in a state this query cannot read. Not a refusal: the Dart side
            // reports it as "this did not work" rather than sending somebody to
            // a permission screen that is already correct.
            result.error("read_failed", error.message ?: "The address book could not be read.", null)
        }
    }

    /**
     * Every phone number on the device, de-duplicated.
     *
     * De-duplicated here because an address book routinely holds one number
     * three times — a contact merged from two accounts, the same mobile under
     * "work" and "mobile" — and every duplicate would otherwise be a blind more
     * to send against a daily budget that is deliberately small.
     */
    private fun numbers(activity: Activity): List<String> {
        val found = LinkedHashSet<String>()
        val cursor = activity.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
            null,
            null,
            null,
        ) ?: return emptyList()

        cursor.use {
            val column = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            if (column < 0) return emptyList()
            while (it.moveToNext()) {
                val number = it.getString(column) ?: continue
                if (number.isNotBlank()) found.add(number)
            }
        }
        return found.toList()
    }
}
