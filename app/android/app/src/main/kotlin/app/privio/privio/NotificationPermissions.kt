package app.privio.privio

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/**
 * What Android says about Privio being allowed to show a notification.
 *
 * Three states rather than two, because "never asked" and "asked and refused"
 * are different situations for the app: the first can still be prompted, and
 * the second cannot — from Android 13 the system shows its dialog once, and
 * after that only the settings app can change the answer.
 *
 * Deliberately built on the framework rather than androidx: the Libre build
 * is audited for what it links, and this needs nothing that is not already in
 * the platform.
 */
object NotificationPermissions {
    const val CHANNEL = "app.privio/notifications"

    /** The request code this activity uses for the notification prompt. */
    const val REQUEST_CODE = 4711

    /**
     * Held while the system dialog is up, so the answer can be handed back to
     * the same Dart call that asked for it.
     */
    var pending: MethodChannel.Result? = null

    fun status(context: Context): String {
        // Below Android 13 there is no runtime permission at all: notifications
        // are on unless the user turned them off in settings, which is what
        // areNotificationsEnabled reports.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return if (enabled(context)) "granted" else "denied"
        }
        val granted = context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return if (enabled(context)) "granted" else "denied"
        return "notRequested"
    }

    /**
     * Whether notifications are switched on for this app.
     *
     * Separate from the permission and worth checking as well: someone can hold
     * the permission and still have turned Privio's notifications off in
     * settings, and to the user those are the same thing — nothing appears.
     */
    private fun enabled(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        return manager.areNotificationsEnabled()
    }

    fun shouldPrompt(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && status(context) == "notRequested"
}
