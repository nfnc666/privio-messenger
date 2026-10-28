import CoreLocation
import Flutter
import Foundation

/// Where the phone is, once, for a place somebody chose to share.
///
/// The same rules as the Android half in `LocationReader.kt`:
///
///  1. **Permission is asked for when the place is asked for**, which is the
///     moment somebody picked "Location" in a chat. iOS shows its prompt once
///     per install, and an app that asked at start would have spent it before
///     anybody wanted anything.
///  2. **When in use, one position.** `requestWhenInUseAuthorization` and
///     `requestLocation`: no "always", no updates, no live location.
///  3. **Nothing is stored.** The two numbers go straight back over the channel.
final class LocationReader: NSObject, CLLocationManagerDelegate {
    static let shared = LocationReader()

    /// How long a fix may take before the answer is "not right now".
    private static let timeout: TimeInterval = 30

    private let manager = CLLocationManager()
    private var pending: FlutterResult?
    private var measuring = false
    private var deadline: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func attach(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "app.privio/location", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(nil)
                return
            }
            guard call.method == "current" else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.current(result: result)
        }
    }

    private func current(result: @escaping FlutterResult) {
        // One request at a time, or the first Dart future would hang for ever.
        guard pending == nil else {
            result(
                FlutterError(
                    code: "busy", message: "A location request is already running.", details: nil))
            return
        }
        pending = result
        switch manager.authorizationStatus {
        case .notDetermined:
            // The answer arrives in `locationManagerDidChangeAuthorization`.
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            measure()
        default:
            finish(Self.denied)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Also called when the manager is created, with nobody waiting.
        guard pending != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            return
        case .authorizedWhenInUse, .authorizedAlways:
            measure()
        default:
            finish(Self.denied)
        }
    }

    private func measure() {
        guard !measuring else { return }
        measuring = true
        let work = DispatchWorkItem { [weak self] in
            self?.finish(
                FlutterError(code: "unavailable", message: "No position came in time.", details: nil))
        }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: work)
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let accuracy: Any = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : NSNull()
        finish([
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": accuracy,
        ])
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A refusal and a failure are told apart, because only one of them
        // should send somebody to the Settings app.
        if (error as? CLError)?.code == .denied {
            finish(Self.denied)
        } else {
            finish(
                FlutterError(code: "unavailable", message: error.localizedDescription, details: nil))
        }
    }

    private static let denied = FlutterError(
        code: "permission_denied", message: "Privio may not use the location.", details: nil)

    private func finish(_ value: Any?) {
        deadline?.cancel()
        deadline = nil
        measuring = false
        guard let result = pending else { return }
        pending = nil
        result(value)
    }
}
