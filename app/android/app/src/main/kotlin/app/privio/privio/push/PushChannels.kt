package app.privio.privio.push

import android.Manifest
import android.app.Activity
import android.os.Build
import app.privio.privio.NotificationPermissions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The channels every build has, whichever service wakes it.
 *
 * The provider-specific half lives in [PushPlatform], which exists once per
 * flavour: `libre` wires the UnifiedPush bridge and `play` wires Firebase.
 * Nothing in `main` can name either, which is what keeps the Libre APK free of
 * a Google dependency by construction rather than by discipline.
 */
object PushChannels {
    private const val WAKE_CHANNEL = "app.privio/wake"

    fun attach(activity: Activity, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger

        // The way a wake-up reaches Dart while the app is alive, and the way a
        // reissued token gets to the server. Dart listens; nothing is called
        // from Dart on it.
        PushWake.channel = MethodChannel(messenger, WAKE_CHANNEL)

        MethodChannel(messenger, NotificationPermissions.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(NotificationPermissions.status(activity))

                    "request" -> {
                        if (!NotificationPermissions.shouldPrompt(activity)) {
                            // Already answered, or a version with no runtime
                            // permission to ask for. Either way the system
                            // shows nothing, so neither do we.
                            result.success(NotificationPermissions.status(activity))
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            NotificationPermissions.pending = result
                            activity.requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                NotificationPermissions.REQUEST_CODE,
                            )
                        } else {
                            result.success(NotificationPermissions.status(activity))
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        PushPlatform.attach(activity, engine)
    }

    /** Releases the channel when the engine goes, so nothing posts into a corpse. */
    fun detach() {
        PushWake.channel = null
    }
}
