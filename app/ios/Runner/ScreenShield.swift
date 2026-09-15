import Flutter
import UIKit

/// iOS's side of the screen protection, which is **detection, not prevention**.
///
/// There is no `FLAG_SECURE` on iOS and no public API that stops a screenshot.
/// `UIScreen.isCaptured` is what Apple offers, and what it reports is that the
/// screen's contents are *being captured right now* — screen recording, an
/// active ReplayKit broadcast, AirPlay mirroring, or a QuickTime capture over a
/// cable. It has been public since iOS 11 and is the documented way to do this.
///
/// So the honest shape of this feature on iOS is: while a capture is running,
/// cover what is on screen; when it stops, uncover. The recording still exists
/// and still plays back — it simply shows Privio's own cover for as long as the
/// protection was on.
///
/// What is deliberately **not** here:
///
///  - Any private API. There is no supported one that blocks capture, and an
///    unsupported one is a rejected build and a broken promise.
///  - The `UITextField.isSecureTextEntry` trick — putting the whole app inside
///    a secure text field's layer so the compositor drops it from screenshots.
///    It works today on some iOS versions, relies on an implementation detail
///    Apple has changed before and documents nowhere, and breaks touch handling
///    and accessibility. A protection that silently stops working after an iOS
///    update is worse than one the app was honest about.
///  - Any claim to block screenshots. `userDidTakeScreenshotNotification` fires
///    *after* the image exists; it could power a notice, but a notice is not a
///    block and this app does not present it as one.
final class ScreenShield: NSObject {
    static let shared = ScreenShield()

    private var channel: FlutterMethodChannel?

    /// Whether the account asked for protection. The capture notification is
    /// observed only while it did — an app that watched regardless would be
    /// spending battery on an answer nobody had asked for.
    private var watching = false

    func attach(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "app.privio/screen-shield", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(nil)
                return
            }
            switch call.method {
            case "capability":
                // The two halves said separately, because they are separately
                // true: iOS cannot block, and it can detect. A single "yes"
                // here is how an app ends up telling somebody their screenshots
                // are blocked when they are not.
                result(["blocksCapture": false, "detectsCapture": true])

            case "setProtected":
                let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
                self.setWatching(on)
                result(nil)

            case "isCaptured":
                result(self.isCaptured())

            default:
                result(FlutterMethodNotImplemented)
            }
        }
        self.channel = channel
    }

    // MARK: - Capture state

    /// The screen this app is actually on.
    ///
    /// `UIScreen.main` is deprecated from iOS 16 and is the wrong answer on a
    /// device driving an external display: what matters is the screen carrying
    /// Privio's window, because that is the one whose contents are at risk.
    /// The fallback is only for a scene-less moment during launch.
    private var activeScreen: UIScreen? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen
    }

    private func isCaptured() -> Bool {
        activeScreen?.isCaptured ?? false
    }

    private func setWatching(_ on: Bool) {
        guard on != watching else { return }
        watching = on
        if on {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(capturedDidChange),
                name: UIScreen.capturedDidChangeNotification,
                object: nil,
            )
            // Reported once immediately: a recording that was already running
            // when the switch went on must not wait for the next change before
            // the app covers itself.
            report()
        } else {
            NotificationCenter.default.removeObserver(
                self, name: UIScreen.capturedDidChangeNotification, object: nil)
            // Told explicitly that nothing is being captured any more, so a
            // cover cannot be left up by a switch going off mid-recording.
            channel?.invokeMethod("capturedChanged", arguments: false)
        }
    }

    @objc private func capturedDidChange() {
        report()
    }

    private func report() {
        // The notification arrives on the main thread already, but `report` is
        // also called straight from a channel handler, and `invokeMethod` has
        // to be on the platform thread.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.channel?.invokeMethod("capturedChanged", arguments: self.isCaptured())
        }
    }
}
