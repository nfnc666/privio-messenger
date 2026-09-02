import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Where the app's launcher entry is decided, as far as iOS allows it.
  ///
  /// iOS can swap the icon and cannot change the name: an app's display name
  /// is fixed at build time and there is no public API for it. The channel
  /// reports that honestly rather than letting the app promise a rename it
  /// cannot perform. Changing the icon also shows a system alert that no app
  /// can suppress without private API, which is worth knowing before turning
  /// a disguise on.
  private static let channelName = "app.privio/launcher"
  private static let calculatorIcon = "AppIconCalculator"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerLauncherChannel(with: engineBridge.binaryMessenger)
  }

  private func registerLauncherChannel(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: AppDelegate.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "capability":
        result([
          "icon": UIApplication.shared.supportsAlternateIcons,
          "name": false,
        ])
      case "apply":
        let arguments = call.arguments as? [String: Any]
        let disguised = (arguments?["skin"] as? String) != nil
        guard UIApplication.shared.supportsAlternateIcons else {
          result(FlutterError(
            code: "unsupported",
            message: "This device cannot change the app icon.",
            details: nil
          ))
          return
        }
        // nil restores the icon the app was built with.
        let wanted: String? = disguised ? AppDelegate.calculatorIcon : nil
        UIApplication.shared.setAlternateIconName(wanted) { error in
          if let error = error {
            result(FlutterError(
              code: "launcher_failed",
              message: error.localizedDescription,
              details: nil
            ))
          } else {
            result(nil)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
