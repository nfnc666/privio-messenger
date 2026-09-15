import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Why something did not work, as a case rather than a sentence.
///
/// A controller or service cannot write the sentence, because it does not know
/// which language the person reading it has chosen — and on a shared device the
/// answer changes with the account. So it names the case and the screen says
/// the words, through `lib/l10n/failure_text.dart`.
enum FailureKind {
  // Reaching the server.
  unreachable,
  unreachableCheckConnection,
  unreachableTryAgain,
  couldNotSave,
  changeNotSaved,

  /// A profile status the server did not take. Says its own sentence rather
  /// than borrowing the generic one, because it has something specific and
  /// reassuring to add: the draft is still in the field.
  statusNotSaved,
  rateLimited,
  tooManyAttempts,

  // Sending, reading, attachments, pictures.
  licenseRequired,
  identityChanged,
  couldNotSendMessage,
  couldNotSendFile,
  couldNotReadMessage,

  /// How many messages could not be read. Carries [Failure.count].
  messagesUnreadable,
  couldNotOpenFile,
  notAnImage,
  couldNotSetPicture,
  deletedHereOnly,

  // Groups.
  couldNotCreateGroup,
  notAGroupLink,
  groupNotFound,
  groupKeyMissing,

  // Channels.
  notAChannelLink,
  handleTaken,
  channelNotFound,
  notAMember,
  insufficientPermission,
  cannotChangeOwnRole,
  ownerIsFixed,
  targetOutranksYou,
  cannotGrantWhatYouLack,
  ownerCannotLeave,

  /// The channel key is being replaced after a removal, and nobody has made
  /// the new one yet.
  channelKeyAwaitingGeneration,

  /// The new channel key exists but has not reached this device.
  channelKeyPending,

  // Signing in and registering.
  usernameTaken,
  invalidCredentials,
  totpRequired,
  invalidTwoFactorCode,
  tooManyDevices,

  /// The server rejected the form and said why. Carries [Failure.detail].
  checkUsernameAndPassword,

  // Security settings.
  invalidTotp,
  totpAlreadyEnabled,
  totpNotSetUp,
  invalidPassword,
  duressMatchesPassword,
  deviceNotFound,
  couldNotLiftBlock,

  // Licences.
  ///
  /// Carries [Failure.detail]: the shape a key has, which is not translated.
  licenseKeyIncomplete,
  notALicenseKey,
  licenseNotFound,
  licenseAlreadyRedeemed,
  licenseRevoked,
  accountAlreadyLicensed,

  // Being woken while closed.
  noPlayServices,
  noApnsToken,
  noPushService,
  noDistributor,
  distributorUnreachable,

  // Calls.
  proxyCallsBlocked,
  callDevicesUnavailable,
  callMicrophoneUnavailable,
  callNotOpen,

  // A call refused on security grounds. None of these falls back to anything:
  // the call ends, and the person is told which check failed.
  callMediaNotEncrypted,
  callFarEndNotBound,
  callCertificateChanged,

  /// Carries [Failure.detail]: who, by username.
  callIdentityChanged,
  callWrongParty,

  /// Strict mode. Carries [Failure.detail]: who, by username.
  callNotVerified,

  // An optional phone number, and finding contacts by one.
  //
  // The number is never an identity here: none of these is a sign-in failure,
  // and none of them blocks anything. The worst any of them does is leave an
  // account without a number, which is a state the whole app supports.
  phoneInvalid,
  phoneSmsUnavailable,
  phoneDiscoveryUnavailable,
  phoneWrongCode,
  phoneCodeExpired,
  phoneTooManyAttempts,
  phoneTooManySends,
  phoneResendTooSoon,
  phoneNoVerification,
  phoneUnchanged,
  phoneNotLinked,
  phoneLookupBudgetSpent,

  /// The operating system refused the address book. Not an error to argue
  /// with — the manual ways of adding somebody still work, and the sentence
  /// says so.
  contactsPermissionDenied,

  // Stickers and custom emoji.
  //
  // The server refuses an upload by code; these are the codes this app has its
  // own words for. It checks the bytes rather than trusting what the client
  // says they are, so any of them can arrive even from a build that pre-checked.
  stickerNotAnImage,
  stickerAnimated,
  stickerTooLarge,
  stickerTooWide,
  stickerTooSmall,
  stickerPackFull,
  stickerTooManyPacks,
  stickerPackNotFound,

  /// A share link that opens nothing: revoked, or the pack deleted.
  stickerLinkDead,

  // The home-screen icon.
  appIconUnsupported,
  appIconHiddenByDisguise,

  /// A state the app did not expect. Honest rather than blamed on the network.
  unexpected,

  /// The server explained it in words this app did not write, in
  /// [Failure.detail]. Shown as it arrived — see the note in `failure_text.dart`.
  serverSaid,
}

/// A [FailureKind] plus whatever the sentence needs to be said.
@immutable
class Failure {
  const Failure(this.kind, {this.detail, this.count});

  /// Wording that came down from the server, kept verbatim.
  const Failure.server(String message)
      : kind = FailureKind.serverSaid,
        detail = message,
        count = null;

  /// Anything thrown, as a failure: a server sentence when the server sent one,
  /// and [otherwise] for everything else (a socket that never answered, a
  /// decode that failed).
  factory Failure.of(Object error, FailureKind otherwise) =>
      error is ApiException ? Failure.server(error.message) : Failure(otherwise);

  final FailureKind kind;

  /// Server wording, or a value the sentence needs. Never a translated string.
  final String? detail;

  /// How many, where the sentence counts something.
  final int? count;

  @override
  bool operator ==(Object other) =>
      other is Failure && other.kind == kind && other.detail == detail && other.count == count;

  @override
  int get hashCode => Object.hash(kind, detail, count);

  @override
  String toString() => 'Failure($kind, detail: $detail, count: $count)';
}
