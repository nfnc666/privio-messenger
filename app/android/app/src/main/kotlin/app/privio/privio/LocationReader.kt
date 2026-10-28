package app.privio.privio

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Where the phone is, once, for a place somebody chose to share.
 *
 * The same rules as `ContactsReader` beside it, for the same reasons:
 *
 *  1. **The permission is requested when the place is asked for**, which is
 *     the moment somebody picked "Location" in a chat. There is no status
 *     call and nothing at start.
 *  2. **One position, while the app is in use.** No background permission, no
 *     stream, no live location: one fix, handed back, and the listener gone.
 *  3. **Nothing is stored.** The two numbers go straight back over the channel.
 *
 * Built on the framework's `LocationManager` rather than Google's fused
 * provider, because the Libre build carries no Google Play services. The
 * price is that a phone without a network location provider waits for GPS.
 */
object LocationReader {
    const val CHANNEL = "app.privio/location"

    /** The request code this activity uses for the location prompt. */
    const val REQUEST_CODE = 4713

    /** How long a fix may take before the answer is "not right now". */
    private const val TIMEOUT_MS = 30_000L

    /**
     * Held while the system dialog is up, so the answer goes back to the Dart
     * call that asked.
     */
    private var pending: MethodChannel.Result? = null

    fun attach(activity: Activity, channel: MethodChannel) {
        channel.setMethodCallHandler { call, result -> handle(activity, call, result) }
    }

    private fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "current") {
            result.notImplemented()
            return
        }
        if (granted(activity)) {
            measure(activity, result)
            return
        }
        // One prompt at a time, or the first Dart future would hang for ever.
        if (pending != null) {
            result.error("busy", "A location prompt is already open.", null)
            return
        }
        pending = result
        activity.requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            REQUEST_CODE,
        )
    }

    /**
     * Hands the system's answer back. Called from
     * `MainActivity.onRequestPermissionsResult`.
     *
     * Approximate is a yes: Android 12 and later let people grant only that,
     * and a place to within a few hundred metres is still the place they chose
     * to share.
     */
    fun permissionResult(activity: Activity, grantResults: IntArray) {
        val waiting = pending ?: return
        pending = null
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            measure(activity, waiting)
        } else {
            waiting.error("permission_denied", "Privio may not use the location.", null)
        }
    }

    private fun granted(activity: Activity): Boolean =
        fine(activity) ||
            activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun fine(activity: Activity): Boolean =
        activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    // Checked in `granted` before anything here runs, and GPS only with the
    // precise permission, which it needs.
    @SuppressLint("MissingPermission")
    private fun measure(activity: Activity, result: MethodChannel.Result) {
        val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val provider = listOfNotNull(
            if (fine(activity)) LocationManager.GPS_PROVIDER else null,
            LocationManager.NETWORK_PROVIDER,
        ).firstOrNull { manager.isProviderEnabled(it) }
        if (provider == null) {
            result.error("unavailable", "Location is switched off.", null)
            return
        }

        val main = Handler(Looper.getMainLooper())
        var answered = false
        fun answer(location: Location?) {
            if (answered) return
            answered = true
            main.removeCallbacksAndMessages(null)
            if (location == null) {
                result.error("unavailable", "No position came in time.", null)
            } else {
                result.success(
                    mapOf(
                        "latitude" to location.latitude,
                        "longitude" to location.longitude,
                        "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
                    ),
                )
            }
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val cancel = CancellationSignal()
                main.postDelayed({
                    cancel.cancel()
                    answer(null)
                }, TIMEOUT_MS)
                manager.getCurrentLocation(provider, cancel, activity.mainExecutor) { answer(it) }
            } else {
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) = answer(location)

                    @Deprecated("Abstract before Android 11, so it has to be here.")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

                    override fun onProviderEnabled(provider: String) {}

                    override fun onProviderDisabled(provider: String) {}
                }
                main.postDelayed({
                    manager.removeUpdates(listener)
                    answer(null)
                }, TIMEOUT_MS)
                @Suppress("DEPRECATION")
                manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            }
        } catch (error: Exception) {
            // A provider that went away between the check and the request, or
            // a permission withdrawn in the same moment. Not a refusal to
            // report as one: the Dart side reads this as "not right now".
            if (!answered) {
                answered = true
                main.removeCallbacksAndMessages(null)
                result.error("unavailable", error.message ?: "No position.", null)
            }
        }
    }
}
