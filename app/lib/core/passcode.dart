/// What shape the app-lock passcode has on this device.
///
/// Three, because they are three different trade-offs and not one setting with
/// a number attached: a four-digit code is what people will actually use, six
/// digits is the same idea with a hundred times the guesses, and a passphrase
/// is for someone who wants the lock to hold up against somebody who has the
/// phone and time.
enum PasscodeKind {
  digits4,
  digits6,
  phrase;

  static PasscodeKind? parse(String? id) => switch (id) {
        'digits4' => PasscodeKind.digits4,
        'digits6' => PasscodeKind.digits6,
        'phrase' => PasscodeKind.phrase,
        _ => null,
      };

  String get id => name;

  /// True for the two that are typed on a keypad, which is what decides whether
  /// the lock screen draws digits or a text field.
  bool get isNumeric => this != PasscodeKind.phrase;

  /// Fixed for the digit kinds, so the lock screen can submit on the last one
  /// without a confirm button. Null for a phrase, which ends when the person
  /// says it does.
  int? get length => switch (this) {
        PasscodeKind.digits4 => 4,
        PasscodeKind.digits6 => 6,
        PasscodeKind.phrase => null,
      };

  String get label => switch (this) {
        PasscodeKind.digits4 => '4 digits',
        PasscodeKind.digits6 => '6 digits',
        PasscodeKind.phrase => 'Passphrase',
      };

  String get description => switch (this) {
        PasscodeKind.digits4 => 'Ten thousand combinations. Quick, and enough against '
            'someone who picks the phone up.',
        PasscodeKind.digits6 => 'A million combinations, and still a keypad.',
        PasscodeKind.phrase => 'Letters, and digits or symbols if you want them. The only '
            'one of the three that stands up to someone with the phone and time.',
      };

  /// The shortest phrase worth calling one. Below this it is a four-digit code
  /// with extra steps.
  static const int minimumPhraseLength = 6;

  /// Whether [value] can be this kind of passcode. Nothing is normalised: a
  /// passcode is compared as it was typed.
  bool accepts(String value) => switch (this) {
        PasscodeKind.digits4 => _isDigits(value) && value.length == 4,
        PasscodeKind.digits6 => _isDigits(value) && value.length == 6,
        // A phrase has to contain a letter, or "123456" would pass as one and
        // the choice would mean nothing.
        PasscodeKind.phrase =>
          value.length >= minimumPhraseLength && value.contains(RegExp('[A-Za-z]')),
      };

  /// Why [value] is not acceptable, in words the person can act on.
  String? complaintAbout(String value) {
    if (accepts(value)) return null;
    return switch (this) {
      PasscodeKind.digits4 => 'Four digits.',
      PasscodeKind.digits6 => 'Six digits.',
      PasscodeKind.phrase => value.length < minimumPhraseLength
          ? 'At least $minimumPhraseLength characters.'
          : 'A passphrase needs at least one letter. Digits and symbols are '
              'welcome alongside it.',
    };
  }

  static bool _isDigits(String value) =>
      value.isNotEmpty && !value.contains(RegExp('[^0-9]'));
}
