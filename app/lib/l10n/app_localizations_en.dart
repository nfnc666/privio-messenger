// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppTextEn extends AppText {
  AppTextEn([String locale = 'en']) : super(locale);

  @override
  String get languageName => 'Language';

  @override
  String get languagePickerTitle => 'Language';

  @override
  String get languagePickerNote =>
      'The interface changes straight away. Messages, channel names and anything else people wrote stay in the language they were written in.';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get commonSkip => 'Skip';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonOk => 'Alright';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopied => 'Copied.';

  @override
  String get commonShare => 'Share';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonSomethingWentWrong => 'Something went wrong.';

  @override
  String get commonNotNow => 'Not now';

  @override
  String get commonOn => 'On';

  @override
  String get commonOff => 'Off';

  @override
  String get commonDefault => 'Default';

  @override
  String get commonCustom => 'Custom';

  @override
  String get commonUnavailable => 'Unavailable';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get disappearingTitle => 'Disappearing messages';

  @override
  String get disappearingExplainer =>
      'New messages are deleted automatically after this long. The timer starts when the message is sent.';

  @override
  String get disappearingCoversChat =>
      'It covers text, photos, files and voice messages, and applies to this chat only. Messages already sent are not affected, and both of you are told when it changes.';

  @override
  String get disappearingCoversGroup =>
      'It covers text, photos, files and voice messages, and applies to this group only. Messages already sent are not affected, everyone is told when it changes, and only an admin can change it.';

  @override
  String get disappearingScreenshotCaveat =>
      'It cannot undo a screenshot, a photo already saved, or anything written down elsewhere.';

  @override
  String get disappearingOff => 'Off';

  @override
  String get disappearing30Seconds => '30 seconds';

  @override
  String get disappearing1Minute => '1 minute';

  @override
  String get disappearing5Minutes => '5 minutes';

  @override
  String get disappearing1Hour => '1 hour';

  @override
  String get disappearing24Hours => '24 hours';

  @override
  String get disappearing7Days => '7 days';

  @override
  String get disappearingAdminOnly => 'Only an admin can change this';

  @override
  String noticeTimerSetBy(String who, String duration) {
    return '$who set disappearing messages to $duration';
  }

  @override
  String noticeTimerOffBy(String who) {
    return '$who turned disappearing messages off';
  }

  @override
  String get noticeYou => 'You';

  @override
  String get noticeThey => 'They';

  @override
  String get noticeSomeone => 'Someone';

  @override
  String noticeMessageDeletedBy(String who) {
    return '$who deleted a message';
  }

  @override
  String noticeSafetyNumberChanged(String who) {
    return 'Your safety number with $who changed';
  }

  @override
  String noticeUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: 'A message',
    );
    return '$_temp0 could not be read. It was sealed to a key this device no longer has.';
  }

  @override
  String noticeUnreadableFrom(int count, String who) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: 'A message',
    );
    return '$_temp0 from $who could not be read. It was sealed to a key this device no longer has.';
  }

  @override
  String durationSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String durationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String durationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String durationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String durationWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks',
      one: '1 week',
    );
    return '$_temp0';
  }

  @override
  String channelSubscribers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subscribers',
      one: '1 subscriber',
    );
    return '$_temp0';
  }

  @override
  String channelMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get channelPublic => 'Public';

  @override
  String get channelPrivate => 'Private';

  @override
  String get channelAdministrators => 'Administrators';

  @override
  String get channelSubscribersRow => 'Subscribers';

  @override
  String get channelSettings => 'Channel settings';

  @override
  String get channelShareLink => 'Share link';

  @override
  String get channelDescription => 'Description';

  @override
  String get channelMedia => 'Media';

  @override
  String get channelLinks => 'Links';

  @override
  String get channelNoMedia => 'No pictures yet';

  @override
  String get channelNoLinks => 'No links yet';

  @override
  String get channelNoPosts => 'No posts yet';

  @override
  String get channelActionLivestream => 'livestream';

  @override
  String get channelActionMute => 'mute';

  @override
  String get channelActionUnmute => 'unmute';

  @override
  String get channelActionSearch => 'search';

  @override
  String get channelActionMore => 'more';

  @override
  String get channelMuteTitle => 'Mute this channel';

  @override
  String get channelMuteNote =>
      'It stays muted on every device you are signed in on — muting it here is not \"until I pick up my laptop\".';

  @override
  String get channelMuteForHour => 'For 1 hour';

  @override
  String get channelMuteForEightHours => 'For 8 hours';

  @override
  String get channelMuteForTwoDays => 'For 2 days';

  @override
  String get channelMuteUntilOff => 'Until I turn it back on';

  @override
  String get channelCopyLink => 'Copy link';

  @override
  String get channelQrCode => 'QR code';

  @override
  String get channelInviteSettings => 'Invite settings';

  @override
  String get channelStatistics => 'Statistics';

  @override
  String get channelReport => 'Report channel';

  @override
  String get channelLeave => 'Leave channel';

  @override
  String get channelLeaveTitle => 'Leave this channel?';

  @override
  String get channelLeaveBody =>
      'You stop receiving its posts. The channel moves to a new key, so nothing published after this is readable to you.';

  @override
  String get channelStay => 'Stay';

  @override
  String get channelNoLinkToShare => 'This channel has no link to share.';

  @override
  String get channelInfo => 'Channel info';

  @override
  String get adminsTitle => 'Admins';

  @override
  String get adminsSectionHeader => 'CHANNEL ADMINISTRATORS';

  @override
  String get adminsAdd => 'Add admin';

  @override
  String get adminsSearch => 'Search admins';

  @override
  String get adminsRoleOwner => 'Owner';

  @override
  String get adminsRoleAdmin => 'Admin';

  @override
  String adminsPromotedBy(String who) {
    return 'promoted by $who';
  }

  @override
  String get adminsHelpOwner => 'Administrators help you run your channel.';

  @override
  String get adminsHelpMember =>
      'Administrators help run this channel. Only somebody who may appoint admins can change this list.';

  @override
  String get adminsNobodyYet => 'Nobody yet.';

  @override
  String get adminsShowSenderName => 'Show sender name';

  @override
  String get adminsShowSenderNameOn =>
      'New posts carry the name of whoever wrote them';

  @override
  String get adminsShowSenderNameLocked =>
      'Only an admin who may edit the channel can change this';

  @override
  String get adminsShowSenderNameNote =>
      'With it off, everything the channel publishes is published by the channel — no admin name is attached, and readers see one voice.';

  @override
  String get adminsTransfer => 'Transfer ownership';

  @override
  String get adminsTransferNote =>
      'Asks for your password, and cannot be undone';

  @override
  String get adminsEverybodyAlready =>
      'Everybody in this channel is already an admin.';

  @override
  String get adminsWhoShouldBe => 'Who should be an admin?';

  @override
  String get adminsDismiss => 'Dismiss as admin';

  @override
  String get adminsAppoint => 'Appoint';

  @override
  String get adminsOwnerFixed =>
      'The owner holds every permission, and that is not editable — not here and not on the server.';

  @override
  String get adminsOutranksYou =>
      'They hold permissions you do not, so you cannot change what they may do.';

  @override
  String get adminsOnlyWhatYouHold =>
      'You can only hand out what you hold yourself. Anything you do not have is off and cannot be switched on.';

  @override
  String get adminsYouDoNotHold => 'You do not hold this yourself';

  @override
  String get adminsCouldNotChange => 'Could not change that.';

  @override
  String get permissionEditChannel => 'Edit the channel';

  @override
  String get permissionEditChannelDetail =>
      'Name, picture, description and settings';

  @override
  String get permissionPost => 'Publish posts';

  @override
  String get permissionPostDetail => 'And edit or schedule their own';

  @override
  String get permissionDeletePosts => 'Delete posts';

  @override
  String get permissionDeletePostsDetail => 'Including other people\'s';

  @override
  String get permissionModerate => 'Moderate the discussion';

  @override
  String get permissionModerateDetail => 'Remove comments and silence people';

  @override
  String get permissionManageMembers => 'Manage subscribers';

  @override
  String get permissionManageMembersDetail => 'Add, remove and silence';

  @override
  String get permissionManageInvites => 'Manage invites';

  @override
  String get permissionManageInvitesDetail =>
      'The link, its limits, and who is waiting';

  @override
  String get permissionManageLivestreams => 'Manage livestreams';

  @override
  String get permissionManageLivestreamsDetail => 'Start and end them';

  @override
  String get permissionAppointAdmins => 'Appoint admins';

  @override
  String get permissionAppointAdminsDetail =>
      'Hand this authority to somebody else';

  @override
  String get subscribersTitle => 'Subscribers';

  @override
  String get subscribersAdd => 'Add subscribers';

  @override
  String get subscribersSearch => 'Search subscribers';

  @override
  String get subscribersAdminsOnlyNote =>
      'Only channel administrators see this list.';

  @override
  String get subscribersPartialNote =>
      'This is not the whole list. Only channel administrators can see who is subscribed — what you see here is the people running it, and you.';

  @override
  String get subscribersCompleteNote => 'Everybody in this channel.';

  @override
  String get subscribersContactsSection => 'CONTACTS IN THIS CHANNEL';

  @override
  String get subscribersOthersSection => 'OTHER SUBSCRIBERS';

  @override
  String get subscribersOnlySection => 'SUBSCRIBERS';

  @override
  String get subscribersNobodyFound => 'Nobody found.';

  @override
  String get subscribersNoContacts => 'No contacts to add yet.';

  @override
  String get subscribersEverybodyHere =>
      'Everybody in your contacts is already here.';

  @override
  String get subscribersAddedOne => 'Added.';

  @override
  String subscribersAddedMany(int count) {
    return 'Added $count people.';
  }

  @override
  String get subscribersNobodyAdded => 'Nobody could be added';

  @override
  String subscribersAddedCount(int count) {
    return 'Added $count';
  }

  @override
  String subscribersNeedInvite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people have',
      one: '1 person has',
    );
    return '$_temp0 set their account so only their own contacts can add them to things. Send them the link instead and let them decide.';
  }

  @override
  String get subscribersCopyTheLink => 'Copy the link';

  @override
  String get subscribersOwnerCannotBeRemoved => 'The owner cannot be removed.';

  @override
  String get subscribersSilenced => 'Silenced';

  @override
  String get subscribersSilence => 'Silence them';

  @override
  String get subscribersSilenceDetail =>
      'They stay subscribed and stop being able to comment';

  @override
  String get subscribersUnsilence => 'Let them speak again';

  @override
  String get subscribersUnsilenceDetail => 'They can comment again';

  @override
  String get subscribersRemoveFromChannel => 'Remove from the channel';

  @override
  String get subscribersRemoveDetail =>
      'The channel moves to a new key, so they cannot read what comes next';

  @override
  String get subscribersCouldNotDoThat => 'Could not do that.';

  @override
  String get presenceOnline => 'online';

  @override
  String presenceMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return 'last seen $_temp0 ago';
  }

  @override
  String presenceHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return 'last seen $_temp0 ago';
  }

  @override
  String presenceDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return 'last seen $_temp0 ago';
  }

  @override
  String presenceOnDate(String date) {
    return 'last seen $date';
  }

  @override
  String get editChannelName => 'Channel name';

  @override
  String get editChannelDescriptionHint => 'Description';

  @override
  String get editChannelChangePicture => 'Change picture';

  @override
  String get editChannelChoosePicture => 'Choose a picture';

  @override
  String get editChannelRemovePicture => 'Remove it';

  @override
  String get editChannelPrivateNameNote =>
      'This channel is private, so its name is encrypted with the channel key. Renaming it re-seals that for every member.';

  @override
  String get editChannelType => 'Channel type';

  @override
  String get editChannelDiscussion => 'Discussion';

  @override
  String get editChannelReactions => 'Reactions';

  @override
  String editChannelReactionsValue(int count) {
    return '$count emoji';
  }

  @override
  String get editChannelWelcome => 'Welcome message';

  @override
  String get editChannelAppearance => 'Appearance';

  @override
  String get editChannelAutoTranslate => 'Auto-translation';

  @override
  String get editChannelDirectMessages => 'Direct messages';

  @override
  String get editChannelNeedsName => 'A channel needs a name.';

  @override
  String get editChannelDiscardTitle => 'Discard your changes?';

  @override
  String get editChannelDiscardBody => 'Nothing here has been saved yet.';

  @override
  String get editChannelKeepEditing => 'Keep editing';

  @override
  String get editChannelDiscard => 'Discard';

  @override
  String get editChannelCouldNotSave => 'Could not save those changes.';

  @override
  String get editChannelCouldNotUsePicture => 'Could not use that picture.';

  @override
  String get editChannelPublicPictureTitle => 'This picture will be public';

  @override
  String get editChannelPublicPictureBody =>
      'A public channel\'s picture is shown on its web page and in link previews, so it is stored unencrypted — the same as its name, handle and description. Posts stay end-to-end encrypted.';

  @override
  String get editChannelUseIt => 'Use it';

  @override
  String get editChannelSignatureNote =>
      'Signed posts show the name of whoever wrote them. With it off, everything the channel publishes is published by the channel.';

  @override
  String get livestreamNotSetUpTitle => 'Livestreams are not set up';

  @override
  String get livestreamNotSetUpBody =>
      'A livestream needs a media server: one person sends video and everybody else receives it, which cannot be done device to device the way a call is.\n\nThis Privio server has none configured, so there is nothing to join yet. Whoever runs it can set one up.';

  @override
  String get livestreamYouAreLive => 'You are live';

  @override
  String get livestreamRunning => 'A stream is running';

  @override
  String get livestreamPublisherBody =>
      'The room is open and your device has a token to publish to it. Privio does not carry the video itself yet — the media server does — so nothing is being sent from this screen.\n\nEnd it when you are done.';

  @override
  String get livestreamViewerBody =>
      'A stream is running and this device has a token to watch it. Privio cannot show the video yet.';

  @override
  String get livestreamEndIt => 'End it';

  @override
  String get livestreamNobodyStreaming => 'Nobody is streaming right now.';

  @override
  String get livestreamCouldNotStart => 'Could not start the stream.';

  @override
  String get translationNotSetUpTitle => 'Auto-translation is not set up';

  @override
  String get translationNotSetUpBody =>
      'Translating a post means sending what it says to a translation service. Privio\'s server cannot do that — it holds ciphertext and no key — so it would have to happen on your device, and the text would leave it in the clear.\n\nThat is a decision for whoever runs this server to enable and for each reader to agree to, so it is off until both have happened. No post has been sent anywhere.';

  @override
  String get visibilityPublicTitle => 'This channel is public';

  @override
  String get visibilityPrivateTitle => 'This channel is private';

  @override
  String visibilityPublicBody(String handle) {
    return 'Anyone can find it by name and read its posts. Its handle is @$handle.\n\nPrivio cannot turn a public channel private after the fact: its name and description have been readable, and unsaying that is not something an app can do.';
  }

  @override
  String get visibilityPrivateBody =>
      'It is not listed, not searchable, and reachable only through its invite link. Its name is encrypted with the channel key.\n\nMaking it public would publish that name, which is a decision Privio does not make on your behalf — create a public channel instead.';

  @override
  String get discussionBody =>
      'With this on, every post gets a thread underneath it. Comments are sealed with the same channel key as the post, so a device that cannot read the post cannot read the thread.\n\nTurning it off later hides the threads rather than deleting them.';

  @override
  String get discussionTurnOn => 'Turn on';

  @override
  String get discussionTurnOff => 'Turn off';

  @override
  String get welcomeShowToNew => 'Show it to new subscribers';

  @override
  String get welcomeHint => 'Shown once, on joining';

  @override
  String get welcomePrivateNote =>
      'This channel is private, so the message is encrypted with the channel key like its name.';

  @override
  String get appearanceNote =>
      'A fixed set rather than a colour picker: every pair here was checked for contrast, so a channel cannot pick something its readers cannot read.';

  @override
  String get appearancePreviewPost => 'A post in this channel';

  @override
  String get appearancePreviewLink => 'and a link in it';

  @override
  String get appearanceAccent => 'Accent';

  @override
  String get appearanceBackground => 'Background';

  @override
  String get appearanceUseDefault => 'Use the default';

  @override
  String get composerHint => 'Type a message...';

  @override
  String get composerAttach => 'Attach a file';

  @override
  String get composerTimerOff => 'Disappearing messages are off';

  @override
  String composerTimerOn(String badge) {
    return 'Messages disappear after $badge';
  }

  @override
  String get searchPostsHint => 'Search posts you can read';

  @override
  String get searchThisChannel => 'Search this channel';

  @override
  String get searchClose => 'Close search';

  @override
  String get searchNoResults => 'Nothing matched';

  @override
  String get settingsPrivacy => 'Privacy & Security';

  @override
  String get settingsStorage => 'Data and Storage';

  @override
  String get settingsAbout => 'About Privio';

  @override
  String get settingsDevices => 'Devices';

  @override
  String get settingsBackup => 'Backup';

  @override
  String get settingsDisguise => 'Disguise mode';

  @override
  String get settingsLicense => 'Privio License';

  @override
  String get settingsLicenseNotActive => 'Not active';

  @override
  String get appearanceTextSize => 'Text size';

  @override
  String get appearanceTextSizeNote =>
      'This is Privio\'s own setting and it applies everywhere in the app. It does not override the size your phone is set to for everything else — that one still applies underneath.';

  @override
  String get appearanceDarkOnly =>
      'Privio is dark-only. The design is built for it, true black costs nothing on the OLED panels most phones ship with, and a light theme that only half exists is not worth a switch that pretends otherwise.';

  @override
  String get textSizeSmall => 'Small';

  @override
  String get textSizeMedium => 'Medium';

  @override
  String get textSizeLarge => 'Large';

  @override
  String get textSizeLarger => 'Larger';

  @override
  String get notificationsPushNote =>
      'A push carries no content — only a wake-up. The message is fetched and decrypted on this device, so nobody in the middle, including whoever runs the service that woke it, sees who wrote to you.';

  @override
  String get notificationsPhoneNote =>
      'Sound, vibration, the light and whether anything shows on the lock screen belong to your phone\'s own settings for Privio, not to this screen. There used to be five switches here that set nothing; they are gone rather than left looking like they worked.';

  @override
  String get notificationsDelivery => 'Delivery';

  @override
  String notificationsDistributorFound(String app) {
    return 'A distributor app on this phone holds one connection for every app that uses it, and forwards a contentless ping. $app needs no Google service for it, and you can run the distributor yourself.';
  }

  @override
  String get notificationsNoDistributor =>
      'No distributor found. Install one — ntfy, for example — to be woken while Privio is closed. Without one, messages arrive while the app is open.';

  @override
  String get privacyWhoCanSee => 'Who can see';

  @override
  String get privacyLastSeen => 'Last Seen';

  @override
  String get privacyLastSeenEveryone => 'Everyone';

  @override
  String get privacyLastSeenContacts => 'My contacts';

  @override
  String get privacyLastSeenNobody => 'Nobody';

  @override
  String get privacyMessaging => 'Messaging';

  @override
  String get privacyReadReceipts => 'Read Receipts';

  @override
  String get privacyTypingIndicators => 'Typing Indicators';

  @override
  String get privacyDisappearing => 'Disappearing Messages';

  @override
  String get privacyPerChat => 'Per chat';

  @override
  String get privacyAccess => 'Access';

  @override
  String get privacyScreenLock => 'Screen Lock';

  @override
  String get privacyPin => 'PIN';

  @override
  String get privacyTwoFactor => 'Two-Factor Authentication';

  @override
  String get privacyDuressCode => 'Duress Code';

  @override
  String get privacySet => 'Set';

  @override
  String get privacyBlockedUsers => 'Blocked Users';

  @override
  String get privacyMutualNote =>
      'Read receipts and typing indicators are mutual: turning them off also stops you from seeing other people’s.';

  @override
  String get storageOnThisDevice => 'On this device';

  @override
  String get storageHistory => 'Conversation history';

  @override
  String get storageInIt => 'In it';

  @override
  String storageChatsAndMessages(int chats, int messages) {
    String _temp0 = intl.Intl.pluralLogic(
      chats,
      locale: localeName,
      other: '$chats chats',
      one: '1 chat',
    );
    String _temp1 = intl.Intl.pluralLogic(
      messages,
      locale: localeName,
      other: '$messages messages',
      one: '1 message',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get storageKeys => 'Keys and sessions';

  @override
  String get storageKeystoreNote =>
      'Both sit in the platform keystore — the Keychain on iOS, Keystore-backed storage on Android — and the history is sealed with AES-256-GCM before it gets there. Neither is readable by another app, and neither is readable by anyone holding the phone without unlocking it.';

  @override
  String get storageNotKept => 'Not kept';

  @override
  String get storageFilesOpened => 'Files you opened';

  @override
  String get storageMemoryOnly => 'Memory only';

  @override
  String get storageVoiceRecordings => 'Voice recordings';

  @override
  String get storageShredded => 'Shredded when sent';

  @override
  String get storageEphemeralNote =>
      'A photo or file you open is decrypted into memory and goes when the app closes; nothing writes it to disk. A voice message is recorded to a temporary file, because the microphone has to write somewhere, and that file is overwritten with random bytes and deleted the moment the recording ends — a deleted file on flash storage is not a gone file.';

  @override
  String get storageDelete => 'Delete';

  @override
  String get storageDeleteHistory => 'Delete history on this device';

  @override
  String get storageDeleteNote =>
      'This is the only deletion that happens here. What the server holds — a backup, an attachment still inside its thirty days — is on the Backup screen, and what the person you wrote to has is theirs.';

  @override
  String get storageConfirmTitle => 'Delete the history on this device?';

  @override
  String get storageConfirmBody =>
      'Every message on this phone goes, in every chat. Your account, your keys and your conversations stay: people can still write to you, and what you send after this still arrives.\n\nIt cannot reach their copy, and it cannot reach a backup already on the server. Delete that from the Backup screen if you want it gone too.';

  @override
  String get storageDeleteIt => 'Delete it';

  @override
  String get storageDeleted => 'The history on this device is gone.';

  @override
  String get devicesThisDevice => 'This device';

  @override
  String get devicesOthers => 'Other devices';

  @override
  String get devicesOthersTapToSignOut => 'Other devices — tap to sign out';

  @override
  String get devicesNone => 'None';

  @override
  String get devicesOnlyThisOne => 'Only this one';

  @override
  String get devicesSignedIn => 'Signed in';

  @override
  String get devicesActiveNow => 'Active now';

  @override
  String devicesActiveMinutes(int count) {
    return 'Active $count min ago';
  }

  @override
  String devicesActiveHours(int count) {
    return 'Active $count h ago';
  }

  @override
  String get devicesActiveYesterday => 'Active yesterday';

  @override
  String devicesActiveDays(int count) {
    return 'Active $count days ago';
  }

  @override
  String get devicesSignOutNote =>
      'Signing a device out revokes its session and deletes anything still queued for it. It can only rejoin by signing in again — as a new device, with new keys.';

  @override
  String devicesRevokeTitle(String name) {
    return 'Sign out $name?';
  }

  @override
  String get devicesRevokeBody =>
      'Its session is revoked and anything still queued for it is deleted. What it has already decrypted stays on that device — nothing here can reach it. It can only come back by signing in again.';

  @override
  String get devicesSignItOut => 'Sign it out';

  @override
  String devicesSignedOut(String name) {
    return '$name is signed out.';
  }

  @override
  String devicesLicenseCovers(int limit) {
    return 'Your license covers $limit devices.';
  }

  @override
  String devicesLicenseCoversUsed(int limit, int used) {
    return 'Your license covers $limit devices. $used in use.';
  }

  @override
  String get aboutTagline =>
      'Built with privacy in mind.\nNo tracking. No ads. Just you.';

  @override
  String get aboutWebsite => 'Website';

  @override
  String get aboutSupport => 'Support';

  @override
  String get aboutAddress => 'Address';

  @override
  String get aboutOpenSource => 'Open source';

  @override
  String get aboutEdition => 'Edition';

  @override
  String aboutFreeSoftware(String name) {
    return '$name · free software';
  }

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutSourceCode => 'Source code';

  @override
  String get aboutCopyLink => 'Copy link';

  @override
  String get aboutSourceLink => 'Source link';

  @override
  String get aboutThirdParty => 'Third-party licenses';

  @override
  String aboutCopied(String what) {
    return '$what copied.';
  }

  @override
  String get aboutFreeBuildNote =>
      'This build contains no proprietary code and can be reproduced from the source above. Nothing here has to be taken on trust — build it yourself and compare.';

  @override
  String get aboutStoreBuildNote =>
      'This build came from an app store and links that store\'s services. The Libre build, at the source above, contains none of them.';

  @override
  String get blockedUnblock => 'Unblock';

  @override
  String blockedUnblockTitle(String name) {
    return 'Unblock $name?';
  }

  @override
  String get blockedUnblockBody =>
      'They will be able to send you messages again.';

  @override
  String get blockedInvisibleNote =>
      'Blocking is invisible: their messages are dropped and they are told nothing, so a block cannot be used to find out that they have been blocked.';

  @override
  String get blockedNobody => 'Nobody is blocked';

  @override
  String get blockedEmptyNote =>
      'Block someone from their chat, and they turn up here.';
}
