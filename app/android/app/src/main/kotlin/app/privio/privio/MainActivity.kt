package app.privio.privio

import android.content.ComponentName
import android.content.pm.PackageManager
import app.privio.privio.push.PushChannels
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The one real activity, plus the channel that decides which launcher entry
 * points at it.
 *
 * Android draws the launcher from `activity-alias` entries, so swapping the
 * icon and the name is a matter of enabling one and disabling the other. The
 * app itself does not change: both aliases target this activity.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PushChannels.attach(this, flutterEngine)
        // The window flag that blocks screenshots and recordings. Attached to
        // this activity because the flag belongs to its window, which is the
        // one window Flutter draws the whole app into.
        ScreenShield.attach(this, flutterEngine.dartExecutor.binaryMessenger)
        // The address book. Nothing here reads anything until Dart calls it,
        // and Dart only calls it when somebody presses the button that matches
        // contacts — see `ContactsReader`.
        ContactsReader.attach(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ContactsReader.CHANNEL),
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Android can change both. iOS answers differently, and the
                    // app is told rather than assuming.
                    // Android changes both, on the launcher entry. The name in
                    // Settings > Apps comes from the application label and is
                    // fixed at build time; the app says so rather than claiming
                    // the disguise is complete.
                    "capability" -> result.success(mapOf("icon" to true, "name" to true))
                    "show" -> {
                        val entry = call.argument<String>("entry")
                        val alias = ALIASES[entry]
                        if (alias == null) {
                            result.error(
                                "unknown_entry",
                                "No launcher entry is called ${'$'}entry.",
                                null,
                            )
                        } else {
                            try {
                                applyLauncher(alias)
                                result.success(null)
                            } catch (error: Exception) {
                                result.error(
                                    "launcher_failed",
                                    error.message ?: "The launcher entry could not be changed.",
                                    null,
                                )
                            }
                        }
                    }
                    "current" -> result.success(currentEntry())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Enables the wanted alias before disabling every other one.
     *
     * The order matters and is not cosmetic: with no launcher alias enabled,
     * even for an instant, some launchers drop the app from the home screen and
     * Android may stop the process. Enabling first means there is never a
     * moment with nothing to launch — and disabling *all* the others after
     * means there is never a moment with two, which is how a duplicate entry
     * gets left behind on the home screen.
     *
     * DONT_KILL_APP keeps the running process alive through the change. The
     * launcher itself may still take a few seconds to redraw its grid, which is
     * the launcher's own caching and not something an app can hurry.
     */
    private fun applyLauncher(wanted: String) {
        setAlias(wanted, enabled = true)
        for (alias in ALIASES.values) {
            if (alias != wanted) setAlias(alias, enabled = false)
        }

        // Read it back. Some manufacturer builds accept the call and change
        // nothing, and an icon that quietly did not move is worse than one that
        // reports it could not: the whole point of the setting is that someone
        // is about to rely on what their home screen shows.
        if (!isEnabled(wanted)) {
            throw IllegalStateException("Android did not apply the launcher change.")
        }
    }

    /**
     * Which entry the launcher is showing, by the name the channel speaks.
     *
     * Read from the package manager rather than remembered, so the app can
     * reconcile what it stored against what is actually on the home screen.
     *
     * An alias that has never been touched reports DEFAULT rather than
     * ENABLED/DISABLED — that is its manifest value, which for the green entry
     * means enabled and for every other means not. A fresh install therefore
     * answers "green" here without anything having had to write it.
     */
    private fun currentEntry(): String? {
        for ((entry, alias) in ALIASES) {
            val setting = packageManager.getComponentEnabledSetting(
                ComponentName(packageName, alias),
            )
            val on = when (setting) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> alias == DEFAULT_ALIAS
                else -> false
            }
            if (on) return entry
        }
        return null
    }

    private fun setAlias(alias: String, enabled: Boolean) {
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        packageManager.setComponentEnabledSetting(
            ComponentName(packageName, alias),
            state,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun isEnabled(alias: String): Boolean {
        val setting = packageManager.getComponentEnabledSetting(ComponentName(packageName, alias))
        return setting == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
    }

    /**
     * Hands the system's answer back to the Dart call that asked for it.
     *
     * Android shows the notification prompt once. A refusal here is final
     * until someone changes it in settings, which is why the app explains
     * rather than asking again.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == ContactsReader.REQUEST_CODE) {
            ContactsReader.permissionResult(this, grantResults)
            return
        }
        if (requestCode != NotificationPermissions.REQUEST_CODE) return
        val waiting = NotificationPermissions.pending ?: return
        NotificationPermissions.pending = null
        waiting.success(NotificationPermissions.status(this))
    }

    override fun onDestroy() {
        PushChannels.detach()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "app.privio/launcher"
        const val DEFAULT_ALIAS = "app.privio.privio.DefaultLauncher"
        const val CALCULATOR_ALIAS = "app.privio.privio.CalculatorLauncher"

        /**
         * Every launcher entry, by the name the channel speaks.
         *
         * "green" is the default alias rather than an alias of its own: the
         * delivered artwork is what the app ships with, and giving it a second
         * component would mean a fresh install had two entries that both
         * claimed to be the original.
         */
        val ALIASES = linkedMapOf(
            "green" to DEFAULT_ALIAS,
            "calculator" to CALCULATOR_ALIAS,
            "blue" to "app.privio.privio.LauncherBlue",
            "teal" to "app.privio.privio.LauncherTeal",
            "purple" to "app.privio.privio.LauncherPurple",
            "pink" to "app.privio.privio.LauncherPink",
            "red" to "app.privio.privio.LauncherRed",
            "orange" to "app.privio.privio.LauncherOrange",
            "yellow" to "app.privio.privio.LauncherYellow",
        )
    }
}
