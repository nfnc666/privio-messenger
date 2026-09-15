import Flutter
import UIKit

/// The channel behind Settings → Appearance → App icon, on iOS.
///
/// iOS calls these *alternate app icons*. They are declared in the asset
/// catalog (`AppIcon-blue` and the rest, listed in
/// `ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES`), and swapped with
/// `UIApplication.setAlternateIconName`. Nothing is downloaded and nothing is
/// drawn at runtime: every variant ships in the bundle.
///
/// Two things iOS decides for itself and this does not try to work around:
///
/// * **It shows its own confirmation.** "You have changed the icon for Privio"
///   is a system alert, it cannot be suppressed, and suppressing it is not
///   something an app should want — the home screen is the user's, not ours.
/// * **It cannot change the app's name.** There is no API for it at all, which
///   is why the calculator disguise is not offered here: a calculator icon
///   still labelled Privio announces itself. A colour is not a disguise, so it
///   has no such problem and is offered.
enum LauncherIcon {
    static let channel = "app.privio/launcher"

    /// The asset-catalog set for each entry the channel speaks.
    ///
    /// `green` maps to nil on purpose: nil is how `setAlternateIconName` says
    /// "the primary icon", which is the delivered artwork. Giving the original
    /// an alternate of its own would ship the same picture twice.
    private static let icons: [String: String?] = [
        "green": nil,
        "blue": "AppIcon-blue",
        "teal": "AppIcon-teal",
        "purple": "AppIcon-purple",
        "pink": "AppIcon-pink",
        "red": "AppIcon-red",
        "orange": "AppIcon-orange",
        "yellow": "AppIcon-yellow",
    ]

    static func attach(messenger: FlutterBinaryMessenger) {
        let methods = FlutterMethodChannel(name: channel, binaryMessenger: messenger)
        methods.setMethodCallHandler { call, result in
            switch call.method {
            case "capability":
                // The icon, yes. The name, never — see the note above. The app
                // is told the truth and decides what to offer rather than
                // finding out by trying.
                result([
                    "icon": UIApplication.shared.supportsAlternateIcons,
                    "name": false,
                ])

            case "show":
                guard
                    let arguments = call.arguments as? [String: Any],
                    let entry = arguments["entry"] as? String
                else {
                    result(FlutterError(code: "unknown_entry", message: "No entry was named.", details: nil))
                    return
                }
                // The disguise is an Android-only feature, and asking for it
                // here is a bug rather than something to half-apply.
                guard let icon = icons[entry] else {
                    result(FlutterError(
                        code: "unknown_entry",
                        message: "No app icon is called \(entry).",
                        details: nil
                    ))
                    return
                }
                guard UIApplication.shared.supportsAlternateIcons else {
                    result(FlutterError(
                        code: "unsupported",
                        message: "This device cannot change the app icon.",
                        details: nil
                    ))
                    return
                }
                UIApplication.shared.setAlternateIconName(icon) { error in
                    // Back on the main queue: the completion is not guaranteed
                    // to be, and a Flutter result must be.
                    DispatchQueue.main.async {
                        if let error {
                            result(FlutterError(
                                code: "launcher_failed",
                                message: error.localizedDescription,
                                details: nil
                            ))
                        } else {
                            result(nil)
                        }
                    }
                }

            case "current":
                // Read from iOS rather than remembered, so the settings screen
                // can reconcile against what the home screen is actually
                // showing. nil means the primary icon, which is green.
                let name = UIApplication.shared.alternateIconName
                guard let name else {
                    result("green")
                    return
                }
                result(icons.first { $0.value == name }?.key)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
