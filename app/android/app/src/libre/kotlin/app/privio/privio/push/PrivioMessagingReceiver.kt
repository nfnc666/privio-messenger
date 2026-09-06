package app.privio.privio.push

import android.content.Context
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.MessagingReceiver
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage

/**
 * Where the distributor's side of the conversation arrives.
 *
 * The message that comes in here is one byte and carries nothing: the server
 * sends `.` and the app fetches its envelopes over its own TLS connection. So
 * there is nothing to parse and nothing to show from it — the only correct
 * response is "wake up and go and look".
 */
class PrivioMessagingReceiver : MessagingReceiver() {

    override fun onNewEndpoint(context: Context, endpoint: PushEndpoint, instance: String) {
        // A temporary endpoint is the distributor's own failover and may change
        // again shortly. It is still a working address, so it is kept: being
        // woken by a stand-in beats not being woken.
        Endpoints.remember(context, endpoint.url)
        // Answers a registration that is waiting, if one is. An endpoint that
        // arrives with nobody waiting is a renewal, and the bridge forwards it
        // to Dart so the new address reaches the server.
        UnifiedPushBridge.deliver(endpoint.url)
    }

    override fun onRegistrationFailed(context: Context, reason: FailedReason, instance: String) {
        Endpoints.forget(context)
        UnifiedPushBridge.deliver(null)
    }

    override fun onUnregistered(context: Context, instance: String) {
        Endpoints.forget(context)
        UnifiedPushBridge.deliver(null)
    }

    override fun onMessage(context: Context, message: PushMessage, instance: String) {
        // Deliberately not read. The body is a single dot by design — see
        // UnifiedPushSender on the server — and anything that ever appeared in
        // it would be content that had travelled through a third party.
        PushWake.arrived(context)
    }
}

/**
 * The last endpoint the distributor gave us, across process deaths.
 *
 * Plain SharedPreferences, and framework-only: this is a public URL the server
 * already holds, not a secret, and the keystore is for things that are.
 */
internal object Endpoints {
    private const val FILE = "privio.push"
    private const val KEY = "unifiedpush.endpoint"

    private fun prefs(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun get(context: Context): String? = prefs(context).getString(KEY, null)

    fun remember(context: Context, endpoint: String) {
        prefs(context).edit().putString(KEY, endpoint).apply()
    }

    fun forget(context: Context) {
        prefs(context).edit().remove(KEY).apply()
    }
}
