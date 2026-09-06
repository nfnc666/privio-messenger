package app.privio.privio.push

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** The Libre and direct builds: a distributor, and nothing proprietary. */
object PushPlatform {
    fun attach(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, UnifiedPushBridge.CHANNEL)
            .setMethodCallHandler { call, result ->
                UnifiedPushBridge.handle(activity.applicationContext, call, result)
            }
    }
}
