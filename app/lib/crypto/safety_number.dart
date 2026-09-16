import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// The number two people read to each other to check that nobody is in the
/// middle.
///
/// End-to-end encryption only means something once both sides know they hold
/// the right keys. The server hands out those keys, so a server that wanted to
/// read a conversation would hand each side its own key instead of the other
/// person's. Nothing in the protocol catches that. Comparing this number over
/// a channel the server does not control — a phone call, a room — is what
/// catches it.
///
/// The digits are Signal's construction, computed by
/// [NumericFingerprintGenerator] from `libsignal_protocol_dart`: 5200 rounds of
/// SHA-512 over each side's identity key and account id, folded down to thirty
/// digits per side and concatenated in a fixed order so both people see the
/// same sixty. Privio implements none of it.
@immutable
class SafetyNumber {
  const SafetyNumber({
    required this.deviceIndex,
    required this.digits,
    required this.identityKey,
    this.fingerprint,
  });

  /// Which of the peer's devices this number covers. See the note on
  /// [SafetyNumbers] for why there is one per device rather than one per
  /// person.
  final int deviceIndex;

  /// Sixty digits, unformatted.
  final String digits;

  /// The peer identity key these digits were computed from, base64. Held so
  /// that marking the number verified records *what* was verified.
  final String identityKey;

  /// The same fingerprint in the form a QR code carries.
  ///
  /// Signal's `ScannableFingerprint`, produced by the same generator as
  /// [digits] from the same two identity keys. **Privio invents no format
  /// here.** Encoding one would mean a QR that only Privio can read and a
  /// comparison only Privio has ever checked, on the one screen where being
  /// wrong is indistinguishable from being attacked.
  ///
  /// Null on a number built without it — a test, or an older stored value. A
  /// null one shows no QR rather than showing a broken one.
  final ScannableFingerprint? fingerprint;

  /// What the QR code carries: the fingerprint protobuf, base64.
  ///
  /// Base64 rather than raw bytes because a QR code carries text and every
  /// reader on every platform agrees about how to give text back.
  String? get scannable {
    final print = fingerprint;
    return print == null ? null : base64Encode(print.fingerprints);
  }

  /// Whether [scanned] is this same fingerprint, seen from the other side.
  ///
  /// **The comparison is the library's, it is two-sided, and it happens here on
  /// the device.** Their local half must equal my remote half *and* their
  /// remote half must equal my local half, which is what makes a QR replayed
  /// from a third person's conversation fail rather than pass. Nothing is asked
  /// of the server, and nothing about the scan leaves the phone.
  ///
  /// False for anything that will not parse, is the wrong version, or is not
  /// base64 at all: a photograph of the wrong thing is a mismatch, not an
  /// error, and on this screen a mismatch must never read as a match.
  bool matchesScan(String scanned) {
    final print = fingerprint;
    if (print == null) return false;
    try {
      return print.compareTo(base64Decode(scanned.trim()));
    } on Object {
      return false;
    }
  }

  /// Twelve groups of five, which is how they are read aloud.
  String get formatted {
    final groups = <String>[];
    for (var i = 0; i < digits.length; i += 5) {
      groups.add(digits.substring(i, i + 5 > digits.length ? digits.length : i + 5));
    }
    return groups.join(' ');
  }

  /// True when [other] is the same number, however it was spaced or pasted.
  bool matches(String other) {
    final stripped = other.replaceAll(RegExp(r'[^0-9]'), '');
    return stripped.length == digits.length && stripped == digits;
  }

  // [fingerprint] is deliberately out of both: it is derived from exactly the
  // three fields below, so including an object with no value equality of its
  // own would make two equal numbers compare unequal.
  @override
  bool operator ==(Object other) =>
      other is SafetyNumber &&
      other.deviceIndex == deviceIndex &&
      other.digits == digits &&
      other.identityKey == identityKey;

  @override
  int get hashCode => Object.hash(deviceIndex, digits, identityKey);
}

/// Where a conversation stands against the number the user last checked.
enum VerificationState {
  /// Never compared. The keys are pinned, but nobody has checked them against
  /// the person they belong to.
  unverified,

  /// Compared, and everything still matches what was compared.
  verified,

  /// Compared once, and no longer matching: a key changed, or the peer's set
  /// of devices did. Either is worth showing, because either is what a server
  /// inserting itself would look like.
  changed,
}

/// Every number for one conversation, and what the user has made of them.
///
/// **One number per device, not one per person.** Signal can show a single
/// number because an identity key there belongs to an account. In Privio each
/// device has its own identity key and is trusted separately, so a single
/// number would be a summary of several trust decisions — and would go stale
/// for reasons the user could not act on. What is pinned is per device, so
/// what is shown is per device.
@immutable
class SafetyNumbers {
  const SafetyNumbers({required this.numbers, required this.state});

  final List<SafetyNumber> numbers;
  final VerificationState state;

  bool get isEmpty => numbers.isEmpty;

  /// What marking this conversation verified would record.
  Map<String, String> get snapshot => {
        for (final number in numbers) '${number.deviceIndex}': number.identityKey,
      };
}

/// Computes the digits. Split out from the store so it can be tested against
/// known keys without any storage at all.
abstract final class SafetyNumberDigits {
  /// The iteration count is part of the number, not a tuning knob: two clients
  /// that disagree about it produce different digits for the same keys.
  static const int iterations = 5200;
  static const int version = 1;

  static final NumericFingerprintGenerator _generator =
      NumericFingerprintGenerator(iterations);

  static String between({
    required String localAccountId,
    required IdentityKey localIdentity,
    required String remoteAccountId,
    required IdentityKey remoteIdentity,
  }) =>
      compute(
        localAccountId: localAccountId,
        localIdentity: localIdentity,
        remoteAccountId: remoteAccountId,
        remoteIdentity: remoteIdentity,
      ).displayableFingerprint.getDisplayText();

  /// The whole fingerprint — the digits people read aloud and the bytes a QR
  /// code carries — from one computation.
  ///
  /// One call rather than two because they must describe the same pair of keys:
  /// digits from one generator run and a QR from another would be a screen
  /// where reading the number aloud and scanning the code could disagree, and
  /// nobody would know which to believe.
  static Fingerprint compute({
    required String localAccountId,
    required IdentityKey localIdentity,
    required String remoteAccountId,
    required IdentityKey remoteIdentity,
  }) =>
      _generator.createFor(
        version,
        Uint8List.fromList(utf8.encode(localAccountId)),
        localIdentity,
        Uint8List.fromList(utf8.encode(remoteAccountId)),
        remoteIdentity,
      );
}
