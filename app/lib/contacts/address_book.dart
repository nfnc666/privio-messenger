import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What came back from asking the device for its address book.
///
/// A sealed set rather than a nullable list, because the three answers call for
/// three different things from the screen: a list to match, a sentence plus the
/// way into the system settings, or nothing at all on a platform that has no
/// address book to read.
@immutable
sealed class AddressBookRead {
  const AddressBookRead();
}

/// Numbers, exactly as the platform stored them.
///
/// Unnormalised on purpose: normalising is `PhoneNumbers.normalise`'s job and
/// it is the same code that decides what is sendable, so doing it here would be
/// a second implementation of the same rule. Everything that does not normalise
/// is dropped before anything leaves the device.
class AddressBookNumbers extends AddressBookRead {
  const AddressBookNumbers(this.numbers);

  final List<String> numbers;
}

/// The person said no, or the system had already recorded a no.
///
/// Not an error to argue with: the manual ways of adding somebody — a PRIVIO
/// ID, an invite link, a QR code — are unchanged, and the sentence that goes
/// with this says so.
class AddressBookDenied extends AddressBookRead {
  const AddressBookDenied();
}

/// This build has no address book to read: the web build, a desktop without
/// the native half, or a channel that is not there.
class AddressBookUnsupported extends AddressBookRead {
  const AddressBookUnsupported();
}

/// The device's address book, behind an interface.
///
/// An interface for the same reason the keystore and the microphone have one:
/// every answer below — including the refusal — has to be reachable in a test,
/// and none of this can be exercised on a machine with no phone attached.
abstract interface class AddressBook {
  /// Asks the operating system, then reads.
  ///
  /// **This is the only thing in the app that touches the address book, and it
  /// asks for permission at the moment it is called.** There is no
  /// status-then-read pair, deliberately: a status call that ran on a settings
  /// screen would be an app looking at whether it may read the address book
  /// before anybody asked it to, and on iOS even asking counts as the prompt.
  ///
  /// What it returns is **numbers only**. Names, emails, photos, addresses,
  /// organisations and notes are never requested from the platform, so there is
  /// nothing to drop later and nothing that could be sent by accident.
  Future<AddressBookRead> read();
}

/// What a build with no address-book integration reports.
class NoAddressBook implements AddressBook {
  const NoAddressBook();

  @override
  Future<AddressBookRead> read() async => const AddressBookUnsupported();
}

/// Asks the platform over a method channel.
///
/// A missing channel reads as [AddressBookUnsupported] rather than as a crash:
/// a build whose native half is not there is in the same position as a platform
/// that cannot do this, and the screen says the same thing either way.
class ChannelAddressBook implements AddressBook {
  const ChannelAddressBook([
    this._channel = const MethodChannel('app.privio/contacts'),
  ]);

  final MethodChannel _channel;

  @override
  Future<AddressBookRead> read() async {
    try {
      final numbers = await _channel.invokeListMethod<String>('read');
      // Null is the platform saying it read nothing, which is an empty address
      // book rather than a failure — a phone with no contacts on it is an
      // ordinary phone.
      return AddressBookNumbers(numbers ?? const []);
    } on MissingPluginException {
      return const AddressBookUnsupported();
    } on PlatformException catch (error) {
      // The one code the native halves raise on purpose. Anything else is a
      // platform that could not answer, which is not the same as a refusal and
      // must not be reported as one — a refusal sends somebody to the settings
      // app for a switch that is already on.
      return error.code == 'permission_denied'
          ? const AddressBookDenied()
          : const AddressBookUnsupported();
    }
  }
}
