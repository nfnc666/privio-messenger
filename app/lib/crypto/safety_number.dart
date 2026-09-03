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
      _generator
          .createFor(
            version,
            Uint8List.fromList(utf8.encode(localAccountId)),
            localIdentity,
            Uint8List.fromList(utf8.encode(remoteAccountId)),
            remoteIdentity,
          )
          .displayableFingerprint
          .getDisplayText();
}
