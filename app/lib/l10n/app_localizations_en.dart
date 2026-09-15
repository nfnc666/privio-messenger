// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppTextEn extends AppText {
  AppTextEn([String locale = 'en']) : super(locale);

  @override
  String get proxyTitle => 'SOCKS5 proxy';

  @override
  String get proxyEnable => 'Use proxy';

  @override
  String get proxyHost => 'Server (hostname or IP)';

  @override
  String get proxyPort => 'Port';

  @override
  String get proxyUsername => 'Username (optional)';

  @override
  String get proxyPassword => 'Password (optional)';

  @override
  String get proxyScope =>
      'For this device, including login, messages, media and backups. Calls are disabled while the proxy is active. No direct fallback. Save to apply changes.';

  @override
  String get proxyPrivacy =>
      'System push notifications and links opened in a browser do not use this proxy. SOCKS5 does not encrypt proxy credentials; use a trusted network/proxy. The proxy sees your IP and destination, but HTTPS stays encrypted. Telegram MTProto proxies are not supported.';

  @override
  String get proxyTest => 'Test connection';

  @override
  String get proxySave => 'Save';

  @override
  String get proxyRemove => 'Remove proxy and connect directly';

  @override
  String get proxyInvalid =>
      'Enter a valid server and port (1–65535). Enter both username and password, or leave both empty.';

  @override
  String get proxyTestSuccess =>
      'Privio is reachable through this proxy. Settings have not been saved.';

  @override
  String get proxySaved => 'Network settings saved.';

  @override
  String get proxyFailed =>
      'Could not complete this action. Check the proxy, credentials and connection, and end any active call. No automatic direct fallback.';

  @override
  String get proxyCallsBlocked =>
      'Calls are unavailable while the proxy is active.';

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
      'Sound, vibration, the light and whether anything shows on the lock screen belong to your phone\'s own settings for Privio, not to this screen.';

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
  String get privacyScreenShield => 'Screen protection';

  @override
  String get privacyScreenShieldAndroid =>
      'Blocks screenshots and screen recordings of the app.';

  @override
  String get privacyScreenShieldIos =>
      'Hides sensitive content when a screen recording or screen sharing is detected. Screenshots cannot be reliably prevented on iOS.';

  @override
  String get privacyScreenShieldUnavailable =>
      'This device cannot protect the screen.';

  @override
  String get privacyScreenShieldScope =>
      'This protects your own device only. It cannot stop anyone else recording their screen, and it cannot stop a photograph taken with another camera.';

  @override
  String get privacyScreenShieldCovering =>
      'A screen recording is running. Privio is hidden until it stops.';

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

  @override
  String get chatsSectionChats => 'Chats';

  @override
  String get chatsSectionMessages => 'Messages';

  @override
  String get chatsYouPrefix => 'You: ';

  @override
  String get chatsNoSearchResults =>
      'Nothing here matches. Only this device was asked — the server holds messages it cannot read, so it could not have answered.';

  @override
  String get chatsFilterAll => 'All';

  @override
  String get chatsJoin => 'Join';

  @override
  String get chatsFilterUnread => 'Unread';

  @override
  String get chatsFilterGroups => 'Groups';

  @override
  String get chatsPin => 'Pin to top';

  @override
  String get chatsUnpin => 'Unpin';

  @override
  String get chatsPinNote => 'Only on this device. Nothing is sent.';

  @override
  String get chatsGroupFallbackName => 'Group';

  @override
  String get chatsNewGroupTooltip => 'New group';

  @override
  String get chatsNewChatTooltip => 'New chat';

  @override
  String get chatsEmptyTitle => 'No chats yet';

  @override
  String get chatsEmptyBody =>
      'Add someone by their exact username to start talking.';

  @override
  String get chatsAddContact => 'Add a contact';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get commonPause => 'Pause';

  @override
  String get commonPlay => 'Play';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonReply => 'Reply';

  @override
  String get commonFile => 'File';

  @override
  String get scrubRemoved => 'Metadata removed';

  @override
  String get scrubNothingToRemove => 'Nothing to remove';

  @override
  String get scrubCouldNotClean => 'Could not be cleaned';

  @override
  String get scrubRemovedBody =>
      'This was stripped out before the file was encrypted and sent. The recipient never receives it.';

  @override
  String get scrubNothingBody =>
      'This file carried no identifying metadata to begin with.';

  @override
  String scrubNoCleanerBody(String type) {
    return 'Privio has no cleaner for $type yet, so the file was sent as it is. It is still end-to-end encrypted, but any metadata inside it reaches the recipient.';
  }

  @override
  String get webStorageShort =>
      'In a browser, this device’s history is only as private as this browser profile. Messages in transit are encrypted either way.';

  @override
  String get webStorageLong =>
      'You are using Privio in a browser. Messages are still end-to-end encrypted in transit — but a browser has no keystore, so the history kept on this device is only as private as this browser profile. Anyone who can read it — a shared computer, an extension, a copy of the profile — can read your chats. The phone apps do not have this problem.';

  @override
  String get voiceCouldNotOpen => 'Could not open this recording.';

  @override
  String get voiceCannotPlay => 'This device cannot play that recording.';

  @override
  String get voiceMicUnavailable =>
      'The microphone is not available right now.';

  @override
  String get voiceCouldNotSave => 'That recording could not be saved.';

  @override
  String get voiceSlideToCancel => 'Slide to cancel';

  @override
  String get voiceResume => 'Resume';

  @override
  String get voiceStop => 'Stop';

  @override
  String get voiceDeleteRecording => 'Delete recording';

  @override
  String get voiceListenBack => 'Listen back';

  @override
  String get bubbleYouDeleted => 'You deleted this message';

  @override
  String get bubbleMessageDeleted => 'This message was deleted';

  @override
  String get bubbleCouldNotOpen => 'Could not open';

  @override
  String get bubbleEncryptedNotice =>
      'Messages and calls are end-to-end encrypted. No one outside this chat can read or listen to them, not even Privio.';

  @override
  String get linkNotWebAddress => 'That link is not a web address.';

  @override
  String get linkNothingCanOpen =>
      'Nothing on this device could open that link.';

  @override
  String get linkOpenTitle => 'Open this link?';

  @override
  String get linkOpenBody =>
      'This opens in your browser, outside Privio. The site sees your connection the way any site you visit does.';

  @override
  String timerBadgeDays(int count) {
    return '${count}d';
  }

  @override
  String timerBadgeHours(int count) {
    return '${count}h';
  }

  @override
  String timerBadgeMinutes(int count) {
    return '${count}m';
  }

  @override
  String timerBadgeSeconds(int count) {
    return '${count}s';
  }

  @override
  String get chatSafetyNumberChanged => 'Safety number changed';

  @override
  String get chatEncrypted => 'End-to-end encrypted';

  @override
  String get chatEncryptedVerified => 'End-to-end encrypted · verified';

  @override
  String get chatEncryptedNumberChanged =>
      'End-to-end encrypted · number changed';

  @override
  String get chatWaitingGroupKey => 'Waiting for the group key';

  @override
  String chatMembersEncrypted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0 · encrypted';
  }

  @override
  String get chatRetrySendTitle => 'Try again';

  @override
  String get chatRetryFailed => 'It did not go out. Send it now.';

  @override
  String get chatRetryQueued => 'Waiting for a network. Try now anyway.';

  @override
  String get chatCopyText => 'Copy text';

  @override
  String get chatDeleteForMe => 'Delete for me';

  @override
  String get chatDeleteForMeNote =>
      'Gone from this device. Other devices keep it.';

  @override
  String get chatDeleteForEveryone => 'Delete for everyone';

  @override
  String get chatDeleteForEveryoneNote =>
      'Asks their app to forget it. It cannot take back what was already read, screenshotted, or restored from a backup.';

  @override
  String get chatPickerNoResponse => 'The file picker did not respond.';

  @override
  String chatPickerFailed(String reason) {
    return 'Could not open the file picker: $reason';
  }

  @override
  String chatCouldNotReadFile(String name) {
    return 'Could not read $name.';
  }

  @override
  String chatBlockTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get chatBlockBody =>
      'Their messages stop arriving. They are not told, and it looks to them as though nothing changed. You can lift it in Privacy & Security.';

  @override
  String get chatBlock => 'Block';

  @override
  String chatBlocked(String name) {
    return '$name is blocked.';
  }

  @override
  String get chatCouldNotBlock => 'Could not block them.';

  @override
  String get chatMicrophoneDenied =>
      'Privio cannot record without microphone access. You can grant it in your device settings.';

  @override
  String get chatNoGroupLink => 'No link for this group yet — pull to refresh.';

  @override
  String get chatInviteLink => 'Invite link';

  @override
  String get chatInviteLinkNote =>
      'Share it anywhere — it carries no key. Whoever opens it joins the group, and the key to its name reaches their device encrypted.';

  @override
  String get chatTyping => 'typing…';

  @override
  String get chatVideoCall => 'Video call';

  @override
  String get chatVoiceCall => 'Voice call';

  @override
  String get chatMore => 'More';

  @override
  String get chatGroupInfo => 'Group info';

  @override
  String get chatSafetyNumber => 'Safety number';

  @override
  String get chatActivate => 'Activate';

  @override
  String get chatSend => 'Send';

  @override
  String get chatHoldToRecord =>
      'Hold the microphone to record a voice message.';

  @override
  String get chatReplyingToYourself => 'Replying to yourself';

  @override
  String chatReplyingTo(String name) {
    return 'Replying to $name';
  }

  @override
  String get chatReplying => 'Replying';

  @override
  String get chatCancelReply => 'Cancel reply';

  @override
  String get contactsTitle => 'Contacts';

  @override
  String get contactsSearch => 'Search contacts';

  @override
  String contactsLastSeen(String username, String when) {
    return '@$username · last seen $when';
  }

  @override
  String get contactsSeenJustNow => 'just now';

  @override
  String contactsSeenMinutes(int count) {
    return '$count min ago';
  }

  @override
  String contactsSeenAtTime(String time) {
    return 'at $time';
  }

  @override
  String contactsSeenDays(int count) {
    return '${count}d ago';
  }

  @override
  String get contactsCouldNotAdd => 'Could not add that user';

  @override
  String get contactsAddTitle => 'Add contact';

  @override
  String get contactsAddNote =>
      'Enter their exact Privio username. Nothing is uploaded from your address book, and nobody can find you by browsing.';

  @override
  String get contactsUsernameHint => 'username';

  @override
  String get contactsEmptyTitle => 'No contacts yet';

  @override
  String get contactsEmptyBody =>
      'Add someone by their exact username, or share your invite link from the Account tab.';

  @override
  String get groupCouldNotCreate => 'Could not create the group';

  @override
  String get groupNewTitle => 'New group';

  @override
  String get groupCreate => 'Create';

  @override
  String get groupName => 'Group name';

  @override
  String get groupNameEncryptedNote =>
      'The name is encrypted. Privio stores a group it cannot name.';

  @override
  String get groupChooseMembers => 'Choose members';

  @override
  String groupSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get groupAddContactsFirst =>
      'Add some contacts first — a group needs people in it.';

  @override
  String get groupInfoCouldNotRead => 'Could not read who is in this group.';

  @override
  String get groupAdminOnly => 'Only an admin can change this';

  @override
  String get groupRename => 'Rename group';

  @override
  String get groupRenameAction => 'Rename';

  @override
  String get groupRenamed =>
      'Renamed. Everyone else opens the new name with the key they already have.';

  @override
  String get groupCouldNotRename => 'Could not rename the group.';

  @override
  String groupRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get groupRemoveBody =>
      'They stop receiving what is sent from now on. What they already received stays on their device — nothing here can reach it.';

  @override
  String get groupCouldNotRemove => 'Could not remove them.';

  @override
  String get groupLeaveTitle => 'Leave this group?';

  @override
  String get groupLeaveBody =>
      'You stop receiving what is sent to it, and the conversation goes from this device with everything in it. Nobody is told; the others see you disappear from the member list.';

  @override
  String get groupLeave => 'Leave';

  @override
  String get groupLeaveRow => 'Leave group';

  @override
  String get groupDeleteTitle => 'Delete this group?';

  @override
  String get groupDeleteBody =>
      'It goes for everyone: nobody can send to it again. What has already been delivered stays on the devices that received it, which is every message anyone has read.';

  @override
  String get groupDeleteRow => 'Delete group for everyone';

  @override
  String get groupYouSuffix => 'You';

  @override
  String get groupAdminSuffix => 'Admin';

  @override
  String get navChats => 'Chats';

  @override
  String get navChannels => 'Channels';

  @override
  String get navCalls => 'Calls';

  @override
  String get navContacts => 'Contacts';

  @override
  String get navAccount => 'Account';

  @override
  String get splashTagline => 'Secure Messenger';

  @override
  String get splashPromise => 'Encrypted. Private. Yours.';

  @override
  String get splashInitialising => 'Initializing secure environment';

  @override
  String accountPickerFailed(String reason) {
    return 'Could not open the picker: $reason';
  }

  @override
  String accountCouldNotReadFile(String name, String reason) {
    return 'Could not read $name: $reason';
  }

  @override
  String get accountCouldNotSetPicture => 'Could not set the picture';

  @override
  String get accountTapToAddPicture => 'Tap to add a picture';

  @override
  String get accountPictureEncrypted =>
      'Encrypted — only your contacts can see it';

  @override
  String get accountUsername => 'Username';

  @override
  String get accountStatus => 'Status';

  @override
  String get accountStatusDefault => 'Hey there! I am using Privio.';

  @override
  String get accountStatusNone => 'Not set';

  @override
  String get accountStatusTitle => 'Status';

  @override
  String get accountStatusHint => 'What are you up to?';

  @override
  String get accountStatusEmoji => 'Emoji';

  @override
  String get accountStatusEmojiNone => 'None';

  @override
  String get accountStatusClearsAfter => 'Clears after';

  @override
  String get accountStatusNeverClears => 'Never';

  @override
  String get accountStatus30Minutes => '30 minutes';

  @override
  String get accountStatus1Hour => '1 hour';

  @override
  String get accountStatus4Hours => '4 hours';

  @override
  String get accountStatusToday => 'Today';

  @override
  String get accountStatus1Week => '1 week';

  @override
  String accountStatusUntil(String time) {
    return 'Until $time';
  }

  @override
  String get accountStatusCouldNotSave =>
      'Your status was not saved. What you typed is still here — try again.';

  @override
  String get accountStatusSaving => 'Saving…';

  @override
  String get accountStatusExplainer =>
      'Anyone allowed to see your status reads this. It is not encrypted the way your messages are, and it is not your online status.';

  @override
  String get privacyProfileStatus => 'Status';

  @override
  String get privacyProfileStatusEveryone => 'Everyone';

  @override
  String get privacyProfileStatusContacts => 'My contacts';

  @override
  String get privacyProfileStatusNobody => 'Nobody';

  @override
  String get accountId => 'Account ID';

  @override
  String get accountInviteRow => 'Invite link / QR code';

  @override
  String get accountLogOut => 'Log Out';

  @override
  String get accountLogOutQuestion => 'Log out?';

  @override
  String get accountLogOutBody =>
      'Your messages stay encrypted on this device until you delete them. You will need your password to sign back in.';

  @override
  String get accountDelete => 'Delete account';

  @override
  String get accountDeleteTitle => 'Delete this account?';

  @override
  String get accountDeleteBody =>
      'Your devices, your keys, the messages still waiting to be delivered, your contacts, your group memberships and your backup are all deleted on the server. Everything on this phone goes with them.\n\nIt cannot reach what other people have already received, and your username becomes free for somebody else to take.\n\nThere is no undo and no recovery — not with the recovery key, not by writing to anybody.';

  @override
  String get accountYourPassword => 'Your password';

  @override
  String get accountDeleteIt => 'Delete it';

  @override
  String get inviteTitle => 'Invite';

  @override
  String get inviteTabLink => 'Invite Link';

  @override
  String get inviteTabQr => 'QR Code';

  @override
  String get inviteYourLink => 'Your invite link';

  @override
  String get inviteCopied => 'Invite link copied';

  @override
  String get inviteCopyLink => 'Copy link';

  @override
  String get inviteCopyInviteLink => 'Copy invite link';

  @override
  String get inviteNote =>
      'Share this link with others to invite them to Privio. It reveals your username and nothing else.';

  @override
  String inviteScanToConnect(String username) {
    return 'Scan to connect with @$username';
  }

  @override
  String get callsClearHistory => 'Clear call history';

  @override
  String get callsClearTitle => 'Clear call history?';

  @override
  String get callsClearBody =>
      'This list is only on this device — clearing it removes it from here and from nowhere else, because it was never anywhere else.';

  @override
  String get callsClear => 'Clear';

  @override
  String get callsNeverLeavesNote =>
      'This list never leaves the device. The server routes a call\'s setup the way it routes a message — sealed, and unreadable to it — so it holds no record of who called whom.';

  @override
  String callsCallSomeone(String name) {
    return 'Call $name';
  }

  @override
  String get callsDeclined => 'Declined';

  @override
  String get callsNotTaken => 'Not taken';

  @override
  String get callsBusy => 'Busy';

  @override
  String get callsCouldNotConnect => 'Could not connect';

  @override
  String get callsMissed => 'Missed';

  @override
  String get callsNoAnswer => 'No answer';

  @override
  String get callsEmptyTitle => 'No calls yet';

  @override
  String get callsEmptyBody =>
      'Start one from a chat. The call is set up over the Signal session that chat already uses, so the addresses your two devices swap to find each other are sealed to each other and not to the server.';

  @override
  String get callCalling => 'Calling…';

  @override
  String get callIncomingVideo => 'Incoming video call';

  @override
  String get callIncoming => 'Incoming call';

  @override
  String get callConnecting => 'Connecting…';

  @override
  String get callEnded => 'Call ended';

  @override
  String get callDecline => 'Decline';

  @override
  String get callAccept => 'Accept';

  @override
  String get callMute => 'Mute';

  @override
  String get callUnmute => 'Unmute';

  @override
  String get callCamera => 'Camera';

  @override
  String get callCameraOff => 'Camera off';

  @override
  String get callEnd => 'End';

  @override
  String get callSpeaker => 'Speaker';

  @override
  String get welcomePromiseEncrypted => 'End-to-end encrypted';

  @override
  String get welcomePromiseNoPhone => 'No phone number required';

  @override
  String get welcomePromiseControl => 'You\'re in control';

  @override
  String get welcomePromiseByDesign => 'Privacy by design';

  @override
  String get welcomeTo => 'Welcome to';

  @override
  String get welcomeGetStarted => 'Get Started';

  @override
  String get welcomeHaveAccount => 'I already have an account';

  @override
  String get welcomeImportBackup => 'Import from backup';

  @override
  String get authCreateTitle => 'Create your account';

  @override
  String get authWelcomeBack => 'Welcome back';

  @override
  String get authCreateNote =>
      'Pick a username. No phone number, no email — nothing to link this account to anything else.';

  @override
  String get authSignInNote => 'Sign in with your username and password.';

  @override
  String get authUsernameRule => '3–32 characters: a–z, 0–9, dot or underscore';

  @override
  String get authPasswordRule =>
      'At least 10 characters — this one protects everything';

  @override
  String get authPasswordRequired => 'Enter your password';

  @override
  String get authTotpHint => 'two-factor code';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authCreateNew => 'Create a new account';

  @override
  String get authPasswordOnlyWay =>
      'Your password is the only way into this account. Privio cannot reset it, because Privio cannot read anything it would unlock.';

  @override
  String get pinEnterPassphrase => 'Enter your passphrase';

  @override
  String get pinEnterPasscode => 'Enter your passcode';

  @override
  String get pinPassphrase => 'Passphrase';

  @override
  String get pinWrong => 'That is not it.';

  @override
  String get pinUnlock => 'Unlock';

  @override
  String get activationTitle => 'Activate Privio';

  @override
  String get activationSignedInNote =>
      'Your account is ready. This server asks for a license key before it will relay your messages.';

  @override
  String get activationNewNote =>
      'This server asks for a license key before it will relay messages. Enter yours now and it is activated as soon as your account exists.';

  @override
  String get activationActivate => 'Activate';

  @override
  String get activationNoKeyYet => 'I do not have a key yet';

  @override
  String get activationWithoutKeyNote =>
      'Without a key you can create an account, sign in and read what arrives, but not send. You can enter it later under Settings › Privio License.';

  @override
  String activationFreeSoftwareNote(String name, String license) {
    return '$name is free software under $license. The key does not unlock the app — you already have all of it, and can build it yourself. It pays for the hosted service that relays your messages.';
  }

  @override
  String get backupCouldNotReach =>
      'Could not reach Privio to check the backup.';

  @override
  String get backupDone => 'Backed up. Privio cannot read it.';

  @override
  String get backupUploadFailed => 'The backup could not be uploaded.';

  @override
  String get backupBadKey => 'That does not look like a recovery key.';

  @override
  String backupRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Restored $count conversations.',
      one: 'Restored 1 conversation.',
    );
    return '$_temp0';
  }

  @override
  String get backupKeyDidNotOpen =>
      'That key did not open the backup, or there is none to open.';

  @override
  String get backupLast => 'Last backup';

  @override
  String get backupOnServer => 'On the server';

  @override
  String get backupNothingYet => 'Nothing yet';

  @override
  String get backupAlways => 'Always';

  @override
  String get backupNow => 'Back up now';

  @override
  String get backupAutomatic => 'Automatic backup';

  @override
  String get backupIntervalDaily => 'Daily';

  @override
  String get backupIntervalWeekly => 'Weekly';

  @override
  String get backupRecoveryKey => 'Recovery key';

  @override
  String get backupRestoreRow => 'Restore from backup';

  @override
  String get backupSealedNote =>
      'Backups are sealed on this device with your recovery key. Privio cannot open them and cannot reset the key — if you lose it, the backup is gone. Write it down somewhere safe.\n\nA backup holds your conversations, not your keys: restoring on a new device gives you your history, and that device sets up its own identity for what comes next.';

  @override
  String get backupNever => 'Never';

  @override
  String backupToday(String time) {
    return 'Today, $time';
  }

  @override
  String get backupWriteItDown =>
      'Write this down. It is the only thing that opens your backups, and nobody — including Privio — can produce it again for you.';

  @override
  String get backupRestoreReplacesNote =>
      'This replaces whatever is on this device with what is in the backup.';

  @override
  String get backupRestore => 'Restore';

  @override
  String get twoFactorOnToast =>
      'Two-factor is on. Keep the recovery of your authenticator safe.';

  @override
  String get twoFactorOffToast => 'Two-factor is off.';

  @override
  String get twoFactorTurnOffTitle => 'Turn off two-factor';

  @override
  String get twoFactorTurnOff => 'Turn off';

  @override
  String get twoFactorTurnOn => 'Turn on';

  @override
  String get twoFactorServerNote =>
      'The code is checked at login, on the server. It protects the account itself — someone who learns your password still cannot sign a new device in. It is not what encrypts your messages: that is the key on this device, and no code can replace it.';

  @override
  String get twoFactorOffBody =>
      'With two-factor on, signing in needs a six-digit code from your authenticator app as well as your password.';

  @override
  String get twoFactorSetUp => 'Set it up';

  @override
  String get twoFactorScanThis => 'Scan this';

  @override
  String get twoFactorScanNote =>
      'Add it to your authenticator app, then type the code it shows. Two-factor is not on until that code has been checked.';

  @override
  String get twoFactorTypeKey => 'Or type this key';

  @override
  String get twoFactorKeyCopied => 'Key copied.';

  @override
  String get twoFactorOnBody =>
      'Signing in asks for a code from your authenticator app.';

  @override
  String get passcodeFourDigits => '4 digits';

  @override
  String get passcodeSixDigits => '6 digits';

  @override
  String get passcodeFourDigitsNote =>
      'Ten thousand combinations. Quick, and enough against someone who picks the phone up.';

  @override
  String get passcodeSixDigitsNote =>
      'A million combinations, and still a keypad.';

  @override
  String get passcodePhraseNote =>
      'Letters, and digits or symbols if you want them. The only one of the three that stands up to someone with the phone and time.';

  @override
  String get passcodeNeedsFourDigits => 'Four digits.';

  @override
  String get passcodeNeedsSixDigits => 'Six digits.';

  @override
  String passcodePhraseTooShort(int count) {
    return 'At least $count characters.';
  }

  @override
  String get passcodePhraseNeedsLetter =>
      'A passphrase needs at least one letter. Digits and symbols are welcome alongside it.';

  @override
  String get lockEntriesDiffer => 'The two entries are not the same.';

  @override
  String get lockOnToast =>
      'App lock on. Privio asks for it when it comes back.';

  @override
  String get lockOffToast => 'App lock off.';

  @override
  String get lockTurnOffTitle => 'Turn off the app lock?';

  @override
  String get lockTurnOffBody =>
      'Anyone holding an unlocked phone reaches your messages. A duress code set for the lock screen is removed with it.';

  @override
  String get lockTurnOffRow => 'Turn off the app lock';

  @override
  String get lockWhatItIsNote =>
      'A passcode on this device, asked for whenever Privio comes back to the foreground. It is not your account password and it never leaves the phone — it guards the history already encrypted on it.';

  @override
  String get lockNoBiometricsNote =>
      'There is no face or fingerprint option. Those are the one credential someone can hold a phone up to your face to use, or press your finger onto while you are asleep — and in several places a court can order them where it cannot order a passcode.';

  @override
  String get lockChangePasscode => 'Change the passcode';

  @override
  String get lockChoosePasscode => 'Choose a passcode';

  @override
  String get lockAgain => 'Again';

  @override
  String get lockChangeIt => 'Change it';

  @override
  String get lockTurnItOn => 'Turn it on';

  @override
  String get lockForgettingNote =>
      'Forgetting it means signing in again, which is a new device to the server: what was already delivered here is gone unless it is in a backup. There is no reset, because a reset anyone could ask for would not be a lock.';

  @override
  String get duressNoLockNote =>
      'At the lock screen it does nothing yet, because there is no app lock on this device. Turn one on under Screen Lock, and a duress code shaped like that lock works there too — which is where a phone that is already signed in gets taken.';

  @override
  String duressShapeNote(String kind) {
    return 'This device unlocks with $kind. A duress code of the same shape can be typed at the lock screen, where it destroys instead of unlocking. Any other shape works at sign-in only.';
  }

  @override
  String get duressMatchesLock =>
      'This one matches the lock on this device, so it works at the lock screen as well as at sign-in.';

  @override
  String duressDoesNotMatchLock(String kind) {
    return 'This one does not match the lock on this device ($kind), so it works at sign-in only — the lock screen has nowhere to type it.';
  }

  @override
  String get duressAtLeastFour => 'Use at least four characters.';

  @override
  String get duressCodesDiffer => 'The two codes are not the same.';

  @override
  String get duressSameAsUnlock =>
      'That is the code that unlocks this device. A duress code has to be different: the lock screen checks it first, so the two being the same would destroy the account every time you unlocked — without saying so.';

  @override
  String get duressSetBoth =>
      'Duress code set. It destroys the account at sign-in and at the lock screen.';

  @override
  String get duressSetSignInOnly =>
      'Duress code set. Typing it at sign-in destroys the account.';

  @override
  String get duressRemoved => 'Duress code removed.';

  @override
  String get duressRemoveTitle => 'Remove the duress code';

  @override
  String get duressWarning =>
      'Typing this code instead of your password at sign-in destroys the account: every device, every message still waiting, your contacts, your group memberships, your backup. There is no undo, and no confirmation — that is the point.';

  @override
  String get duressIsSet => 'A duress code is set';

  @override
  String get duressCannotShow =>
      'Privio cannot show it to you — it is stored the way a password is. Setting a new one below replaces it.';

  @override
  String get duressRemoveIt => 'Remove it';

  @override
  String get duressReplaceIt => 'Replace it';

  @override
  String get duressSetOne => 'Set a duress code';

  @override
  String get duressAccountPassword => 'Your Privio account password';

  @override
  String get duressLooksLikePin =>
      'That is shorter than an account password. This field wants the password you chose when you created the account — not the PIN that unlocks the app.';

  @override
  String get duressCodeField => 'Duress code';

  @override
  String get duressCodeAgain => 'Duress code again';

  @override
  String get duressReplaceCode => 'Replace the code';

  @override
  String get duressSetCode => 'Set the code';

  @override
  String get duressWhatItDoesNotDo =>
      'What it does not do: the account name stays taken, so nobody can claim it afterwards, and it cannot reach a different device that is already signed in somewhere else. Anyone watching sees the attempt refused exactly as a mistyped password or PIN is refused.';

  @override
  String get disguiseIntro =>
      'A locked Privio opens to a working calculator instead of a lock screen. Any sum that comes to your passcode opens Privio when you press =, so the code itself never has to appear on screen. Every other sum is just a sum.';

  @override
  String get disguiseOpenTo => 'Open to';

  @override
  String get disguiseLockScreen => 'The lock screen';

  @override
  String disguiseCalculatorNamed(String name) {
    return '$name calculator';
  }

  @override
  String get disguisePickNote =>
      'Pick the one your phone already ships. A calculator that does not look like the usual one is the thing somebody notices.';

  @override
  String get disguiseSeeIt => 'See it';

  @override
  String disguiseErrorSuffix(String reason) {
    return '$reason The lock screen changed anyway; the home screen did not.';
  }

  @override
  String get disguiseNoLock =>
      'There is no screen lock on this device yet, so there is no code to type into a calculator.';

  @override
  String get disguisePhraseLock =>
      'Your screen lock is a passphrase. A calculator has ten keys and no letters, so there is no way to type it in. Switch the lock to 4 or 6 digits to use a disguise.';

  @override
  String get disguiseOnHomeScreen => 'On the home screen';

  @override
  String get disguiseWhatItDoesNotDo => 'What this does not do';

  @override
  String get disguiseNotADefence =>
      'It is not a defence against anyone who has the phone for long. The app is still installed, and its size, its files and its network traffic are all still there to find by anyone who looks properly. What it is good at is the ordinary case — a screen glanced at, or a phone handed over unlocked.';

  @override
  String get disguiseHomeScreenChanges =>
      'On the home screen and in the app drawer, Privio becomes a calculator icon called \"Calculator\". Your launcher may take a few seconds to redraw, and an icon you pinned to the home screen yourself may need pinning again. Turning the disguise off puts it back.\n\nAndroid\'s own app list — Settings, app info, the name shown when Privio asks for a permission — still says Privio. That name is set when the app is built and no app can change it while running.';

  @override
  String get disguiseIconUnchanged =>
      'On this device the icon and the name do not change — only what the app opens to. Someone going through the home screen still finds Privio by name.';

  @override
  String get disguiseClosePreview => 'Close preview';

  @override
  String get licenseActivatedToast =>
      'Activated. This license now belongs to your account.';

  @override
  String get licenseNotCheckedTitle => 'Not checked yet';

  @override
  String get licenseNotCheckedBody =>
      'Privio has not been able to ask the server about this account yet. Pull the app back online and reopen this screen.';

  @override
  String get licenseNotNeededTitle => 'No license needed here';

  @override
  String get licenseNotNeededBody =>
      'This server does not require one. Licensing is for the hosted Privio service — a license for infrastructure you already run would mean nothing.';

  @override
  String get licenseStoreTitle => 'Handled by the store';

  @override
  String licenseStoreBody(String store) {
    return 'This build was paid for through the app store it came from, so there is no key to enter. If it is not active, restore your purchase in $store.';
  }

  @override
  String get licenseOnePurchaseNote =>
      'One purchase, one key, one account, for good. A redeemed key is bound to the account that redeemed it and cannot be moved or used again.';

  @override
  String get licenseEnterTitle => 'Enter your license key';

  @override
  String get licenseEnterBody =>
      'Buy a key at getprivio.com/license, then type it here. Until it is activated this account can sign in and read what has already arrived, but not send.';

  @override
  String get licenseActivated => 'Activated';

  @override
  String licenseRedeemedOn(String date) {
    return 'Redeemed on $date.';
  }

  @override
  String get licenseFromAppStore => 'Bought through the App Store.';

  @override
  String get licenseFromPlay => 'Bought through Google Play.';

  @override
  String get licenseFromKey =>
      'Activated with a license key. Lifetime access, no renewals.';

  @override
  String get safetyTrustedToast =>
      'The new key is trusted. Compare the number again before you rely on it.';

  @override
  String get safetyMatches => 'That matches one of the numbers below.';

  @override
  String get safetyNoMatch => 'That matches none of the numbers below.';

  @override
  String safetyNothingYet(String name) {
    return 'There is nothing to compare yet. A number exists once you and $name have exchanged a message, because only then has this device pinned a key of theirs.';
  }

  @override
  String safetyReadThese(String name) {
    return 'Read these digits to $name — on a call, or in person. If they see the same ones, no one is sitting between you. If they do not, stop using this chat for anything you would not say in public.';
  }

  @override
  String get safetyMarkNotVerified => 'Mark as not verified';

  @override
  String get safetyMarkVerified => 'Mark as verified';

  @override
  String safetyMarkNote(String name) {
    return 'Marking this verified records the exact keys on screen. If any of them changes, or a new device joins $name, the mark goes back to changed on its own — it is a record of what you checked, not a promise about what happens next.';
  }

  @override
  String get safetyVerified => 'Verified';

  @override
  String get safetyChangedSince => 'Changed since you checked';

  @override
  String get safetyNotVerified => 'Not verified';

  @override
  String safetyTheirDevice(int index) {
    return 'Their device $index';
  }

  @override
  String get safetyCompareTitle => 'Compare a number they sent you';

  @override
  String get safetyCompare => 'Compare';

  @override
  String get safetyKeyNotYours =>
      'The key on the server is not the one you had';

  @override
  String get safetyRefusedUntilDecide =>
      'Messages to this chat are refused until you decide. Reinstalling Privio, or signing in on a new device, does this legitimately and is the usual reason. So does a server handing you a key of its own, which looks exactly the same from here — which is why the number below is worth comparing again afterwards.';

  @override
  String get safetyTrustNewKey => 'Trust the new key';

  @override
  String get safetyKeyChangedArrived =>
      'Their key changed, and a message with it arrived';

  @override
  String get safetyKeyChangedBody =>
      'The new key is already in use — a message that brings one cannot be turned away without handing anyone a way to silence a chat. Reinstalling does this. So does someone stepping in. The number below is the difference, and it is only worth anything compared out loud.';

  @override
  String get channelsCouldNotOpenLink => 'Could not open that link';

  @override
  String get channelsJoinWithLink => 'Join with a link';

  @override
  String get channelsNewChannel => 'New channel';

  @override
  String get channelsTabFollowing => 'Following';

  @override
  String get channelsTabDiscover => 'Discover';

  @override
  String get channelsSearchMine => 'Search your channels';

  @override
  String get channelsSearchPublic => 'Search public channels';

  @override
  String get channelsEmptyTitle => 'No channels yet';

  @override
  String get channelsEmptyBody =>
      'Create one, or find a public channel under Discover.';

  @override
  String get channelsNothingFound => 'Nothing found';

  @override
  String get channelsDiscoverEmptyBody =>
      'Search public channels by name, handle or description. Private channels never appear here.';

  @override
  String channelsHandleAndMembers(String handle, String members) {
    return '@$handle  ·  $members';
  }

  @override
  String get channelsJoinTitle => 'Join a channel';

  @override
  String get channelsJoinNote =>
      'Paste a channel link. It shows you the channel; joining is a button there. Joining does not hand you the key either — a member who has it sends it to your device, encrypted, right after.';

  @override
  String get categoryNews => 'News';

  @override
  String get categoryTechnology => 'Technology';

  @override
  String get categoryCommunity => 'Community';

  @override
  String get categoryEducation => 'Education';

  @override
  String get categoryCulture => 'Culture';

  @override
  String newChannelPictureUnreadable(String name) {
    return 'Privio could not read $name. Try a different picture.';
  }

  @override
  String get newChannelCouldNotCreate => 'Could not create the channel';

  @override
  String get newChannelWithoutPicture =>
      'The channel was created without the picture.';

  @override
  String get newChannelCreate => 'Create';

  @override
  String get newChannelPublicPictureNote =>
      'A public channel\'s picture is shown on its web page and in link previews, so it is stored unencrypted — the same as its name, handle and description.';

  @override
  String get newChannelHandle => 'Handle';

  @override
  String get newChannelHandleRule =>
      '3-32 characters: a-z, 0-9, underscore or dot';

  @override
  String get newChannelCategory => 'Category';

  @override
  String get newChannelRestrictSaving => 'Restrict saving';

  @override
  String get newChannelRestrictNote =>
      'Asks readers’ apps not to save or forward posts. A request, not a guarantee — anyone who can read a post can photograph it.';

  @override
  String get newChannelPrivateBody =>
      'Reachable only with an invite link. The name is uploaded encrypted, so the server stores a channel it cannot name.';

  @override
  String get newChannelPublicBody =>
      'Listed and searchable. The name, handle and description are public by definition; the posts stay end-to-end encrypted.';

  @override
  String get membersCouldNotLift => 'Could not lift that.';

  @override
  String get membersCouldNotChange => 'Could not change that member';

  @override
  String get membersTitle => 'Members';

  @override
  String get membersWhoRuns => 'Who runs this channel';

  @override
  String get membersSilencedCanRead => 'Can read, cannot post or react';

  @override
  String get membersAllowAgain => 'Allow again';

  @override
  String get membersRoleAndPermissions => 'Role and permissions';

  @override
  String get membersOwnerEverything => 'Owner · everything';

  @override
  String get membersSubscriberReadOnly => 'Subscriber · read only';

  @override
  String get membersGrantPost => 'post';

  @override
  String get membersGrantEdit => 'edit';

  @override
  String get membersGrantDeletePosts => 'delete posts';

  @override
  String get membersGrantManageMembers => 'manage members';

  @override
  String get membersGrantDeleteChannel => 'delete channel';

  @override
  String membersRoleLine(String role, String granted) {
    return '$role · $granted';
  }

  @override
  String get membersSubscriber => 'Subscriber';

  @override
  String get membersTogglePost => 'Post';

  @override
  String get membersToggleEditChannel => 'Edit the channel';

  @override
  String get membersToggleDeletePosts => 'Delete posts';

  @override
  String get membersToggleManageMembers => 'Manage members';

  @override
  String get membersToggleDeleteChannel => 'Delete the channel';

  @override
  String get membersGreyedOutNote =>
      'Greyed-out permissions are ones you do not hold yourself. Nobody can hand out more than they have.';

  @override
  String get membersSubscriberNote =>
      'A subscriber reads the channel and nothing else.';

  @override
  String get membersRemoveFromChannel => 'Remove from channel';

  @override
  String get membersStoppedFromPosting => 'Stopped from posting';

  @override
  String get membersAudienceNote =>
      'Only the people who run this channel are listed. Who reads it is not shown to other readers — including you.';

  @override
  String get channelPicture => 'Picture';

  @override
  String get channelLinkCopied => 'Link copied.';

  @override
  String get adminsMakeSomebodyFirst => 'Make somebody an admin first.';

  @override
  String get subscribersCouldNotAddAnybody => 'Could not add anybody.';

  @override
  String subscribersAddCount(int count) {
    return 'Add $count';
  }

  @override
  String get threadCouldNotPost => 'Could not post that comment.';

  @override
  String get threadCouldNotRemove => 'Could not remove that comment.';

  @override
  String threadStopTitle(String name) {
    return 'Stop $name posting?';
  }

  @override
  String get threadStopBody =>
      'They stay in the channel and can go on reading it. They cannot comment or react until you undo this.\n\nRemoving them from the channel is the other, heavier thing: that rotates the key and takes their reading with it.';

  @override
  String get threadStopThem => 'Stop them';

  @override
  String get threadStopThemPosting => 'Stop them posting';

  @override
  String get threadCouldNotDoThat => 'Could not do that.';

  @override
  String get threadTitle => 'Comments';

  @override
  String get threadUnknown => 'Unknown';

  @override
  String get threadEncryptedNoKey =>
      'Encrypted — this device has no key for it.';

  @override
  String get threadCommentHint => 'Comment';

  @override
  String get threadNoKeyForChannel => 'No key for this channel';

  @override
  String get threadDeletedAccount => 'Deleted account';

  @override
  String get threadEncryptedNoKeyHere =>
      'Encrypted — no key for it on this device.';

  @override
  String get threadEmptyTitle => 'No comments yet';

  @override
  String get threadEmptyBody =>
      'Comments are encrypted with the channel key, like the posts. The server stores them and cannot read them.';

  @override
  String threadStoppedToast(String name) {
    return '$name can still read the channel, but not post in it.';
  }

  @override
  String get threadThem => 'They';

  @override
  String get threadThemObject => 'them';

  @override
  String get feedCouldNotAskForKey => 'Could not ask for the key.';

  @override
  String get feedKeyArrived => 'The key arrived. You can post again.';

  @override
  String get feedAskedAgain =>
      'Asked again. The key is delivered by another member, so it arrives when one of them is online.';

  @override
  String get feedCouldNotJoin => 'Could not join';

  @override
  String get feedPickFutureTime => 'Pick a time that has not gone yet.';

  @override
  String get feedCouldNotPublishPoll => 'Could not publish that poll.';

  @override
  String feedScheduledFor(String when) {
    return 'Scheduled for $when. It is under \"Scheduled\" until then.';
  }

  @override
  String get feedCouldNotPublish => 'Could not publish';

  @override
  String get feedCouldNotChangeLink => 'Could not change the link.';

  @override
  String get feedOldLinkDead =>
      'The old link is dead. Anyone holding it will need the new one.';

  @override
  String get feedSaved => 'Saved.';

  @override
  String get feedCouldNotChangeReactions => 'Could not change the reactions.';

  @override
  String get feedCouldNotChangePost => 'Could not change the post.';

  @override
  String get feedPublished => 'Published.';

  @override
  String get feedCouldNotPublishIt => 'Could not publish it.';

  @override
  String get feedCouldNotChangeThat => 'Could not change that.';

  @override
  String get feedCommentsOn => 'Readers can comment on posts now.';

  @override
  String get feedCommentsOff =>
      'Comments are off. Existing threads are hidden, not deleted.';

  @override
  String get feedCouldNotReadNumbers => 'Could not read the numbers.';

  @override
  String get feedNobodyToHandTo =>
      'There is nobody else in this channel to hand it to.';

  @override
  String feedOwnsNow(String name) {
    return '$name owns this channel now. You are an admin in it.';
  }

  @override
  String get feedCouldNotHandOn => 'Could not hand the channel on.';

  @override
  String get feedReported => 'Reported. Thank you.';

  @override
  String get feedCouldNotSendThat => 'Could not send that.';

  @override
  String get feedRemovePicture => 'Remove picture';

  @override
  String get feedPictureRemoved => 'Picture removed.';

  @override
  String get feedCouldNotRemovePicture => 'Could not remove the picture.';

  @override
  String get feedCouldNotSetPicture => 'Could not set the picture.';

  @override
  String get feedPictureUpdated => 'Channel picture updated.';

  @override
  String get feedDeleteChannelTitle => 'Delete channel?';

  @override
  String get feedDeleteChannelBody =>
      'The channel and every post in it are removed for everyone. Nothing undoes this.';

  @override
  String get feedCouldNotDeleteChannel => 'Could not delete the channel';

  @override
  String get feedCouldNotLeaveChannel => 'Could not leave the channel';

  @override
  String get feedScheduled => 'Scheduled';

  @override
  String get feedRequestsToJoin => 'Requests to join';

  @override
  String get feedChannelPicture => 'Channel picture';

  @override
  String get feedAddPicture => 'Add a picture';

  @override
  String get feedTurnCommentsOff => 'Turn comments off';

  @override
  String get feedTurnCommentsOn => 'Turn comments on';

  @override
  String get feedHandChannelOn => 'Hand this channel on';

  @override
  String get feedDeleteChannel => 'Delete channel';

  @override
  String get dayToday => 'Today';

  @override
  String get dayYesterday => 'Yesterday';

  @override
  String get feedNoSearchResultsBody =>
      'The search runs on this device, over the posts it has already loaded and could open. The server cannot search them: it holds them sealed.';

  @override
  String get feedEdited => '· edited';

  @override
  String feedCommentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comments',
      one: '1 comment',
      zero: 'Comment',
    );
    return '$_temp0';
  }

  @override
  String get feedUnpin => 'Unpin';

  @override
  String get feedPin => 'Pin';

  @override
  String get feedRemoveFile => 'Remove the file';

  @override
  String get feedAttach => 'Attach a picture or a file';

  @override
  String get feedPublishLater => 'Publish later';

  @override
  String get feedAskQuestion => 'Ask a question';

  @override
  String get feedWritePost => 'Write a post';

  @override
  String get feedEditPost => 'Edit post';

  @override
  String get feedPost => 'Post';

  @override
  String get feedEditUnseenNote =>
      'Nobody has seen this yet, so it will not be marked as edited.';

  @override
  String get feedEditSeenNote =>
      'The post will be marked as edited. Its file, if it has one, stays as it is.';

  @override
  String get feedWaiting => 'Waiting';

  @override
  String get feedEncryptedNoKeyHere => 'Encrypted — no key on this device.';

  @override
  String get feedDiscard => 'Discard';

  @override
  String get feedPublishNow => 'Publish now';

  @override
  String get feedNothingWaiting => 'Nothing waiting';

  @override
  String get feedNothingWaitingBody =>
      'Posts you schedule wait here until their time comes. Nobody else can see them, or that they exist.';

  @override
  String feedTodayAt(String time) {
    return 'today at $time';
  }

  @override
  String feedTomorrowAt(String time) {
    return 'tomorrow at $time';
  }

  @override
  String feedDateAt(String date, String time) {
    return '$date at $time';
  }

  @override
  String get feedReactionsNote =>
      'What readers can put under a post. Reactions already on a post stay, even if you take the emoji off this list.';

  @override
  String feedChosenOfLimit(int chosen, int limit) {
    return '$chosen of $limit';
  }

  @override
  String get feedPollNoKey => 'A poll this device has no key for.';

  @override
  String feedPollPickUpTo(int count) {
    return 'Pick up to $count';
  }

  @override
  String get feedPollPickOne => 'Pick one';

  @override
  String feedPollCloses(String when) {
    return 'closes $when';
  }

  @override
  String feedPollVoters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voters',
      one: '1 voter',
    );
    return '$_temp0';
  }

  @override
  String get feedPollClearAnswer => 'Clear my answer';

  @override
  String get feedPollAnswer => 'Answer';

  @override
  String get feedPollQuestion => 'Question';

  @override
  String feedPollAnswerN(int index) {
    return 'Answer $index';
  }

  @override
  String get feedPollAddAnswer => 'Add an answer';

  @override
  String get feedPollSeveral => 'Several answers';

  @override
  String get feedPollNote =>
      'The question and the answers are encrypted with the channel key, like a post. The server counts the votes without ever learning what any of them say.';

  @override
  String get feedPollAsk => 'Ask';

  @override
  String get feedCouldNotOpenFile => 'Could not open that file.';

  @override
  String get feedOpened => 'Opened';

  @override
  String get statsPosts => 'Posts';

  @override
  String get statsWaitingToPublish => 'Waiting to publish';

  @override
  String get statsPeopleWhoVoted => 'People who voted';

  @override
  String get statsWaitingToJoin => 'Waiting to join';

  @override
  String get statsNoViewCountNote =>
      'There is no view count, and that is a decision rather than a gap. Counting who has read a post — without counting anybody twice — means keeping a row for every reader of every post, which is a record of what each person read. Everything above is counted from something somebody chose to do.';

  @override
  String get feedPollClosed => 'closed';

  @override
  String get inviteNever => 'Never';

  @override
  String inviteExpires(String when) {
    return 'expires $when';
  }

  @override
  String requestsAsked(String when) {
    return 'Asked $when';
  }

  @override
  String get inviteAskMeFirst => 'Ask me first';

  @override
  String get inviteAskMeFirstNote =>
      'People who follow the link wait for your approval instead of walking in. They hold no key until you let them in.';

  @override
  String get inviteExpiresLabel => 'Expires';

  @override
  String get invitePickATime => 'Pick a time';

  @override
  String get inviteHowMany => 'How many can join on it';

  @override
  String get inviteNoLimit => 'No limit';

  @override
  String inviteJoinedSoFar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count have joined on this link so far.',
      one: '1 person has joined on this link so far.',
    );
    return '$_temp0 Opening it and walking away does not count.';
  }

  @override
  String get inviteReplaceLink => 'Replace the link';

  @override
  String get inviteReplaceNote =>
      'Replacing is how a link is revoked: the old one stops working at once, everywhere. There is no half-working link left behind.';

  @override
  String get inviteReplaceTitle => 'Replace the link?';

  @override
  String get inviteReplaceBody =>
      'The link you have shared stops working immediately — in messages, on posters, wherever it was pasted. Nobody holding it can join.\n\nPeople already in the channel stay in. There is no way to bring the old link back.';

  @override
  String get inviteReplaceIt => 'Replace it';

  @override
  String get inviteExpired => 'This link has expired — nobody can join on it.';

  @override
  String get inviteUsedUp => 'This link has been used up.';

  @override
  String get inviteNeedsApproval => 'Joining needs your approval';

  @override
  String get inviteOpenJoin => 'Anyone with it joins straight away';

  @override
  String inviteUsedOf(int used, int max) {
    return '$used of $max used';
  }

  @override
  String get inviteShareNote =>
      'Share this anywhere — it carries no key. Whoever opens it joins the channel, and the key to read it is sent to their device afterwards, encrypted, by someone who already has it.';

  @override
  String get requestsNobodyWaiting => 'Nobody waiting';

  @override
  String get requestsNobodyWaitingBody =>
      'People who follow the invite link appear here while the link is set to ask you first.';

  @override
  String get requestsNo => 'No';

  @override
  String get requestsLetIn => 'Let in';

  @override
  String get feedSettings => 'Settings';

  @override
  String feedKeyRotating(int epoch) {
    return 'Someone left this channel, so it is changing its key (version $epoch). Posts from before are still readable. New ones open once the new key reaches this device.';
  }

  @override
  String get feedWaitingForKey =>
      'Waiting for the key. It is sent to this device, encrypted, by someone already in the channel — the server never holds it.';

  @override
  String get feedJoinNote =>
      'Joining gets you the posts. The key that opens them is sent to your device afterwards by a member, never by the server.';

  @override
  String get feedJoinChannel => 'Join channel';

  @override
  String get feedNoPostsYet => 'No posts yet';

  @override
  String get feedPickNewOwnerNote =>
      'Only somebody already in the channel. Handing it to a stranger would put them in charge of a key they do not hold.';

  @override
  String feedTransferTitle(String name) {
    return 'Give the channel to $name?';
  }

  @override
  String get feedTransferBody =>
      'They will own it. You stay on as an admin with everything you have now except the right to delete the channel — and they can remove you afterwards.\n\nYou cannot undo this yourself. That is why it asks for your password rather than trusting an unlocked phone.';

  @override
  String get feedYourPrivioPassword => 'Your Privio password';

  @override
  String get feedHandItOn => 'Hand it on';

  @override
  String get feedReportTitle => 'Report this channel';

  @override
  String get feedReportPublicNote =>
      'The report carries this channel and the reason you pick. Whoever runs the server can see a public channel\'s name and description, because those are how it is searched for — but not its posts, which are encrypted.';

  @override
  String get feedReportPrivateNote =>
      'The report carries this channel and the reason you pick, and nothing else. Its name and its posts are encrypted, so whoever runs the server cannot read them. That is the honest limit of what reporting a private channel does.';

  @override
  String get feedReportNoMessageNote =>
      'There is no message box on purpose: it would be the one place in Privio where somebody pastes the encrypted thing they are reporting into a field the server can read.';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportAbuse => 'Abuse or harassment';

  @override
  String get reportIllegal => 'Illegal content';

  @override
  String get reportImpersonation => 'Pretending to be someone else';

  @override
  String get reportOther => 'Something else';

  @override
  String get feedReactionLimit => 'Reactions';

  @override
  String get failureUnreachable => 'Could not reach Privio.';

  @override
  String get failureUnreachableCheckConnection =>
      'Could not reach Privio. Check your connection.';

  @override
  String get failureUnreachableTryAgain =>
      'Could not reach Privio. Check your connection and try again.';

  @override
  String get failureCouldNotSave =>
      'Could not save that. Check your connection.';

  @override
  String get failureChangeNotSaved =>
      'Could not reach Privio. The change has not been saved.';

  @override
  String get failureRateLimited => 'Too many requests. Wait a moment.';

  @override
  String get failureTooManyAttempts => 'Too many attempts. Wait a few minutes.';

  @override
  String get failureLicenseRequired =>
      'Activate your license to send messages.';

  @override
  String get failureIdentityChanged =>
      'The safety number changed. Nothing was sent — check it before you do.';

  @override
  String get failureCouldNotSendMessage => 'Could not send message';

  @override
  String get failureCouldNotSendFile => 'Could not send file';

  @override
  String get failureCouldNotReadMessage => 'Could not read a message';

  @override
  String failureMessagesUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages could not be read',
      one: 'A message could not be read',
    );
    return '$_temp0';
  }

  @override
  String get failureCouldNotOpenFile => 'Could not open that file.';

  @override
  String get failureNotAnImage => 'That file is not an image Privio can use.';

  @override
  String get failureCouldNotSetPicture => 'Could not set the picture';

  @override
  String get failureDeletedHereOnly =>
      'Deleted here. The request to delete it there did not go out.';

  @override
  String get failureCouldNotCreateGroup => 'Could not create the group';

  @override
  String get failureNotAGroupLink =>
      'That does not look like a Privio group link.';

  @override
  String get failureGroupNotFound =>
      'That group does not exist, or the link is wrong.';

  @override
  String get failureGroupKeyMissing =>
      'This device does not have the group key yet.';

  @override
  String get failureNotAChannelLink =>
      'That does not look like a Privio channel link.';

  @override
  String get failureHandleTaken => 'That handle is already in use.';

  @override
  String get failureChannelNotFound =>
      'That channel does not exist, or the link is wrong.';

  @override
  String get failureNotAMember => 'You are not in this channel.';

  @override
  String get failureInsufficientPermission =>
      'You do not have permission to do that.';

  @override
  String get failureCannotChangeOwnRole => 'You cannot change your own role.';

  @override
  String get failureOwnerIsFixed =>
      'The channel owner cannot be changed or removed.';

  @override
  String get failureTargetOutranksYou =>
      'That member holds permissions you do not.';

  @override
  String get failureCannotGrantWhatYouLack =>
      'You cannot grant a permission you do not hold yourself.';

  @override
  String get failureOwnerCannotLeave =>
      'Hand the channel over or delete it instead.';

  @override
  String get failureUsernameTaken => 'That username is already taken.';

  @override
  String get failureInvalidCredentials => 'Username or password is incorrect.';

  @override
  String get failureTotpRequired => 'Enter your two-factor code.';

  @override
  String get failureInvalidTwoFactorCode =>
      'That two-factor code is not right.';

  @override
  String get failureTooManyDevices =>
      'This account already has the maximum number of devices.';

  @override
  String failureCheckUsernameAndPassword(String detail) {
    return 'Check the username and password: $detail';
  }

  @override
  String get failureInvalidTotp =>
      'That code is not right. Check the clock on your phone and try again.';

  @override
  String get failureTotpAlreadyEnabled =>
      'Two-factor is already on for this account.';

  @override
  String get failureTotpNotSetUp =>
      'Start the setup again — the secret is gone.';

  @override
  String get failureInvalidPassword => 'That password is not right.';

  @override
  String get failureDuressMatchesPassword =>
      'The duress code has to be different from your password, or an ordinary sign-in would destroy the account.';

  @override
  String get failureDeviceNotFound => 'That device is already signed out.';

  @override
  String get failureCouldNotLiftBlock => 'Could not lift that block.';

  @override
  String failureLicenseKeyIncomplete(String format) {
    return 'That key is not complete. It looks like $format.';
  }

  @override
  String get failureNotALicenseKey =>
      'That does not look like a Privio license key.';

  @override
  String get failureLicenseNotFound =>
      'No license matches that key. Check it and try again.';

  @override
  String get failureLicenseAlreadyRedeemed =>
      'That key has already been used by another account. A key can only be redeemed once.';

  @override
  String get failureLicenseRevoked =>
      'That license was revoked. Contact support if you paid for it.';

  @override
  String get failureAccountAlreadyLicensed =>
      'This account already has a license, so the key you entered has not been used.';

  @override
  String get failureNoPlayServices =>
      'This phone has no Google Play services, so Privio cannot be woken while it is closed. Messages arrive while Privio is open.';

  @override
  String get failureNoApnsToken =>
      'iOS did not issue a push token for Privio, so it cannot be woken while it is closed. Messages arrive while Privio is open.';

  @override
  String get failureNoPushService =>
      'No push service answered. Messages arrive while Privio is open.';

  @override
  String get failureNoDistributor =>
      'No UnifiedPush distributor answered. Install one — ntfy, for example — and try again.';

  @override
  String get failureDistributorUnreachable =>
      'Privio cannot reach that distributor. It has to be an https address on the public internet.';

  @override
  String get failureChannelKeyAwaitingGeneration =>
      'This channel is changing its key after a member left. You can post again once someone who manages the channel opens Privio.';

  @override
  String get failureChannelKeyPending =>
      'Waiting for the new channel key to reach this device. Your post is not lost — try again in a moment.';

  @override
  String get failureUnexpected =>
      'Something did not work as expected. Try again.';

  @override
  String get failureCallDevicesUnavailable =>
      'Privio could not open the camera or microphone.';

  @override
  String get failureCallMicrophoneUnavailable =>
      'Privio could not open the microphone.';

  @override
  String get failureCallNotOpen => 'The call was not open.';

  @override
  String get deepLinkChannelGone =>
      'That link does not point at a channel any more. Ask whoever sent it for a new one.';

  @override
  String get chatsPreviewDeleted => 'Message deleted';

  @override
  String get chatsPreviewPhoto => 'Photo';

  @override
  String get chatsPreviewVideo => 'Video';

  @override
  String get chatsPreviewVoice => 'Voice message';

  @override
  String get chatsPreviewFile => 'File';

  @override
  String get notificationsPermissionDenied =>
      'Notifications are turned off for Privio in your system settings. Messages still arrive while Privio is open — you will not be told about them, and a call will not ring.';

  @override
  String get notificationsPermissionNotAsked =>
      'Privio has not been allowed to notify you yet.';

  @override
  String get failureCallMediaNotEncrypted =>
      'The call was ended: the other side asked for a connection Privio cannot encrypt. Privio never falls back to an unencrypted call.';

  @override
  String get failureCallFarEndNotBound =>
      'The call was ended: nothing in the setup proved who was at the other end. Privio does not connect a call it cannot tie to a key.';

  @override
  String get failureCallCertificateChanged =>
      'The call was ended: the other end changed midway through. A call has one other end, and this one had two.';

  @override
  String failureCallIdentityChanged(String who) {
    return 'The call was ended: the security number for $who is not the one Privio had. Compare it with them on another channel before calling again.';
  }

  @override
  String get failureCallWrongParty =>
      'The call was ended: a message about it came from someone who is not on it.';

  @override
  String failureCallNotVerified(String who) {
    return 'The call was ended: you only take calls from people whose security number you have confirmed, and $who\'s is not confirmed on this device.';
  }

  @override
  String get callEncrypted => 'End-to-end encrypted';

  @override
  String get callEncryptedVerified => 'End-to-end encrypted · verified';

  @override
  String get securityVerifiedCallsOnly => 'Only calls from verified contacts';

  @override
  String get securityVerifiedCallsOnlyBody =>
      'Every call is end-to-end encrypted either way. With this on, Privio also refuses a call unless you have compared the security number with that person and marked it confirmed — so a key this device merely met first is not enough. Calls from anyone else end with an explanation, on both sides.';

  @override
  String get privacyCalls => 'Calls';

  @override
  String get appearanceAccentColour => 'Accent colour';

  @override
  String get appearanceAccentNote =>
      'This changes how Privio looks on this device, for this account. Nobody you write to sees it, and your other accounts keep their own. Red, for deleting and hanging up, stays red whichever accent you pick.';

  @override
  String get accentGreen => 'Green';

  @override
  String get accentBlue => 'Blue';

  @override
  String get accentTeal => 'Turquoise';

  @override
  String get accentPurple => 'Violet';

  @override
  String get accentPink => 'Pink';

  @override
  String get accentRed => 'Red';

  @override
  String get accentOrange => 'Orange';

  @override
  String get accentYellow => 'Yellow';

  @override
  String get accentPrivioDefault => 'Privio default';

  @override
  String get appearanceAccentReset => 'Reset to default';

  @override
  String get appearanceAccentPreview => 'Preview';

  @override
  String get appearancePreviewSend => 'Send';

  @override
  String get appearancePreviewSetting => 'Read receipts';

  @override
  String get appearancePreviewMessage =>
      'This is what your own messages will look like.';

  @override
  String accentSelected(String colour) {
    return '$colour, selected';
  }

  @override
  String get appearanceAppIcon => 'App icon';

  @override
  String get appearanceAppIconNote =>
      'This is the icon on your home screen, and it belongs to this phone rather than to your account: signing in as somebody else does not change it. It stays as you set it when you pick a different accent colour.';

  @override
  String get appearanceAppIconMatchAccent => 'Use the current accent colour';

  @override
  String get appearanceAppIconReset => 'Restore the original icon';

  @override
  String get appearanceAppIconSlow =>
      'The home screen can take a few seconds to redraw. That wait belongs to the launcher, not to Privio.';

  @override
  String get appearanceAppIconUnavailable =>
      'This device cannot change the app icon, so Privio does not offer to.';

  @override
  String get appearanceAppIconOriginal => 'Original';

  @override
  String get failureAppIconUnsupported =>
      'The app icon could not be changed: this device does not offer it.';

  @override
  String get failureAppIconHiddenByDisguise =>
      'The home screen is showing the calculator while the disguise is on, so the icon colour has not been changed. Switch the disguise off first.';

  @override
  String appIconSelected(String colour) {
    return '$colour icon, selected';
  }

  @override
  String appIconChoose(String colour) {
    return '$colour icon';
  }

  @override
  String get failureStickerNotAnImage =>
      'That file is not a PNG or a WebP image.';

  @override
  String get failureStickerAnimated =>
      'Animated stickers are not supported yet. Use a still PNG or WebP.';

  @override
  String failureStickerTooLarge(int limit) {
    return 'A sticker has to be smaller than $limit KB.';
  }

  @override
  String failureStickerTooWide(int limit) {
    return 'A sticker can be at most $limit×$limit pixels.';
  }

  @override
  String failureStickerTooSmall(int limit) {
    return 'A sticker has to be at least $limit×$limit pixels.';
  }

  @override
  String get failureStickerPackFull =>
      'This pack is full. Remove something to make room.';

  @override
  String get failureStickerTooManyPacks =>
      'You have as many packs as Privio holds. Delete one to make another.';

  @override
  String get failureStickerPackNotFound => 'That pack is no longer there.';

  @override
  String get failureStickerLinkDead =>
      'This link no longer opens anything: it was withdrawn, or the pack was deleted.';

  @override
  String get settingsStickers => 'Stickers & Emoji';

  @override
  String get stickersTitle => 'Stickers & Emoji';

  @override
  String get stickersMyPacks => 'My packs';

  @override
  String get stickersInstalled => 'Added';

  @override
  String get stickersEmptyTitle => 'No packs yet';

  @override
  String get stickersEmptyBody =>
      'Make a pack from your own pictures, or open a link somebody sent you.';

  @override
  String get stickersNewPack => 'New pack';

  @override
  String get stickersNewStickerPack => 'Sticker pack';

  @override
  String get stickersNewEmojiPack => 'Emoji pack';

  @override
  String get stickersNameLabel => 'Name';

  @override
  String get stickersNameHint => 'What this pack is called';

  @override
  String get stickersCreate => 'Create';

  @override
  String get stickersRename => 'Rename';

  @override
  String get stickersDelete => 'Delete pack';

  @override
  String stickersDeleteConfirm(String title) {
    return 'Delete “$title”?';
  }

  @override
  String get stickersDeleteExplain =>
      'The link stops working and the pack leaves your picker. Stickers from it that you have already sent stay readable in those conversations.';

  @override
  String get stickersRemovePack => 'Remove from my packs';

  @override
  String get stickersAddPack => 'Add pack';

  @override
  String get stickersAlreadyAdded => 'Already in your packs';

  @override
  String get stickersShare => 'Share this pack';

  @override
  String get stickersSharedOn => 'Anyone with the link can add it';

  @override
  String get stickersSharedOff => 'Private. Only you can see it.';

  @override
  String get stickersShareExplain =>
      'A pack is private until you share it. Sticker pictures are not encrypted: a link is meant for people who hold no key of yours, so anyone who has the link — and this server — can see them. Withdrawing the link stops new people adding the pack; it does not take it back from people who already have it.';

  @override
  String get stickersCopyLink => 'Copy link';

  @override
  String get stickersLinkCopied => 'Link copied';

  @override
  String get stickersWithdrawLink => 'Withdraw the link';

  @override
  String get stickersNewLinkNote =>
      'Sharing again makes a new link and stops the old one.';

  @override
  String get stickersAddItem => 'Add a picture';

  @override
  String get stickersItemEmoji => 'Emoji for this one';

  @override
  String get stickersItemEmojiWhy =>
      'What it stands for: what a client without this pack shows in its place, and how you find it later.';

  @override
  String get stickersEmptyPack => 'Nothing in this pack yet.';

  @override
  String stickersItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pictures',
      one: '1 picture',
      zero: 'Empty',
    );
    return '$_temp0';
  }

  @override
  String get stickersRemoveItem => 'Remove';

  @override
  String get stickersReorderHint => 'Hold and drag to reorder.';

  @override
  String get stickersCropTitle => 'Crop';

  @override
  String get stickersCropHint =>
      'Drag and pinch to choose the square. Transparency is kept.';

  @override
  String get stickersUse => 'Use';

  @override
  String get stickersPreviewTitle => 'Sticker pack';

  @override
  String get stickersOpenLinkTitle => 'Open a pack link';

  @override
  String get stickersOpenLinkHint =>
      'Paste the link or the code somebody sent you.';

  @override
  String get stickersOpen => 'Open';

  @override
  String get stickersKindSticker => 'Stickers';

  @override
  String get stickersKindEmoji => 'Custom emoji';

  @override
  String get stickersPickFailed => 'That picture could not be opened.';

  @override
  String get notificationsIphoneNote =>
      'You can manage notifications for Privio in iPhone Settings.';

  @override
  String get notificationsOpenIphoneSettings => 'Open iPhone Settings';

  @override
  String get notificationsSettingsFailed =>
      'Could not open Settings. Open the Settings app and select Privio.';

  @override
  String get pickerEmoji => 'Emoji';

  @override
  String get pickerStickers => 'Stickers';

  @override
  String get pickerMine => 'Mine';

  @override
  String get pickerFavourites => 'Favourites';

  @override
  String get pickerRecent => 'Recently used';

  @override
  String get pickerNoStickers => 'No sticker packs yet.';

  @override
  String get pickerNoCustomEmoji => 'No custom emoji yet.';

  @override
  String get pickerManagePacks => 'Manage packs';

  @override
  String get pickerAddFavourite => 'Add to favourites';

  @override
  String get pickerRemoveFavourite => 'Remove from favourites';

  @override
  String get pickerOpenPack => 'Open pack';

  @override
  String stickerFromPack(String title) {
    return 'Sticker from “$title”';
  }

  @override
  String get stickerPackGone => 'This pack is not available to you.';

  @override
  String get chatSticker => 'Sticker';

  @override
  String get pickerOpenTooltip => 'Stickers and emoji';

  @override
  String get failurePhoneInvalid =>
      'That is not a phone number Privio can use. Include the country code, like +49.';

  @override
  String get failurePhoneSmsUnavailable =>
      'This server cannot send text messages yet, so a number cannot be verified here. You can keep using Privio without one.';

  @override
  String get failurePhoneDiscoveryUnavailable =>
      'This server has contact discovery switched off.';

  @override
  String get failurePhoneWrongCode => 'That code is not right.';

  @override
  String get failurePhoneCodeExpired =>
      'That code has expired. Ask for a new one.';

  @override
  String get failurePhoneTooManyAttempts =>
      'Too many wrong codes. Ask for a new one.';

  @override
  String get failurePhoneTooManySends =>
      'Privio has sent that code as many times as it will. Try again later.';

  @override
  String get failurePhoneResendTooSoon =>
      'Wait a moment before asking for another code.';

  @override
  String get failurePhoneNoVerification => 'Ask for a code first.';

  @override
  String get failurePhoneUnchanged =>
      'That number is already verified on this account.';

  @override
  String get failurePhoneNotLinked =>
      'There is no verified number on this account.';

  @override
  String get failurePhoneLookupBudgetSpent =>
      'Privio has matched as many numbers for this account today as it will. Try again tomorrow.';

  @override
  String get failureContactsPermissionDenied =>
      'Privio has no access to your contacts. You can still add people by their PRIVIO ID or an invite link.';

  @override
  String get channelVerifiedTooltip => 'Official Privio channel';

  @override
  String get phoneFieldLabel => 'Phone number (optional)';

  @override
  String get phoneFieldHint => 'Phone number (optional)';

  @override
  String get phoneFieldExplain =>
      'Link your phone number so contacts can find you. You can use PRIVIO without a phone number too.';

  @override
  String get phoneCountryCode => 'Country code';

  @override
  String get phoneVerifyTitle => 'Confirm your number';

  @override
  String phoneVerifySent(String hint) {
    return 'We sent a code to $hint.';
  }

  @override
  String get phoneVerifyCode => 'Six-digit code';

  @override
  String get phoneVerifyConfirm => 'Confirm';

  @override
  String get phoneVerifyResend => 'Send a new code';

  @override
  String get phoneVerifySkip => 'Continue without a number';

  @override
  String phoneVerifyStub(String code) {
    return 'Development server: no text message was sent. The code is $code.';
  }

  @override
  String get privacyPhoneSection => 'Phone number & contacts';

  @override
  String get phoneAdd => 'Add a phone number';

  @override
  String get phoneChange => 'Change number';

  @override
  String get phoneRemove => 'Remove number';

  @override
  String get phoneRemoveExplain =>
      'The number and the link the server keeps for finding you are both deleted. Your chats are untouched.';

  @override
  String get phoneDiscoverable => 'Be found by my phone number';

  @override
  String get phoneDiscoverableExplain =>
      'Off unless you switch it on. When it is on, somebody who has your number in their contacts sees your PRIVIO account.';

  @override
  String get phoneContactSync => 'Sync device contacts';

  @override
  String get phoneContactSyncExplain =>
      'Off unless you switch it on. PRIVIO reads the phone numbers in your contacts, turns each one into an unreadable value on this device, and asks the server which of them belong to a PRIVIO account. Names, notes and the address book itself are never sent and never stored on the server.';

  @override
  String get phoneSyncNow => 'Match contacts now';

  @override
  String phoneSyncFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count people.',
      one: 'Found 1 person.',
      zero:
          'Nobody from your contacts is on PRIVIO, or nobody has switched on being found.',
    );
    return '$_temp0';
  }

  @override
  String get phoneImportedRemove => 'Remove imported contacts';

  @override
  String get phoneImportedRemoveExplain =>
      'Removes the people matching added, and nothing else. Your chats with them stay.';

  @override
  String get phoneNotLinkedYet => 'No number linked';
}
