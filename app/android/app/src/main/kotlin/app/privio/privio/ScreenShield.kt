package app.privio.privio

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.MethodChannel

/**
 * Android's side of the screen protection: `FLAG_SECURE`, and nothing else.
 *
 * The flag is a property of a **window**, and Flutter draws the entire app —
 * every route, every dialog, every bottom sheet, every image viewer — into the
 * single window belonging to [MainActivity]. Setting it there therefore covers
 * all of them at once, which is why there is no per-screen opt-in anywhere in
 * the Dart tree and no list of "sensitive screens" to keep up to date. A list
 * like that is a list somebody forgets to add to.
 *
 * What the flag does, per the platform documentation:
 *
 *  - the screenshot key combination produces a toast instead of an image;
 *  - a `MediaProjection` recording — the system recorder, and every third-party
 *    recorder, which all go through the same API — captures a black frame;
 *  - the window is left out of the recent-apps thumbnail;
 *  - the window is not mirrored to a non-secure external display.
 *
 * What it does not do is covered in `docs/screen-protection.md`: it cannot stop
 * a second phone being pointed at the screen, it does not travel to anybody
 * else's device, and a rooted or instrumented device can do as it likes.
 *
 * Some manufacturer builds are known to honour it incompletely. That is a
 * device limitation and it is written down rather than worked around, because
 * the alternative — a private API, or a trick — would be a promise this app
 * cannot keep.
 */
object ScreenShield {
    const val CHANNEL = "app.privio/screen-shield"

    fun attach(activity: Activity, messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Android blocks outright, so there is never a capture in
                // progress for the app to be told about. Answering `false` to
                // `detectsCapture` is what stops the Dart side putting a cover
                // over a screen nobody is recording.
                "capability" -> result.success(
                    mapOf("blocksCapture" to true, "detectsCapture" to false),
                )

                "setProtected" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    // Window flags must be touched on the UI thread. A channel
                    // call already arrives on it, but `runOnUiThread` costs
                    // nothing and makes that independent of how the engine is
                    // configured.
                    activity.runOnUiThread {
                        try {
                            if (on) {
                                activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                // Cleared, not merely "not added". A flag left
                                // set after the switch goes off is the failure
                                // this branch exists to prevent: the user is
                                // told the protection is off while the system
                                // is still refusing their screenshots.
                                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "flag_failed",
                                error.message ?: "The window flag could not be changed.",
                                null,
                            )
                        }
                    }
                }

                // Never true here: `FLAG_SECURE` means a recorder gets black
                // frames rather than that the app learns it is running. Android
                // offers no public way to be told, and inventing one would mean
                // guessing.
                "isCaptured" -> result.success(false)

                else -> result.notImplemented()
            }
        }
    }

    /** Whether the flag is currently set, for the activity to restore it. */
    fun isProtected(activity: Activity): Boolean =
        (activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
}
