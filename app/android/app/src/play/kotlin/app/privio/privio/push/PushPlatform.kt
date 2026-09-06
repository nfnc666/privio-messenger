package app.privio.privio.push

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** The Play build: Firebase, which only this flavour is allowed to contain. */
object PushPlatform {
    fun attach(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, FcmBridge.CHANNEL)
            .setMethodCallHandler { call, result ->
                FcmBridge.handle(activity.applicationContext, call, result)
            }
    }
}
