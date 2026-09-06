package app.privio.privio.push

import android.content.Context
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Play build's way of being woken. This file exists only in the `play`
 * source set, and the Firebase dependency only in `playImplementation`, so
 * there is no arrangement of build flags under which it reaches the Libre APK.
 *
 * A phone with no Play services is a normal thing, not an error: many are sold
 * that way and some people remove it. The bridge answers "no token" and the
 * app says plainly that it can only be reached while it is open.
 */
object FcmBridge {
    const val CHANNEL = "app.privio/push"

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(available(context))

            "token" -> {
                if (!available(context)) {
                    result.success(null)
                    return
                }
                FirebaseMessaging.getInstance().token
                    .addOnSuccessListener { result.success(it) }
                    // Firebase with no `google-services.json` behind it fails
                    // here rather than at build time. "No token" is the honest
                    // answer and the app already knows how to say it.
                    .addOnFailureListener { result.success(null) }
            }

            "delete" -> {
                if (!available(context)) {
                    result.success(null)
                    return
                }
                FirebaseMessaging.getInstance().deleteToken()
                    .addOnCompleteListener { result.success(null) }
            }

            else -> result.notImplemented()
        }
    }

    private fun available(context: Context): Boolean =
        GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) ==
            ConnectionResult.SUCCESS
}

/**
 * Receives the wake-up.
 *
 * The payload is data-only and its single field says `wake` or `call` — see
 * `FcmSender` on the server. Google composes nothing, because there is no
 * `notification` block for it to compose from, and there never can be: the
 * text would be somebody's message passing through Google's servers.
 */
class PrivioFirebaseService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        // The value is not read for content — it has none. It only says
        // whether this can wait for a battery window, which the sender already
        // encoded in the message priority.
        PushWake.arrived(applicationContext)
    }

    override fun onNewToken(token: String) {
        // FCM reissues on reinstall, on a restore to a new phone, and on its
        // own schedule. A server left holding the old one pushes into the void.
        PushWake.tokenChanged(token)
    }
}
