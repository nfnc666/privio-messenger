import Flutter
import UIKit
import UserNotifications

/// The iOS half of push: the permission, the APNs token, and the wake-up.
///
/// Everything here is the operating system's own — nothing is linked for it,
/// which is why the App Store build needs no third-party push SDK and the
/// payload can stay empty. What arrives is `content-available: 1` and nothing
/// else; the app fetches its envelopes over its own TLS connection and composes
/// whatever the user sees from plaintext that never left the device.
///
/// What is deliberately *not* here: PushKit and CallKit. See
/// `docs/notifications.md` — reporting an incoming call to CallKit on every
/// VoIP push is a requirement, not an option, and getting it wrong has the
/// system terminate the app. It is not something to write without a device to
/// run it on.
final class PushBridge: NSObject {
    static let shared = PushBridge()

    private var permissions: FlutterMethodChannel?
    private var push: FlutterMethodChannel?
    private var wake: FlutterMethodChannel?

    /// Held while APNs is deciding, so the token can be handed back to the Dart
    /// call that asked for it. iOS answers on a delegate callback, not a return
    /// value, so the request and the answer are two separate moments.
    private var pendingToken: FlutterResult?
    private var token: String?

    func attach(messenger: FlutterBinaryMessenger) {
        wake = FlutterMethodChannel(name: "app.privio/wake", binaryMessenger: messenger)

        let permissions = FlutterMethodChannel(
            name: "app.privio/notifications", binaryMessenger: messenger)
        permissions.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "status": self?.status(result)
            case "request": self?.request(result)
            default: result(FlutterMethodNotImplemented)
            }
        }
        self.permissions = permissions

        let push = FlutterMethodChannel(name: "app.privio/push", binaryMessenger: messenger)
        push.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "isAvailable":
                // A simulator has no APNs. Saying so beats a token that never
                // arrives and a screen that waits for it.
                #if targetEnvironment(simulator)
                    result(false)
                #else
                    result(true)
                #endif
            case "token": self?.requestToken(result)
            case "delete":
                // iOS has no "forget this token" call: unregistering is what
                // stops delivery, and Apple invalidates the token itself.
                UIApplication.shared.unregisterForRemoteNotifications()
                self?.token = nil
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
        self.push = push
    }

    // MARK: - Permission

    private func status(_ result: @escaping FlutterResult) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let answer: String
            switch settings.authorizationStatus {
            case .notDetermined: answer = "notRequested"
            case .denied: answer = "denied"
            case .authorized, .provisional, .ephemeral: answer = "granted"
            @unknown default: answer = "unsupported"
            }
            DispatchQueue.main.async { result(answer) }
        }
    }

    private func request(_ result: @escaping FlutterResult) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
                // The granted flag is ignored in favour of reading the settings
                // back: someone who was asked before gets `false` here without
                // any prompt being shown, which is not the same as a refusal
                // and must not be reported as one.
                self?.status(result)
            }
    }

    // MARK: - Token

    private func requestToken(_ result: @escaping FlutterResult) {
        if let token {
            result(token)
            return
        }
        pendingToken = result
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
    }

    func received(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        if let waiting = pendingToken {
            pendingToken = nil
            waiting(hex)
        } else {
            // A token with nobody waiting for it is a renewal. Apple reissues
            // on restore and on reinstall, and a server still holding the old
            // one pushes into the void.
            wake?.invokeMethod("tokenChanged", arguments: hex)
        }
    }

    func failedToRegister() {
        token = nil
        pendingToken?(nil)
        pendingToken = nil
    }

    /// A background push arrived. There is nothing in it to read.
    ///
    /// The completion handler reports what the fetch actually did, and is
    /// called exactly once. It used to fire `.newData` immediately, before Dart
    /// had done anything — which is not a small inaccuracy: iOS decides how
    /// generously to deliver future background pushes partly on whether the
    /// app really had work to do, and an app that always claims new data while
    /// sometimes having none gets throttled. Reporting a failure as success
    /// also hides the failure.
    ///
    /// Three things have to be true at once, and the guard below is what makes
    /// them so: exactly one call, even if the timeout and the reply race; a
    /// bounded wait, because iOS kills the process after roughly thirty
    /// seconds and a handler that never fires is the worst outcome; and an
    /// answer even when there is no Dart side listening at all.
    func woken(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        var finished = false
        let lock = NSLock()

        /// Calls back once, whoever gets here first.
        func finish(_ result: UIBackgroundFetchResult) {
            lock.lock()
            let alreadyDone = finished
            finished = true
            lock.unlock()
            guard !alreadyDone else { return }
            DispatchQueue.main.async { completion(result) }
        }

        guard let wake else {
            // No engine is listening — the app is not running its Dart side.
            // Nothing was fetched and saying so is the truth.
            finish(.noData)
            return
        }

        // Comfortably inside the system's own limit, and short enough that a
        // wedged fetch does not spend the whole budget.
        let deadline = DispatchTime.now() + .seconds(25)
        DispatchQueue.main.asyncAfter(deadline: deadline) { finish(.failed) }

        wake.invokeMethod("wake", arguments: nil) { reply in
            if reply is FlutterError {
                // The fetch threw. `.failed` rather than `.noData`, because the
                // two mean different things to the system: one is "nothing to
                // do", the other is "this did not work".
                finish(.failed)
            } else if FlutterMethodNotImplemented as AnyObject === reply as AnyObject {
                finish(.noData)
            } else if let didFetch = reply as? Bool {
                finish(didFetch ? .newData : .noData)
            } else {
                // An older Dart side that answers nothing. It did go and look,
                // so `.newData` is the closer of the two.
                finish(.newData)
            }
        }
    }
}
