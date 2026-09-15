import '../core/passcode.dart';
import 'app_localizations.dart';

/// Words for the three shapes of app lock, and for what is wrong with one.
///
/// They live here rather than on [PasscodeKind] because a model class cannot
/// know which of the app's five languages the person reading it is in.
String passcodeKindLabel(AppText text, PasscodeKind kind) => switch (kind) {
      PasscodeKind.digits4 => text.passcodeFourDigits,
      PasscodeKind.digits6 => text.passcodeSixDigits,
      PasscodeKind.phrase => text.pinPassphrase,
    };

String passcodeKindNote(AppText text, PasscodeKind kind) => switch (kind) {
      PasscodeKind.digits4 => text.passcodeFourDigitsNote,
      PasscodeKind.digits6 => text.passcodeSixDigitsNote,
      PasscodeKind.phrase => text.passcodePhraseNote,
    };

String passcodeComplaintText(AppText text, PasscodeComplaint complaint) =>
    switch (complaint) {
      PasscodeComplaint.needsFourDigits => text.passcodeNeedsFourDigits,
      PasscodeComplaint.needsSixDigits => text.passcodeNeedsSixDigits,
      PasscodeComplaint.phraseTooShort =>
        text.passcodePhraseTooShort(PasscodeKind.minimumPhraseLength),
      PasscodeComplaint.phraseNeedsLetter => text.passcodePhraseNeedsLetter,
    };
