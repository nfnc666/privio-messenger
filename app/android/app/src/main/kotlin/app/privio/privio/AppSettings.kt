package app.privio.privio

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings

/**
 * The way into this app's own settings page.
 *
 * Every runtime permission Privio asks for — notifications, the camera, the
 * photo picker on the versions that still gate it — can be refused once and
 * then only changed here: Android shows its dialog a limited number of times
 * and after that the request is a no-op. An app that cannot point at this page
 * leaves the user with an explanation and nowhere to act on it.
 *
 * Returns whether the page actually opened, so Dart can say "open settings
 * yourself" rather than claiming to have done something it did not.
 */
object AppSettings {
    fun open(context: Context): Boolean {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            // A device with no settings app for this — rare, but it is a
            // "false" rather than a crash in the middle of a refusal the user
            // is already unhappy about.
            false
        }
    }
}
