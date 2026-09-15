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

  // No `label` or `description` here. Both were English sentences produced by
  // a model class, which cannot know which of the app's five languages the
  // person reading is in. The screens turn these three values into words.

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

  /// Why [value] is not acceptable — as a case, not a sentence. The screen
  /// that asked turns it into words.
  PasscodeComplaint? complaintAbout(String value) {
    if (accepts(value)) return null;
    return switch (this) {
      PasscodeKind.digits4 => PasscodeComplaint.needsFourDigits,
      PasscodeKind.digits6 => PasscodeComplaint.needsSixDigits,
      PasscodeKind.phrase => value.length < minimumPhraseLength
          ? PasscodeComplaint.phraseTooShort
          : PasscodeComplaint.phraseNeedsLetter,
    };
  }

  static bool _isDigits(String value) =>
      value.isNotEmpty && !value.contains(RegExp('[^0-9]'));
}

/// What is wrong with a passcode somebody typed.
enum PasscodeComplaint {
  needsFourDigits,
  needsSixDigits,
  phraseTooShort,
  phraseNeedsLetter,
}
