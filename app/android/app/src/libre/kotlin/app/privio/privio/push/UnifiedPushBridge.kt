package app.privio.privio.push

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.unifiedpush.android.connector.UnifiedPush

/**
 * The Libre and direct builds' way of being woken: a distributor the user
 * installed, and no Google library anywhere in the APK.
 *
 * The shape of this is dictated by the connector, and it is not the shape the
 * Dart interface suggests. `UnifiedPush.register` does not return an endpoint;
 * it starts a conversation with the distributor, and the endpoint arrives later
 * as a broadcast at [PrivioMessagingReceiver]. So the pending Dart result is
 * held here until that callback fires — or until the timeout does, because a
 * distributor that never answers must not leave the settings screen spinning
 * forever.
 *
 * Written against `org.unifiedpush.android:connector:3.3.5`, whose sources say
 * `register`/`unregister`; the library's `main` branch is mid-rename from
 * `registerApp`/`unregisterApp` and code written from it will not compile here.
 */
object UnifiedPushBridge {
    const val CHANNEL = "app.privio/unifiedpush"

    /** How long a distributor gets to answer before this gives up on it. */
    private const val REGISTER_TIMEOUT_MS = 20_000L

    private var pending: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())
    private val giveUp = Runnable { deliver(null) }

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // "Is there anything to register with." Not whether we are already
            // registered — the screen asks this to decide whether offering the
            // option would mean anything on this phone.
            "isAvailable" -> result.success(UnifiedPush.getDistributors(context).isNotEmpty())

            "register" -> register(context, result)

            "unregister" -> {
                UnifiedPush.unregister(context)
                UnifiedPush.removeDistributor(context)
                Endpoints.forget(context)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun register(context: Context, result: MethodChannel.Result) {
        // Already registered and the distributor has acknowledged it: hand back
        // what we have rather than starting the dance again.
        val known = Endpoints.get(context)
        if (known != null && UnifiedPush.getAckDistributor(context) != null) {
            result.success(known)
            return
        }

        // Only one registration can be in flight, because only one result can
        // be held. A second call while the first is waiting is answered with
        // the same "nothing yet" the timeout would give.
        if (pending != null) {
            result.success(null)
            return
        }
        pending = result

        // Picks the saved distributor, or the system default, or shows the
        // chooser. False means there was nothing to pick and no dialog to show.
        UnifiedPush.tryUseCurrentOrDefaultDistributor(context) { picked ->
            if (!picked) {
                deliver(null)
                return@tryUseCurrentOrDefaultDistributor
            }
            UnifiedPush.register(
                context,
                messageForDistributor = "Privio",
            )
            main.postDelayed(giveUp, REGISTER_TIMEOUT_MS)
        }
    }

    /**
     * Called by the receiver when the distributor answers, and by the timeout.
     *
     * An endpoint with nobody waiting for it is a renewal — distributors
     * reissue, and a server still holding the old address posts into the void —
     * so it is forwarded to Dart instead of being dropped.
     */
    fun deliver(endpoint: String?) {
        main.removeCallbacks(giveUp)
        val waiting = pending
        if (waiting == null) {
            if (endpoint != null) PushWake.tokenChanged(endpoint)
            return
        }
        pending = null
        main.post { waiting.success(endpoint) }
    }
}
