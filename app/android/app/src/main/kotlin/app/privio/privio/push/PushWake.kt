package app.privio.privio.push

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import app.privio.privio.R
import io.flutter.plugin.common.MethodChannel

/**
 * What happens when a wake-up arrives, whichever service carried it.
 *
 * The push itself says nothing — that is the whole design — so there are only
 * two honest things to do with one: tell the running app to go and fetch, and,
 * when there is no running app, put something neutral on the screen so the
 * person knows to open Privio.
 *
 * "Neutral" is not a placeholder for something better. Any text a notification
 * could otherwise show would have to come from a decrypted message, and the
 * only place that plaintext exists is inside the app after it has fetched. A
 * notification composed before that point cannot say who wrote or what they
 * said; one composed after it would be putting a private conversation on a
 * lock screen that anyone holding the phone can read.
 */
object PushWake {
    private const val CHANNEL_ID = "privio.messages"
    private const val NOTIFICATION_ID = 1

    /** Set while a Flutter engine is alive and listening. */
    var channel: MethodChannel? = null

    private val main = Handler(Looper.getMainLooper())

    fun arrived(context: Context) {
        val live = channel
        if (live != null) {
            // The app is running: it fetches, decrypts, and decides for itself
            // what — if anything — to show.
            main.post { live.invokeMethod("wake", null) }
            return
        }
        notifyNeutrally(context)
    }

    /** Tells Dart that the push service issued a new address for this device. */
    fun tokenChanged(token: String) {
        val live = channel ?: return
        main.post { live.invokeMethod("tokenChanged", token) }
    }

    private fun notifyNeutrally(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.notification_channel_messages),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )

        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val intent = open?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            // No name, no count, no preview. There is nothing here that could
            // be one: this code has never seen a plaintext and cannot.
            .setContentTitle(context.getString(R.string.notification_title))
            .setContentText(context.getString(R.string.notification_body))
            .setAutoCancel(true)
            .apply { if (intent != null) setContentIntent(intent) }
            .build()

        manager.notify(NOTIFICATION_ID, notification)
    }
}
