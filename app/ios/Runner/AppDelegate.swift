import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // `applicationRegistrar.messenger()`, not `applicationBinaryMessenger` —
    // the bridge has no such property, and this file had never been compiled
    // to say so. `FlutterImplicitEngineBridge` vends a
    // `FlutterApplicationRegistrar`, and the messenger comes off that:
    // `FlutterEngine.h` and `FlutterPlugin.h` in the engine's own headers.
    PushBridge.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
  }

  // MARK: - APNs

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    PushBridge.shared.received(deviceToken: deviceToken)
    super.application(
      application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // A device with no network at launch, or a build with no push entitlement.
    // Neither is fatal: the app keeps working on its own connection and says so.
    PushBridge.shared.failedToRegister()
    super.application(
      application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  /// A wake-up. The payload is `content-available: 1` and nothing else — see
  /// `ApnsSender` on the server — so there is nothing here to read and the only
  /// correct response is to go and fetch.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    PushBridge.shared.woken(completion: completionHandler)
  }
}
