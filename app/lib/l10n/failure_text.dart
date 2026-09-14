import '../core/failure.dart';
import '../services/wake_up.dart';
import 'app_localizations.dart';

/// Says a [Failure] in the language the reader has chosen.
///
/// The one case that is not translated is [FailureKind.serverSaid]: the server
/// answered with a sentence this app did not write, and it arrives in English.
/// Everything the app can name itself is named, so that case is the exception
/// and not the rule — see `docs/localisation.md`.
extension FailureText on Failure {
  String words(AppText text) => switch (kind) {
        FailureKind.unreachable => text.failureUnreachable,
        FailureKind.unreachableCheckConnection => text.failureUnreachableCheckConnection,
        FailureKind.unreachableTryAgain => text.failureUnreachableTryAgain,
        FailureKind.couldNotSave => text.failureCouldNotSave,
        FailureKind.changeNotSaved => text.failureChangeNotSaved,
        FailureKind.rateLimited => text.failureRateLimited,
        FailureKind.tooManyAttempts => text.failureTooManyAttempts,
        FailureKind.licenseRequired => text.failureLicenseRequired,
        FailureKind.identityChanged => text.failureIdentityChanged,
        FailureKind.couldNotSendMessage => text.failureCouldNotSendMessage,
        FailureKind.couldNotSendFile => text.failureCouldNotSendFile,
        FailureKind.couldNotReadMessage => text.failureCouldNotReadMessage,
        FailureKind.messagesUnreadable => text.failureMessagesUnreadable(count ?? 1),
        FailureKind.couldNotOpenFile => text.failureCouldNotOpenFile,
        FailureKind.notAnImage => text.failureNotAnImage,
        FailureKind.couldNotSetPicture => text.failureCouldNotSetPicture,
        FailureKind.deletedHereOnly => text.failureDeletedHereOnly,
        FailureKind.couldNotCreateGroup => text.failureCouldNotCreateGroup,
        FailureKind.notAGroupLink => text.failureNotAGroupLink,
        FailureKind.groupNotFound => text.failureGroupNotFound,
        FailureKind.groupKeyMissing => text.failureGroupKeyMissing,
        FailureKind.notAChannelLink => text.failureNotAChannelLink,
        FailureKind.handleTaken => text.failureHandleTaken,
        FailureKind.channelNotFound => text.failureChannelNotFound,
        FailureKind.notAMember => text.failureNotAMember,
        FailureKind.insufficientPermission => text.failureInsufficientPermission,
        FailureKind.cannotChangeOwnRole => text.failureCannotChangeOwnRole,
        FailureKind.ownerIsFixed => text.failureOwnerIsFixed,
        FailureKind.targetOutranksYou => text.failureTargetOutranksYou,
        FailureKind.cannotGrantWhatYouLack => text.failureCannotGrantWhatYouLack,
        FailureKind.ownerCannotLeave => text.failureOwnerCannotLeave,
        FailureKind.channelKeyAwaitingGeneration => text.failureChannelKeyAwaitingGeneration,
        FailureKind.channelKeyPending => text.failureChannelKeyPending,
        FailureKind.usernameTaken => text.failureUsernameTaken,
        FailureKind.invalidCredentials => text.failureInvalidCredentials,
        FailureKind.totpRequired => text.failureTotpRequired,
        FailureKind.invalidTwoFactorCode => text.failureInvalidTwoFactorCode,
        FailureKind.tooManyDevices => text.failureTooManyDevices,
        FailureKind.checkUsernameAndPassword =>
          text.failureCheckUsernameAndPassword(detail ?? ''),
        FailureKind.invalidTotp => text.failureInvalidTotp,
        FailureKind.totpAlreadyEnabled => text.failureTotpAlreadyEnabled,
        FailureKind.totpNotSetUp => text.failureTotpNotSetUp,
        FailureKind.invalidPassword => text.failureInvalidPassword,
        FailureKind.duressMatchesPassword => text.failureDuressMatchesPassword,
        FailureKind.deviceNotFound => text.failureDeviceNotFound,
        FailureKind.couldNotLiftBlock => text.failureCouldNotLiftBlock,
        FailureKind.licenseKeyIncomplete => text.failureLicenseKeyIncomplete(detail ?? ''),
        FailureKind.notALicenseKey => text.failureNotALicenseKey,
        FailureKind.licenseNotFound => text.failureLicenseNotFound,
        FailureKind.licenseAlreadyRedeemed => text.failureLicenseAlreadyRedeemed,
        FailureKind.licenseRevoked => text.failureLicenseRevoked,
        FailureKind.accountAlreadyLicensed => text.failureAccountAlreadyLicensed,
        FailureKind.noPlayServices => text.failureNoPlayServices,
        FailureKind.noApnsToken => text.failureNoApnsToken,
        FailureKind.noPushService => text.failureNoPushService,
        FailureKind.noDistributor => text.failureNoDistributor,
        FailureKind.distributorUnreachable => text.failureDistributorUnreachable,
        FailureKind.callDevicesUnavailable => text.failureCallDevicesUnavailable,
        FailureKind.callMicrophoneUnavailable => text.failureCallMicrophoneUnavailable,
        FailureKind.callNotOpen => text.failureCallNotOpen,
        FailureKind.unexpected => text.failureUnexpected,
        FailureKind.serverSaid => detail ?? text.failureUnreachable,
      };
}

/// The words for a notification warning, in the reader's language.
String notificationWarningWords(AppText text, NotificationWarning warning) =>
    switch (warning) {
      NotificationWarning.turnedOff => text.notificationsPermissionDenied,
      NotificationWarning.notAskedYet => text.notificationsPermissionNotAsked,
    };
