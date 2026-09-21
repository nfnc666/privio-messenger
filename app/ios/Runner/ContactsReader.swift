import Contacts
import Flutter
import Foundation

/// The address book, read once and for one purpose.
///
/// The same three rules as the Android half in `ContactsReader.kt`, and they
/// matter more here because iOS hands out the whole contact object if you ask
/// for it:
///
///  1. **Only the number key is fetched.** `CNContactPhoneNumbersKey` and
///     nothing else. Asking for a name would mean the app held names it has no
///     use for, and `CNContactFetchRequest` gives exactly what its `keysToFetch`
///     lists — so what this app can see is visible in one line rather than in
///     whatever happens to the objects afterwards.
///  2. **Access is requested at the moment the read is asked for.** There is no
///     status call. iOS shows its prompt once per install; an app that asked on
///     a settings screen would have spent that one prompt before anybody
///     pressed anything.
///  3. **Nothing is stored.** The numbers go straight back over the channel.
///     No cache, no file, no log line.
///
/// On iOS 18 and later `CNAuthorizationStatus.limited` exists: the person chose
/// specific contacts. That is a yes to exactly those, and this reads them the
/// same way it reads a full address book — the system decides what the store
/// returns, and an app that refused to work with a limited grant would be
/// arguing with a privacy choice.
final class ContactsReader: NSObject {
    static let shared = ContactsReader()

    private let store = CNContactStore()

    func attach(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "app.privio/contacts", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(nil)
                return
            }
            guard call.method == "read" else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.read(result: result)
        }
    }

    private func read(result: @escaping FlutterResult) {
        store.requestAccess(for: .contacts) { [weak self] granted, error in
            guard let self else {
                result(nil)
                return
            }
            // A refusal and a failure are told apart, because only one of them
            // should send somebody to the Settings app: `permission_denied` is
            // the code the Dart side turns into "denied", and anything else
            // reads as "this did not work".
            guard granted, error == nil else {
                DispatchQueue.main.async {
                    result(
                        FlutterError(
                            code: "permission_denied",
                            message: "Privio may not read the address book.",
                            details: nil))
                }
                return
            }
            let numbers = self.numbers()
            DispatchQueue.main.async {
                switch numbers {
                case .success(let found):
                    result(found)
                case .failure(let failure):
                    result(
                        FlutterError(
                            code: "read_failed",
                            message: failure.localizedDescription,
                            details: nil))
                }
            }
        }
    }

    /// Every phone number in the address book, de-duplicated.
    ///
    /// De-duplicated for the same reason as on Android: one number routinely
    /// appears three times — merged accounts, the same mobile filed under two
    /// labels — and every duplicate would be another blind spent against a
    /// daily budget that is deliberately small.
    private func numbers() -> Result<[String], Error> {
        var found: [String] = []
        var seen = Set<String>()
        let request = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor])
        // The sort has a cost and buys nothing here: nothing about matching
        // depends on the order, and the numbers are turned into hashes before
        // anything else looks at them.
        request.sortOrder = .none

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                for number in contact.phoneNumbers {
                    let value = number.value.stringValue.trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty, seen.insert(value).inserted {
                        found.append(value)
                    }
                }
            }
        } catch {
            return .failure(error)
        }
        return .success(found)
    }
}
