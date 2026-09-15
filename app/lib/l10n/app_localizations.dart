import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppText
/// returned by `AppText.of(context)`.
///
/// Applications need to include `AppText.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppText.localizationsDelegates,
///   supportedLocales: AppText.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppText.supportedLocales
/// property.
abstract class AppText {
  AppText(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;
  String get proxyTitle;
  String get proxyEnable;
  String get proxyHost;
  String get proxyPort;
  String get proxyUsername;
  String get proxyPassword;
  String get proxyScope;
  String get proxyPrivacy;
  String get proxyTest;
  String get proxySave;
  String get proxyRemove;
  String get proxyInvalid;
  String get proxyTestSuccess;
  String get proxySaved;
  String get proxyFailed;
  String get proxyCallsBlocked;

  static AppText of(BuildContext context) {
    return Localizations.of<AppText>(context, AppText)!;
  }

  static const LocalizationsDelegate<AppText> delegate = _AppTextDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
  ];

  /// The settings row that opens the language picker.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageName;

  /// No description provided for @languagePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languagePickerTitle;

  /// No description provided for @languagePickerNote.
  ///
  /// In en, this message translates to:
  /// **'The interface changes straight away. Messages, channel names and anything else people wrote stay in the language they were written in.'**
  String get languagePickerNote;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonRetry;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get commonSkip;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'Alright'**
  String get commonOk;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied.'**
  String get commonCopied;

  /// No description provided for @commonShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @commonSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get commonSomethingWentWrong;

  /// No description provided for @commonNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get commonNotNow;

  /// No description provided for @commonOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get commonOn;

  /// No description provided for @commonOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get commonOff;

  /// No description provided for @commonDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get commonDefault;

  /// No description provided for @commonCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get commonCustom;

  /// No description provided for @commonUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get commonUnavailable;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @disappearingTitle.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages'**
  String get disappearingTitle;

  /// No description provided for @disappearingExplainer.
  ///
  /// In en, this message translates to:
  /// **'New messages are deleted automatically after this long. The timer starts when the message is sent.'**
  String get disappearingExplainer;

  /// No description provided for @disappearingCoversChat.
  ///
  /// In en, this message translates to:
  /// **'It covers text, photos, files and voice messages, and applies to this chat only. Messages already sent are not affected, and both of you are told when it changes.'**
  String get disappearingCoversChat;

  /// No description provided for @disappearingCoversGroup.
  ///
  /// In en, this message translates to:
  /// **'It covers text, photos, files and voice messages, and applies to this group only. Messages already sent are not affected, everyone is told when it changes, and only an admin can change it.'**
  String get disappearingCoversGroup;

  /// No description provided for @disappearingScreenshotCaveat.
  ///
  /// In en, this message translates to:
  /// **'It cannot undo a screenshot, a photo already saved, or anything written down elsewhere.'**
  String get disappearingScreenshotCaveat;

  /// No description provided for @disappearingOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get disappearingOff;

  /// No description provided for @disappearing30Seconds.
  ///
  /// In en, this message translates to:
  /// **'30 seconds'**
  String get disappearing30Seconds;

  /// No description provided for @disappearing1Minute.
  ///
  /// In en, this message translates to:
  /// **'1 minute'**
  String get disappearing1Minute;

  /// No description provided for @disappearing5Minutes.
  ///
  /// In en, this message translates to:
  /// **'5 minutes'**
  String get disappearing5Minutes;

  /// No description provided for @disappearing1Hour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get disappearing1Hour;

  /// No description provided for @disappearing24Hours.
  ///
  /// In en, this message translates to:
  /// **'24 hours'**
  String get disappearing24Hours;

  /// No description provided for @disappearing7Days.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get disappearing7Days;

  /// No description provided for @disappearingAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'Only an admin can change this'**
  String get disappearingAdminOnly;

  /// A system line in a chat. `who` is a name or the translation of 'You'.
  ///
  /// In en, this message translates to:
  /// **'{who} set disappearing messages to {duration}'**
  String noticeTimerSetBy(String who, String duration);

  /// No description provided for @noticeTimerOffBy.
  ///
  /// In en, this message translates to:
  /// **'{who} turned disappearing messages off'**
  String noticeTimerOffBy(String who);

  /// No description provided for @noticeYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get noticeYou;

  /// No description provided for @noticeThey.
  ///
  /// In en, this message translates to:
  /// **'They'**
  String get noticeThey;

  /// No description provided for @noticeSomeone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get noticeSomeone;

  /// No description provided for @noticeMessageDeletedBy.
  ///
  /// In en, this message translates to:
  /// **'{who} deleted a message'**
  String noticeMessageDeletedBy(String who);

  /// No description provided for @noticeSafetyNumberChanged.
  ///
  /// In en, this message translates to:
  /// **'Your safety number with {who} changed'**
  String noticeSafetyNumberChanged(String who);

  /// No description provided for @noticeUnreadable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A message} other{{count} messages}} could not be read. It was sealed to a key this device no longer has.'**
  String noticeUnreadable(int count);

  /// No description provided for @noticeUnreadableFrom.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A message} other{{count} messages}} from {who} could not be read. It was sealed to a key this device no longer has.'**
  String noticeUnreadableFrom(int count, String who);

  /// No description provided for @durationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 second} other{{count} seconds}}'**
  String durationSeconds(int count);

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String durationMinutes(int count);

  /// No description provided for @durationHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String durationHours(int count);

  /// No description provided for @durationDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String durationDays(int count);

  /// No description provided for @durationWeeks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 week} other{{count} weeks}}'**
  String durationWeeks(int count);

  /// No description provided for @channelSubscribers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 subscriber} other{{count} subscribers}}'**
  String channelSubscribers(int count);

  /// No description provided for @channelMembers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String channelMembers(int count);

  /// No description provided for @channelPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get channelPublic;

  /// No description provided for @channelPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get channelPrivate;

  /// No description provided for @channelAdministrators.
  ///
  /// In en, this message translates to:
  /// **'Administrators'**
  String get channelAdministrators;

  /// No description provided for @channelSubscribersRow.
  ///
  /// In en, this message translates to:
  /// **'Subscribers'**
  String get channelSubscribersRow;

  /// No description provided for @channelSettings.
  ///
  /// In en, this message translates to:
  /// **'Channel settings'**
  String get channelSettings;

  /// No description provided for @channelShareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get channelShareLink;

  /// No description provided for @channelDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get channelDescription;

  /// No description provided for @channelMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get channelMedia;

  /// No description provided for @channelLinks.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get channelLinks;

  /// No description provided for @channelNoMedia.
  ///
  /// In en, this message translates to:
  /// **'No pictures yet'**
  String get channelNoMedia;

  /// No description provided for @channelNoLinks.
  ///
  /// In en, this message translates to:
  /// **'No links yet'**
  String get channelNoLinks;

  /// No description provided for @channelNoPosts.
  ///
  /// In en, this message translates to:
  /// **'No posts yet'**
  String get channelNoPosts;

  /// No description provided for @channelActionLivestream.
  ///
  /// In en, this message translates to:
  /// **'livestream'**
  String get channelActionLivestream;

  /// No description provided for @channelActionMute.
  ///
  /// In en, this message translates to:
  /// **'mute'**
  String get channelActionMute;

  /// No description provided for @channelActionUnmute.
  ///
  /// In en, this message translates to:
  /// **'unmute'**
  String get channelActionUnmute;

  /// No description provided for @channelActionSearch.
  ///
  /// In en, this message translates to:
  /// **'search'**
  String get channelActionSearch;

  /// No description provided for @channelActionMore.
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get channelActionMore;

  /// No description provided for @channelMuteTitle.
  ///
  /// In en, this message translates to:
  /// **'Mute this channel'**
  String get channelMuteTitle;

  /// No description provided for @channelMuteNote.
  ///
  /// In en, this message translates to:
  /// **'It stays muted on every device you are signed in on — muting it here is not \"until I pick up my laptop\".'**
  String get channelMuteNote;

  /// No description provided for @channelMuteForHour.
  ///
  /// In en, this message translates to:
  /// **'For 1 hour'**
  String get channelMuteForHour;

  /// No description provided for @channelMuteForEightHours.
  ///
  /// In en, this message translates to:
  /// **'For 8 hours'**
  String get channelMuteForEightHours;

  /// No description provided for @channelMuteForTwoDays.
  ///
  /// In en, this message translates to:
  /// **'For 2 days'**
  String get channelMuteForTwoDays;

  /// No description provided for @channelMuteUntilOff.
  ///
  /// In en, this message translates to:
  /// **'Until I turn it back on'**
  String get channelMuteUntilOff;

  /// No description provided for @channelCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get channelCopyLink;

  /// No description provided for @channelQrCode.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get channelQrCode;

  /// No description provided for @channelInviteSettings.
  ///
  /// In en, this message translates to:
  /// **'Invite settings'**
  String get channelInviteSettings;

  /// No description provided for @channelStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get channelStatistics;

  /// No description provided for @channelReport.
  ///
  /// In en, this message translates to:
  /// **'Report channel'**
  String get channelReport;

  /// No description provided for @channelLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave channel'**
  String get channelLeave;

  /// No description provided for @channelLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave this channel?'**
  String get channelLeaveTitle;

  /// No description provided for @channelLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'You stop receiving its posts. The channel moves to a new key, so nothing published after this is readable to you.'**
  String get channelLeaveBody;

  /// No description provided for @channelStay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get channelStay;

  /// No description provided for @channelNoLinkToShare.
  ///
  /// In en, this message translates to:
  /// **'This channel has no link to share.'**
  String get channelNoLinkToShare;

  /// No description provided for @channelInfo.
  ///
  /// In en, this message translates to:
  /// **'Channel info'**
  String get channelInfo;

  /// No description provided for @adminsTitle.
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get adminsTitle;

  /// No description provided for @adminsSectionHeader.
  ///
  /// In en, this message translates to:
  /// **'CHANNEL ADMINISTRATORS'**
  String get adminsSectionHeader;

  /// No description provided for @adminsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add admin'**
  String get adminsAdd;

  /// No description provided for @adminsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search admins'**
  String get adminsSearch;

  /// No description provided for @adminsRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get adminsRoleOwner;

  /// No description provided for @adminsRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get adminsRoleAdmin;

  /// No description provided for @adminsPromotedBy.
  ///
  /// In en, this message translates to:
  /// **'promoted by {who}'**
  String adminsPromotedBy(String who);

  /// No description provided for @adminsHelpOwner.
  ///
  /// In en, this message translates to:
  /// **'Administrators help you run your channel.'**
  String get adminsHelpOwner;

  /// No description provided for @adminsHelpMember.
  ///
  /// In en, this message translates to:
  /// **'Administrators help run this channel. Only somebody who may appoint admins can change this list.'**
  String get adminsHelpMember;

  /// No description provided for @adminsNobodyYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody yet.'**
  String get adminsNobodyYet;

  /// No description provided for @adminsShowSenderName.
  ///
  /// In en, this message translates to:
  /// **'Show sender name'**
  String get adminsShowSenderName;

  /// No description provided for @adminsShowSenderNameOn.
  ///
  /// In en, this message translates to:
  /// **'New posts carry the name of whoever wrote them'**
  String get adminsShowSenderNameOn;

  /// No description provided for @adminsShowSenderNameLocked.
  ///
  /// In en, this message translates to:
  /// **'Only an admin who may edit the channel can change this'**
  String get adminsShowSenderNameLocked;

  /// No description provided for @adminsShowSenderNameNote.
  ///
  /// In en, this message translates to:
  /// **'With it off, everything the channel publishes is published by the channel — no admin name is attached, and readers see one voice.'**
  String get adminsShowSenderNameNote;

  /// No description provided for @adminsTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership'**
  String get adminsTransfer;

  /// No description provided for @adminsTransferNote.
  ///
  /// In en, this message translates to:
  /// **'Asks for your password, and cannot be undone'**
  String get adminsTransferNote;

  /// No description provided for @adminsEverybodyAlready.
  ///
  /// In en, this message translates to:
  /// **'Everybody in this channel is already an admin.'**
  String get adminsEverybodyAlready;

  /// No description provided for @adminsWhoShouldBe.
  ///
  /// In en, this message translates to:
  /// **'Who should be an admin?'**
  String get adminsWhoShouldBe;

  /// No description provided for @adminsDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss as admin'**
  String get adminsDismiss;

  /// No description provided for @adminsAppoint.
  ///
  /// In en, this message translates to:
  /// **'Appoint'**
  String get adminsAppoint;

  /// No description provided for @adminsOwnerFixed.
  ///
  /// In en, this message translates to:
  /// **'The owner holds every permission, and that is not editable — not here and not on the server.'**
  String get adminsOwnerFixed;

  /// No description provided for @adminsOutranksYou.
  ///
  /// In en, this message translates to:
  /// **'They hold permissions you do not, so you cannot change what they may do.'**
  String get adminsOutranksYou;

  /// No description provided for @adminsOnlyWhatYouHold.
  ///
  /// In en, this message translates to:
  /// **'You can only hand out what you hold yourself. Anything you do not have is off and cannot be switched on.'**
  String get adminsOnlyWhatYouHold;

  /// No description provided for @adminsYouDoNotHold.
  ///
  /// In en, this message translates to:
  /// **'You do not hold this yourself'**
  String get adminsYouDoNotHold;

  /// No description provided for @adminsCouldNotChange.
  ///
  /// In en, this message translates to:
  /// **'Could not change that.'**
  String get adminsCouldNotChange;

  /// No description provided for @permissionEditChannel.
  ///
  /// In en, this message translates to:
  /// **'Edit the channel'**
  String get permissionEditChannel;

  /// No description provided for @permissionEditChannelDetail.
  ///
  /// In en, this message translates to:
  /// **'Name, picture, description and settings'**
  String get permissionEditChannelDetail;

  /// No description provided for @permissionPost.
  ///
  /// In en, this message translates to:
  /// **'Publish posts'**
  String get permissionPost;

  /// No description provided for @permissionPostDetail.
  ///
  /// In en, this message translates to:
  /// **'And edit or schedule their own'**
  String get permissionPostDetail;

  /// No description provided for @permissionDeletePosts.
  ///
  /// In en, this message translates to:
  /// **'Delete posts'**
  String get permissionDeletePosts;

  /// No description provided for @permissionDeletePostsDetail.
  ///
  /// In en, this message translates to:
  /// **'Including other people\'s'**
  String get permissionDeletePostsDetail;

  /// No description provided for @permissionModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate the discussion'**
  String get permissionModerate;

  /// No description provided for @permissionModerateDetail.
  ///
  /// In en, this message translates to:
  /// **'Remove comments and silence people'**
  String get permissionModerateDetail;

  /// No description provided for @permissionManageMembers.
  ///
  /// In en, this message translates to:
  /// **'Manage subscribers'**
  String get permissionManageMembers;

  /// No description provided for @permissionManageMembersDetail.
  ///
  /// In en, this message translates to:
  /// **'Add, remove and silence'**
  String get permissionManageMembersDetail;

  /// No description provided for @permissionManageInvites.
  ///
  /// In en, this message translates to:
  /// **'Manage invites'**
  String get permissionManageInvites;

  /// No description provided for @permissionManageInvitesDetail.
  ///
  /// In en, this message translates to:
  /// **'The link, its limits, and who is waiting'**
  String get permissionManageInvitesDetail;

  /// No description provided for @permissionManageLivestreams.
  ///
  /// In en, this message translates to:
  /// **'Manage livestreams'**
  String get permissionManageLivestreams;

  /// No description provided for @permissionManageLivestreamsDetail.
  ///
  /// In en, this message translates to:
  /// **'Start and end them'**
  String get permissionManageLivestreamsDetail;

  /// No description provided for @permissionAppointAdmins.
  ///
  /// In en, this message translates to:
  /// **'Appoint admins'**
  String get permissionAppointAdmins;

  /// No description provided for @permissionAppointAdminsDetail.
  ///
  /// In en, this message translates to:
  /// **'Hand this authority to somebody else'**
  String get permissionAppointAdminsDetail;

  /// No description provided for @subscribersTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscribers'**
  String get subscribersTitle;

  /// No description provided for @subscribersAdd.
  ///
  /// In en, this message translates to:
  /// **'Add subscribers'**
  String get subscribersAdd;

  /// No description provided for @subscribersSearch.
  ///
  /// In en, this message translates to:
  /// **'Search subscribers'**
  String get subscribersSearch;

  /// No description provided for @subscribersAdminsOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'Only channel administrators see this list.'**
  String get subscribersAdminsOnlyNote;

  /// No description provided for @subscribersPartialNote.
  ///
  /// In en, this message translates to:
  /// **'This is not the whole list. Only channel administrators can see who is subscribed — what you see here is the people running it, and you.'**
  String get subscribersPartialNote;

  /// No description provided for @subscribersCompleteNote.
  ///
  /// In en, this message translates to:
  /// **'Everybody in this channel.'**
  String get subscribersCompleteNote;

  /// No description provided for @subscribersContactsSection.
  ///
  /// In en, this message translates to:
  /// **'CONTACTS IN THIS CHANNEL'**
  String get subscribersContactsSection;

  /// No description provided for @subscribersOthersSection.
  ///
  /// In en, this message translates to:
  /// **'OTHER SUBSCRIBERS'**
  String get subscribersOthersSection;

  /// No description provided for @subscribersOnlySection.
  ///
  /// In en, this message translates to:
  /// **'SUBSCRIBERS'**
  String get subscribersOnlySection;

  /// No description provided for @subscribersNobodyFound.
  ///
  /// In en, this message translates to:
  /// **'Nobody found.'**
  String get subscribersNobodyFound;

  /// No description provided for @subscribersNoContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts to add yet.'**
  String get subscribersNoContacts;

  /// No description provided for @subscribersEverybodyHere.
  ///
  /// In en, this message translates to:
  /// **'Everybody in your contacts is already here.'**
  String get subscribersEverybodyHere;

  /// No description provided for @subscribersAddedOne.
  ///
  /// In en, this message translates to:
  /// **'Added.'**
  String get subscribersAddedOne;

  /// No description provided for @subscribersAddedMany.
  ///
  /// In en, this message translates to:
  /// **'Added {count} people.'**
  String subscribersAddedMany(int count);

  /// No description provided for @subscribersNobodyAdded.
  ///
  /// In en, this message translates to:
  /// **'Nobody could be added'**
  String get subscribersNobodyAdded;

  /// No description provided for @subscribersAddedCount.
  ///
  /// In en, this message translates to:
  /// **'Added {count}'**
  String subscribersAddedCount(int count);

  /// No description provided for @subscribersNeedInvite.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person has} other{{count} people have}} set their account so only their own contacts can add them to things. Send them the link instead and let them decide.'**
  String subscribersNeedInvite(int count);

  /// No description provided for @subscribersCopyTheLink.
  ///
  /// In en, this message translates to:
  /// **'Copy the link'**
  String get subscribersCopyTheLink;

  /// No description provided for @subscribersOwnerCannotBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'The owner cannot be removed.'**
  String get subscribersOwnerCannotBeRemoved;

  /// No description provided for @subscribersSilenced.
  ///
  /// In en, this message translates to:
  /// **'Silenced'**
  String get subscribersSilenced;

  /// No description provided for @subscribersSilence.
  ///
  /// In en, this message translates to:
  /// **'Silence them'**
  String get subscribersSilence;

  /// No description provided for @subscribersSilenceDetail.
  ///
  /// In en, this message translates to:
  /// **'They stay subscribed and stop being able to comment'**
  String get subscribersSilenceDetail;

  /// No description provided for @subscribersUnsilence.
  ///
  /// In en, this message translates to:
  /// **'Let them speak again'**
  String get subscribersUnsilence;

  /// No description provided for @subscribersUnsilenceDetail.
  ///
  /// In en, this message translates to:
  /// **'They can comment again'**
  String get subscribersUnsilenceDetail;

  /// No description provided for @subscribersRemoveFromChannel.
  ///
  /// In en, this message translates to:
  /// **'Remove from the channel'**
  String get subscribersRemoveFromChannel;

  /// No description provided for @subscribersRemoveDetail.
  ///
  /// In en, this message translates to:
  /// **'The channel moves to a new key, so they cannot read what comes next'**
  String get subscribersRemoveDetail;

  /// No description provided for @subscribersCouldNotDoThat.
  ///
  /// In en, this message translates to:
  /// **'Could not do that.'**
  String get subscribersCouldNotDoThat;

  /// No description provided for @presenceOnline.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get presenceOnline;

  /// No description provided for @presenceMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'last seen {count, plural, =1{1 minute} other{{count} minutes}} ago'**
  String presenceMinutesAgo(int count);

  /// No description provided for @presenceHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'last seen {count, plural, =1{1 hour} other{{count} hours}} ago'**
  String presenceHoursAgo(int count);

  /// No description provided for @presenceDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'last seen {count, plural, =1{1 day} other{{count} days}} ago'**
  String presenceDaysAgo(int count);

  /// No description provided for @presenceOnDate.
  ///
  /// In en, this message translates to:
  /// **'last seen {date}'**
  String presenceOnDate(String date);

  /// No description provided for @editChannelName.
  ///
  /// In en, this message translates to:
  /// **'Channel name'**
  String get editChannelName;

  /// No description provided for @editChannelDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get editChannelDescriptionHint;

  /// No description provided for @editChannelChangePicture.
  ///
  /// In en, this message translates to:
  /// **'Change picture'**
  String get editChannelChangePicture;

  /// No description provided for @editChannelChoosePicture.
  ///
  /// In en, this message translates to:
  /// **'Choose a picture'**
  String get editChannelChoosePicture;

  /// No description provided for @editChannelRemovePicture.
  ///
  /// In en, this message translates to:
  /// **'Remove it'**
  String get editChannelRemovePicture;

  /// No description provided for @editChannelPrivateNameNote.
  ///
  /// In en, this message translates to:
  /// **'This channel is private, so its name is encrypted with the channel key. Renaming it re-seals that for every member.'**
  String get editChannelPrivateNameNote;

  /// No description provided for @editChannelType.
  ///
  /// In en, this message translates to:
  /// **'Channel type'**
  String get editChannelType;

  /// No description provided for @editChannelDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Discussion'**
  String get editChannelDiscussion;

  /// No description provided for @editChannelReactions.
  ///
  /// In en, this message translates to:
  /// **'Reactions'**
  String get editChannelReactions;

  /// No description provided for @editChannelReactionsValue.
  ///
  /// In en, this message translates to:
  /// **'{count} emoji'**
  String editChannelReactionsValue(int count);

  /// No description provided for @editChannelWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome message'**
  String get editChannelWelcome;

  /// No description provided for @editChannelAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get editChannelAppearance;

  /// No description provided for @editChannelAutoTranslate.
  ///
  /// In en, this message translates to:
  /// **'Auto-translation'**
  String get editChannelAutoTranslate;

  /// No description provided for @editChannelDirectMessages.
  ///
  /// In en, this message translates to:
  /// **'Direct messages'**
  String get editChannelDirectMessages;

  /// No description provided for @editChannelNeedsName.
  ///
  /// In en, this message translates to:
  /// **'A channel needs a name.'**
  String get editChannelNeedsName;

  /// No description provided for @editChannelDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get editChannelDiscardTitle;

  /// No description provided for @editChannelDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing here has been saved yet.'**
  String get editChannelDiscardBody;

  /// No description provided for @editChannelKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get editChannelKeepEditing;

  /// No description provided for @editChannelDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get editChannelDiscard;

  /// No description provided for @editChannelCouldNotSave.
  ///
  /// In en, this message translates to:
  /// **'Could not save those changes.'**
  String get editChannelCouldNotSave;

  /// No description provided for @editChannelCouldNotUsePicture.
  ///
  /// In en, this message translates to:
  /// **'Could not use that picture.'**
  String get editChannelCouldNotUsePicture;

  /// No description provided for @editChannelPublicPictureTitle.
  ///
  /// In en, this message translates to:
  /// **'This picture will be public'**
  String get editChannelPublicPictureTitle;

  /// No description provided for @editChannelPublicPictureBody.
  ///
  /// In en, this message translates to:
  /// **'A public channel\'s picture is shown on its web page and in link previews, so it is stored unencrypted — the same as its name, handle and description. Posts stay end-to-end encrypted.'**
  String get editChannelPublicPictureBody;

  /// No description provided for @editChannelUseIt.
  ///
  /// In en, this message translates to:
  /// **'Use it'**
  String get editChannelUseIt;

  /// No description provided for @editChannelSignatureNote.
  ///
  /// In en, this message translates to:
  /// **'Signed posts show the name of whoever wrote them. With it off, everything the channel publishes is published by the channel.'**
  String get editChannelSignatureNote;

  /// No description provided for @livestreamNotSetUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Livestreams are not set up'**
  String get livestreamNotSetUpTitle;

  /// No description provided for @livestreamNotSetUpBody.
  ///
  /// In en, this message translates to:
  /// **'A livestream needs a media server: one person sends video and everybody else receives it, which cannot be done device to device the way a call is.\n\nThis Privio server has none configured, so there is nothing to join yet. Whoever runs it can set one up.'**
  String get livestreamNotSetUpBody;

  /// No description provided for @livestreamYouAreLive.
  ///
  /// In en, this message translates to:
  /// **'You are live'**
  String get livestreamYouAreLive;

  /// No description provided for @livestreamRunning.
  ///
  /// In en, this message translates to:
  /// **'A stream is running'**
  String get livestreamRunning;

  /// No description provided for @livestreamPublisherBody.
  ///
  /// In en, this message translates to:
  /// **'The room is open and your device has a token to publish to it. Privio does not carry the video itself yet — the media server does — so nothing is being sent from this screen.\n\nEnd it when you are done.'**
  String get livestreamPublisherBody;

  /// No description provided for @livestreamViewerBody.
  ///
  /// In en, this message translates to:
  /// **'A stream is running and this device has a token to watch it. Privio cannot show the video yet.'**
  String get livestreamViewerBody;

  /// No description provided for @livestreamEndIt.
  ///
  /// In en, this message translates to:
  /// **'End it'**
  String get livestreamEndIt;

  /// No description provided for @livestreamNobodyStreaming.
  ///
  /// In en, this message translates to:
  /// **'Nobody is streaming right now.'**
  String get livestreamNobodyStreaming;

  /// No description provided for @livestreamCouldNotStart.
  ///
  /// In en, this message translates to:
  /// **'Could not start the stream.'**
  String get livestreamCouldNotStart;

  /// No description provided for @translationNotSetUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-translation is not set up'**
  String get translationNotSetUpTitle;

  /// No description provided for @translationNotSetUpBody.
  ///
  /// In en, this message translates to:
  /// **'Translating a post means sending what it says to a translation service. Privio\'s server cannot do that — it holds ciphertext and no key — so it would have to happen on your device, and the text would leave it in the clear.\n\nThat is a decision for whoever runs this server to enable and for each reader to agree to, so it is off until both have happened. No post has been sent anywhere.'**
  String get translationNotSetUpBody;

  /// No description provided for @visibilityPublicTitle.
  ///
  /// In en, this message translates to:
  /// **'This channel is public'**
  String get visibilityPublicTitle;

  /// No description provided for @visibilityPrivateTitle.
  ///
  /// In en, this message translates to:
  /// **'This channel is private'**
  String get visibilityPrivateTitle;

  /// No description provided for @visibilityPublicBody.
  ///
  /// In en, this message translates to:
  /// **'Anyone can find it by name and read its posts. Its handle is @{handle}.\n\nPrivio cannot turn a public channel private after the fact: its name and description have been readable, and unsaying that is not something an app can do.'**
  String visibilityPublicBody(String handle);

  /// No description provided for @visibilityPrivateBody.
  ///
  /// In en, this message translates to:
  /// **'It is not listed, not searchable, and reachable only through its invite link. Its name is encrypted with the channel key.\n\nMaking it public would publish that name, which is a decision Privio does not make on your behalf — create a public channel instead.'**
  String get visibilityPrivateBody;

  /// No description provided for @discussionBody.
  ///
  /// In en, this message translates to:
  /// **'With this on, every post gets a thread underneath it. Comments are sealed with the same channel key as the post, so a device that cannot read the post cannot read the thread.\n\nTurning it off later hides the threads rather than deleting them.'**
  String get discussionBody;

  /// No description provided for @discussionTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get discussionTurnOn;

  /// No description provided for @discussionTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get discussionTurnOff;

  /// No description provided for @welcomeShowToNew.
  ///
  /// In en, this message translates to:
  /// **'Show it to new subscribers'**
  String get welcomeShowToNew;

  /// No description provided for @welcomeHint.
  ///
  /// In en, this message translates to:
  /// **'Shown once, on joining'**
  String get welcomeHint;

  /// No description provided for @welcomePrivateNote.
  ///
  /// In en, this message translates to:
  /// **'This channel is private, so the message is encrypted with the channel key like its name.'**
  String get welcomePrivateNote;

  /// No description provided for @appearanceNote.
  ///
  /// In en, this message translates to:
  /// **'A fixed set rather than a colour picker: every pair here was checked for contrast, so a channel cannot pick something its readers cannot read.'**
  String get appearanceNote;

  /// No description provided for @appearancePreviewPost.
  ///
  /// In en, this message translates to:
  /// **'A post in this channel'**
  String get appearancePreviewPost;

  /// No description provided for @appearancePreviewLink.
  ///
  /// In en, this message translates to:
  /// **'and a link in it'**
  String get appearancePreviewLink;

  /// No description provided for @appearanceAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get appearanceAccent;

  /// No description provided for @appearanceBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get appearanceBackground;

  /// No description provided for @appearanceUseDefault.
  ///
  /// In en, this message translates to:
  /// **'Use the default'**
  String get appearanceUseDefault;

  /// No description provided for @composerHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get composerHint;

  /// No description provided for @composerAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach a file'**
  String get composerAttach;

  /// No description provided for @composerTimerOff.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages are off'**
  String get composerTimerOff;

  /// No description provided for @composerTimerOn.
  ///
  /// In en, this message translates to:
  /// **'Messages disappear after {badge}'**
  String composerTimerOn(String badge);

  /// No description provided for @searchPostsHint.
  ///
  /// In en, this message translates to:
  /// **'Search posts you can read'**
  String get searchPostsHint;

  /// No description provided for @searchThisChannel.
  ///
  /// In en, this message translates to:
  /// **'Search this channel'**
  String get searchThisChannel;

  /// No description provided for @searchClose.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get searchClose;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing matched'**
  String get searchNoResults;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get settingsPrivacy;

  /// No description provided for @settingsStorage.
  ///
  /// In en, this message translates to:
  /// **'Data and Storage'**
  String get settingsStorage;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About Privio'**
  String get settingsAbout;

  /// No description provided for @settingsDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get settingsDevices;

  /// No description provided for @settingsBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get settingsBackup;

  /// No description provided for @settingsDisguise.
  ///
  /// In en, this message translates to:
  /// **'Disguise mode'**
  String get settingsDisguise;

  /// No description provided for @settingsLicense.
  ///
  /// In en, this message translates to:
  /// **'Privio License'**
  String get settingsLicense;

  /// No description provided for @settingsLicenseNotActive.
  ///
  /// In en, this message translates to:
  /// **'Not active'**
  String get settingsLicenseNotActive;

  /// No description provided for @appearanceTextSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get appearanceTextSize;

  /// No description provided for @appearanceTextSizeNote.
  ///
  /// In en, this message translates to:
  /// **'This is Privio\'s own setting and it applies everywhere in the app. It does not override the size your phone is set to for everything else — that one still applies underneath.'**
  String get appearanceTextSizeNote;

  /// No description provided for @appearanceDarkOnly.
  ///
  /// In en, this message translates to:
  /// **'Privio is dark-only. The design is built for it, true black costs nothing on the OLED panels most phones ship with, and a light theme that only half exists is not worth a switch that pretends otherwise.'**
  String get appearanceDarkOnly;

  /// No description provided for @textSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get textSizeSmall;

  /// No description provided for @textSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get textSizeMedium;

  /// No description provided for @textSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get textSizeLarge;

  /// No description provided for @textSizeLarger.
  ///
  /// In en, this message translates to:
  /// **'Larger'**
  String get textSizeLarger;

  /// No description provided for @notificationsPushNote.
  ///
  /// In en, this message translates to:
  /// **'A push carries no content — only a wake-up. The message is fetched and decrypted on this device, so nobody in the middle, including whoever runs the service that woke it, sees who wrote to you.'**
  String get notificationsPushNote;

  /// No description provided for @notificationsPhoneNote.
  ///
  /// In en, this message translates to:
  /// Phone notification preferences are managed in system settings.
  String get notificationsPhoneNote;

  String get notificationsIphoneNote;

  String get notificationsOpenIphoneSettings;

  String get notificationsSettingsFailed;


  /// No description provided for @notificationsDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get notificationsDelivery;

  /// No description provided for @notificationsDistributorFound.
  ///
  /// In en, this message translates to:
  /// **'A distributor app on this phone holds one connection for every app that uses it, and forwards a contentless ping. {app} needs no Google service for it, and you can run the distributor yourself.'**
  String notificationsDistributorFound(String app);

  /// No description provided for @notificationsNoDistributor.
  ///
  /// In en, this message translates to:
  /// **'No distributor found. Install one — ntfy, for example — to be woken while Privio is closed. Without one, messages arrive while the app is open.'**
  String get notificationsNoDistributor;

  /// No description provided for @privacyWhoCanSee.
  ///
  /// In en, this message translates to:
  /// **'Who can see'**
  String get privacyWhoCanSee;

  /// No description provided for @privacyLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last Seen'**
  String get privacyLastSeen;

  /// No description provided for @privacyLastSeenEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get privacyLastSeenEveryone;

  /// No description provided for @privacyLastSeenContacts.
  ///
  /// In en, this message translates to:
  /// **'My contacts'**
  String get privacyLastSeenContacts;

  /// No description provided for @privacyLastSeenNobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get privacyLastSeenNobody;

  /// No description provided for @privacyMessaging.
  ///
  /// In en, this message translates to:
  /// **'Messaging'**
  String get privacyMessaging;

  /// No description provided for @privacyReadReceipts.
  ///
  /// In en, this message translates to:
  /// **'Read Receipts'**
  String get privacyReadReceipts;

  /// No description provided for @privacyTypingIndicators.
  ///
  /// In en, this message translates to:
  /// **'Typing Indicators'**
  String get privacyTypingIndicators;

  /// No description provided for @privacyDisappearing.
  ///
  /// In en, this message translates to:
  /// **'Disappearing Messages'**
  String get privacyDisappearing;

  /// No description provided for @privacyPerChat.
  ///
  /// In en, this message translates to:
  /// **'Per chat'**
  String get privacyPerChat;

  /// No description provided for @privacyAccess.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get privacyAccess;

  /// No description provided for @privacyScreenLock.
  ///
  /// In en, this message translates to:
  /// **'Screen Lock'**
  String get privacyScreenLock;

  /// No description provided for @privacyPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get privacyPin;

  /// No description provided for @privacyTwoFactor.
  ///
  /// In en, this message translates to:
  /// **'Two-Factor Authentication'**
  String get privacyTwoFactor;

  /// No description provided for @privacyDuressCode.
  ///
  /// In en, this message translates to:
  /// **'Duress Code'**
  String get privacyDuressCode;

  /// No description provided for @privacyScreenShield.
  ///
  /// In en, this message translates to:
  /// **'Screen protection'**
  String get privacyScreenShield;

  /// No description provided for @privacyScreenShieldAndroid.
  ///
  /// In en, this message translates to:
  /// **'Blocks screenshots and screen recordings of the app.'**
  String get privacyScreenShieldAndroid;

  /// No description provided for @privacyScreenShieldIos.
  ///
  /// In en, this message translates to:
  /// **'Hides sensitive content when a screen recording or screen sharing is detected. Screenshots cannot be reliably prevented on iOS.'**
  String get privacyScreenShieldIos;

  /// No description provided for @privacyScreenShieldUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This device cannot protect the screen.'**
  String get privacyScreenShieldUnavailable;

  /// No description provided for @privacyScreenShieldScope.
  ///
  /// In en, this message translates to:
  /// **'This protects your own device only. It cannot stop anyone else recording their screen, and it cannot stop a photograph taken with another camera.'**
  String get privacyScreenShieldScope;

  /// No description provided for @privacyScreenShieldCovering.
  ///
  /// In en, this message translates to:
  /// **'A screen recording is running. Privio is hidden until it stops.'**
  String get privacyScreenShieldCovering;

  /// No description provided for @privacySet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get privacySet;

  /// No description provided for @privacyBlockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Blocked Users'**
  String get privacyBlockedUsers;

  /// No description provided for @privacyMutualNote.
  ///
  /// In en, this message translates to:
  /// **'Read receipts and typing indicators are mutual: turning them off also stops you from seeing other people’s.'**
  String get privacyMutualNote;

  /// No description provided for @storageOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get storageOnThisDevice;

  /// No description provided for @storageHistory.
  ///
  /// In en, this message translates to:
  /// **'Conversation history'**
  String get storageHistory;

  /// No description provided for @storageInIt.
  ///
  /// In en, this message translates to:
  /// **'In it'**
  String get storageInIt;

  /// No description provided for @storageChatsAndMessages.
  ///
  /// In en, this message translates to:
  /// **'{chats, plural, =1{1 chat} other{{chats} chats}}, {messages, plural, =1{1 message} other{{messages} messages}}'**
  String storageChatsAndMessages(int chats, int messages);

  /// No description provided for @storageKeys.
  ///
  /// In en, this message translates to:
  /// **'Keys and sessions'**
  String get storageKeys;

  /// No description provided for @storageKeystoreNote.
  ///
  /// In en, this message translates to:
  /// **'Both sit in the platform keystore — the Keychain on iOS, Keystore-backed storage on Android — and the history is sealed with AES-256-GCM before it gets there. Neither is readable by another app, and neither is readable by anyone holding the phone without unlocking it.'**
  String get storageKeystoreNote;

  /// No description provided for @storageNotKept.
  ///
  /// In en, this message translates to:
  /// **'Not kept'**
  String get storageNotKept;

  /// No description provided for @storageFilesOpened.
  ///
  /// In en, this message translates to:
  /// **'Files you opened'**
  String get storageFilesOpened;

  /// No description provided for @storageMemoryOnly.
  ///
  /// In en, this message translates to:
  /// **'Memory only'**
  String get storageMemoryOnly;

  /// No description provided for @storageVoiceRecordings.
  ///
  /// In en, this message translates to:
  /// **'Voice recordings'**
  String get storageVoiceRecordings;

  /// No description provided for @storageShredded.
  ///
  /// In en, this message translates to:
  /// **'Shredded when sent'**
  String get storageShredded;

  /// No description provided for @storageEphemeralNote.
  ///
  /// In en, this message translates to:
  /// **'A photo or file you open is decrypted into memory and goes when the app closes; nothing writes it to disk. A voice message is recorded to a temporary file, because the microphone has to write somewhere, and that file is overwritten with random bytes and deleted the moment the recording ends — a deleted file on flash storage is not a gone file.'**
  String get storageEphemeralNote;

  /// No description provided for @storageDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get storageDelete;

  /// No description provided for @storageDeleteHistory.
  ///
  /// In en, this message translates to:
  /// **'Delete history on this device'**
  String get storageDeleteHistory;

  /// No description provided for @storageDeleteNote.
  ///
  /// In en, this message translates to:
  /// **'This is the only deletion that happens here. What the server holds — a backup, an attachment still inside its thirty days — is on the Backup screen, and what the person you wrote to has is theirs.'**
  String get storageDeleteNote;

  /// No description provided for @storageConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the history on this device?'**
  String get storageConfirmTitle;

  /// No description provided for @storageConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Every message on this phone goes, in every chat. Your account, your keys and your conversations stay: people can still write to you, and what you send after this still arrives.\n\nIt cannot reach their copy, and it cannot reach a backup already on the server. Delete that from the Backup screen if you want it gone too.'**
  String get storageConfirmBody;

  /// No description provided for @storageDeleteIt.
  ///
  /// In en, this message translates to:
  /// **'Delete it'**
  String get storageDeleteIt;

  /// No description provided for @storageDeleted.
  ///
  /// In en, this message translates to:
  /// **'The history on this device is gone.'**
  String get storageDeleted;

  /// No description provided for @devicesThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get devicesThisDevice;

  /// No description provided for @devicesOthers.
  ///
  /// In en, this message translates to:
  /// **'Other devices'**
  String get devicesOthers;

  /// No description provided for @devicesOthersTapToSignOut.
  ///
  /// In en, this message translates to:
  /// **'Other devices — tap to sign out'**
  String get devicesOthersTapToSignOut;

  /// No description provided for @devicesNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get devicesNone;

  /// No description provided for @devicesOnlyThisOne.
  ///
  /// In en, this message translates to:
  /// **'Only this one'**
  String get devicesOnlyThisOne;

  /// No description provided for @devicesSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get devicesSignedIn;

  /// No description provided for @devicesActiveNow.
  ///
  /// In en, this message translates to:
  /// **'Active now'**
  String get devicesActiveNow;

  /// No description provided for @devicesActiveMinutes.
  ///
  /// In en, this message translates to:
  /// **'Active {count} min ago'**
  String devicesActiveMinutes(int count);

  /// No description provided for @devicesActiveHours.
  ///
  /// In en, this message translates to:
  /// **'Active {count} h ago'**
  String devicesActiveHours(int count);

  /// No description provided for @devicesActiveYesterday.
  ///
  /// In en, this message translates to:
  /// **'Active yesterday'**
  String get devicesActiveYesterday;

  /// No description provided for @devicesActiveDays.
  ///
  /// In en, this message translates to:
  /// **'Active {count} days ago'**
  String devicesActiveDays(int count);

  /// No description provided for @devicesSignOutNote.
  ///
  /// In en, this message translates to:
  /// **'Signing a device out revokes its session and deletes anything still queued for it. It can only rejoin by signing in again — as a new device, with new keys.'**
  String get devicesSignOutNote;

  /// No description provided for @devicesRevokeTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out {name}?'**
  String devicesRevokeTitle(String name);

  /// No description provided for @devicesRevokeBody.
  ///
  /// In en, this message translates to:
  /// **'Its session is revoked and anything still queued for it is deleted. What it has already decrypted stays on that device — nothing here can reach it. It can only come back by signing in again.'**
  String get devicesRevokeBody;

  /// No description provided for @devicesSignItOut.
  ///
  /// In en, this message translates to:
  /// **'Sign it out'**
  String get devicesSignItOut;

  /// No description provided for @devicesSignedOut.
  ///
  /// In en, this message translates to:
  /// **'{name} is signed out.'**
  String devicesSignedOut(String name);

  /// No description provided for @devicesLicenseCovers.
  ///
  /// In en, this message translates to:
  /// **'Your license covers {limit} devices.'**
  String devicesLicenseCovers(int limit);

  /// No description provided for @devicesLicenseCoversUsed.
  ///
  /// In en, this message translates to:
  /// **'Your license covers {limit} devices. {used} in use.'**
  String devicesLicenseCoversUsed(int limit, int used);

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Built with privacy in mind.\nNo tracking. No ads. Just you.'**
  String get aboutTagline;

  /// No description provided for @aboutWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsite;

  /// No description provided for @aboutSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get aboutSupport;

  /// No description provided for @aboutAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get aboutAddress;

  /// No description provided for @aboutOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get aboutOpenSource;

  /// No description provided for @aboutEdition.
  ///
  /// In en, this message translates to:
  /// **'Edition'**
  String get aboutEdition;

  /// No description provided for @aboutFreeSoftware.
  ///
  /// In en, this message translates to:
  /// **'{name} · free software'**
  String aboutFreeSoftware(String name);

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicense;

  /// No description provided for @aboutSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCode;

  /// No description provided for @aboutCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get aboutCopyLink;

  /// No description provided for @aboutSourceLink.
  ///
  /// In en, this message translates to:
  /// **'Source link'**
  String get aboutSourceLink;

  /// No description provided for @aboutThirdParty.
  ///
  /// In en, this message translates to:
  /// **'Third-party licenses'**
  String get aboutThirdParty;

  /// No description provided for @aboutCopied.
  ///
  /// In en, this message translates to:
  /// **'{what} copied.'**
  String aboutCopied(String what);

  /// No description provided for @aboutFreeBuildNote.
  ///
  /// In en, this message translates to:
  /// **'This build contains no proprietary code and can be reproduced from the source above. Nothing here has to be taken on trust — build it yourself and compare.'**
  String get aboutFreeBuildNote;

  /// No description provided for @aboutStoreBuildNote.
  ///
  /// In en, this message translates to:
  /// **'This build came from an app store and links that store\'s services. The Libre build, at the source above, contains none of them.'**
  String get aboutStoreBuildNote;

  /// No description provided for @blockedUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get blockedUnblock;

  /// No description provided for @blockedUnblockTitle.
  ///
  /// In en, this message translates to:
  /// **'Unblock {name}?'**
  String blockedUnblockTitle(String name);

  /// No description provided for @blockedUnblockBody.
  ///
  /// In en, this message translates to:
  /// **'They will be able to send you messages again.'**
  String get blockedUnblockBody;

  /// No description provided for @blockedInvisibleNote.
  ///
  /// In en, this message translates to:
  /// **'Blocking is invisible: their messages are dropped and they are told nothing, so a block cannot be used to find out that they have been blocked.'**
  String get blockedInvisibleNote;

  /// No description provided for @blockedNobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody is blocked'**
  String get blockedNobody;

  /// No description provided for @blockedEmptyNote.
  ///
  /// In en, this message translates to:
  /// **'Block someone from their chat, and they turn up here.'**
  String get blockedEmptyNote;

  /// No description provided for @chatsSectionChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatsSectionChats;

  /// No description provided for @chatsSectionMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get chatsSectionMessages;

  /// No description provided for @chatsYouPrefix.
  ///
  /// In en, this message translates to:
  /// **'You: '**
  String get chatsYouPrefix;

  /// No description provided for @chatsNoSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing here matches. Only this device was asked — the server holds messages it cannot read, so it could not have answered.'**
  String get chatsNoSearchResults;

  /// No description provided for @chatsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get chatsFilterAll;

  /// No description provided for @chatsJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get chatsJoin;

  /// No description provided for @chatsFilterUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get chatsFilterUnread;

  /// No description provided for @chatsFilterGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get chatsFilterGroups;

  /// No description provided for @chatsPin.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get chatsPin;

  /// No description provided for @chatsUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get chatsUnpin;

  /// No description provided for @chatsPinNote.
  ///
  /// In en, this message translates to:
  /// **'Only on this device. Nothing is sent.'**
  String get chatsPinNote;

  /// No description provided for @chatsGroupFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get chatsGroupFallbackName;

  /// No description provided for @chatsNewGroupTooltip.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get chatsNewGroupTooltip;

  /// No description provided for @chatsNewChatTooltip.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get chatsNewChatTooltip;

  /// No description provided for @chatsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get chatsEmptyTitle;

  /// No description provided for @chatsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add someone by their exact username to start talking.'**
  String get chatsEmptyBody;

  /// No description provided for @chatsAddContact.
  ///
  /// In en, this message translates to:
  /// **'Add a contact'**
  String get chatsAddContact;

  /// No description provided for @commonGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get commonGotIt;

  /// No description provided for @commonPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get commonPause;

  /// No description provided for @commonPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get commonPlay;

  /// No description provided for @commonOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// No description provided for @commonReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get commonReply;

  /// No description provided for @commonFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get commonFile;

  /// No description provided for @scrubRemoved.
  ///
  /// In en, this message translates to:
  /// **'Metadata removed'**
  String get scrubRemoved;

  /// No description provided for @scrubNothingToRemove.
  ///
  /// In en, this message translates to:
  /// **'Nothing to remove'**
  String get scrubNothingToRemove;

  /// No description provided for @scrubCouldNotClean.
  ///
  /// In en, this message translates to:
  /// **'Could not be cleaned'**
  String get scrubCouldNotClean;

  /// No description provided for @scrubRemovedBody.
  ///
  /// In en, this message translates to:
  /// **'This was stripped out before the file was encrypted and sent. The recipient never receives it.'**
  String get scrubRemovedBody;

  /// No description provided for @scrubNothingBody.
  ///
  /// In en, this message translates to:
  /// **'This file carried no identifying metadata to begin with.'**
  String get scrubNothingBody;

  /// No description provided for @scrubNoCleanerBody.
  ///
  /// In en, this message translates to:
  /// **'Privio has no cleaner for {type} yet, so the file was sent as it is. It is still end-to-end encrypted, but any metadata inside it reaches the recipient.'**
  String scrubNoCleanerBody(String type);

  /// No description provided for @webStorageShort.
  ///
  /// In en, this message translates to:
  /// **'In a browser, this device’s history is only as private as this browser profile. Messages in transit are encrypted either way.'**
  String get webStorageShort;

  /// No description provided for @webStorageLong.
  ///
  /// In en, this message translates to:
  /// **'You are using Privio in a browser. Messages are still end-to-end encrypted in transit — but a browser has no keystore, so the history kept on this device is only as private as this browser profile. Anyone who can read it — a shared computer, an extension, a copy of the profile — can read your chats. The phone apps do not have this problem.'**
  String get webStorageLong;

  /// No description provided for @voiceCouldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open this recording.'**
  String get voiceCouldNotOpen;

  /// No description provided for @voiceCannotPlay.
  ///
  /// In en, this message translates to:
  /// **'This device cannot play that recording.'**
  String get voiceCannotPlay;

  /// No description provided for @voiceMicUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The microphone is not available right now.'**
  String get voiceMicUnavailable;

  /// No description provided for @voiceCouldNotSave.
  ///
  /// In en, this message translates to:
  /// **'That recording could not be saved.'**
  String get voiceCouldNotSave;

  /// No description provided for @voiceSlideToCancel.
  ///
  /// In en, this message translates to:
  /// **'Slide to cancel'**
  String get voiceSlideToCancel;

  /// No description provided for @voiceResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get voiceResume;

  /// No description provided for @voiceStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get voiceStop;

  /// No description provided for @voiceDeleteRecording.
  ///
  /// In en, this message translates to:
  /// **'Delete recording'**
  String get voiceDeleteRecording;

  /// No description provided for @voiceListenBack.
  ///
  /// In en, this message translates to:
  /// **'Listen back'**
  String get voiceListenBack;

  /// No description provided for @bubbleYouDeleted.
  ///
  /// In en, this message translates to:
  /// **'You deleted this message'**
  String get bubbleYouDeleted;

  /// No description provided for @bubbleMessageDeleted.
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get bubbleMessageDeleted;

  /// No description provided for @bubbleCouldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open'**
  String get bubbleCouldNotOpen;

  /// No description provided for @bubbleEncryptedNotice.
  ///
  /// In en, this message translates to:
  /// **'Messages and calls are end-to-end encrypted. No one outside this chat can read or listen to them, not even Privio.'**
  String get bubbleEncryptedNotice;

  /// No description provided for @linkNotWebAddress.
  ///
  /// In en, this message translates to:
  /// **'That link is not a web address.'**
  String get linkNotWebAddress;

  /// No description provided for @linkNothingCanOpen.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this device could open that link.'**
  String get linkNothingCanOpen;

  /// No description provided for @linkOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open this link?'**
  String get linkOpenTitle;

  /// No description provided for @linkOpenBody.
  ///
  /// In en, this message translates to:
  /// **'This opens in your browser, outside Privio. The site sees your connection the way any site you visit does.'**
  String get linkOpenBody;

  /// No description provided for @timerBadgeDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String timerBadgeDays(int count);

  /// No description provided for @timerBadgeHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String timerBadgeHours(int count);

  /// No description provided for @timerBadgeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String timerBadgeMinutes(int count);

  /// No description provided for @timerBadgeSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count}s'**
  String timerBadgeSeconds(int count);

  /// No description provided for @chatSafetyNumberChanged.
  ///
  /// In en, this message translates to:
  /// **'Safety number changed'**
  String get chatSafetyNumberChanged;

  /// No description provided for @chatEncrypted.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted'**
  String get chatEncrypted;

  /// No description provided for @chatEncryptedVerified.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted · verified'**
  String get chatEncryptedVerified;

  /// No description provided for @chatEncryptedNumberChanged.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted · number changed'**
  String get chatEncryptedNumberChanged;

  /// No description provided for @chatWaitingGroupKey.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the group key'**
  String get chatWaitingGroupKey;

  /// No description provided for @chatMembersEncrypted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}} · encrypted'**
  String chatMembersEncrypted(int count);

  /// No description provided for @chatRetrySendTitle.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get chatRetrySendTitle;

  /// No description provided for @chatRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'It did not go out. Send it now.'**
  String get chatRetryFailed;

  /// No description provided for @chatRetryQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a network. Try now anyway.'**
  String get chatRetryQueued;

  /// No description provided for @chatCopyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get chatCopyText;

  /// No description provided for @chatDeleteForMe.
  ///
  /// In en, this message translates to:
  /// **'Delete for me'**
  String get chatDeleteForMe;

  /// No description provided for @chatDeleteForMeNote.
  ///
  /// In en, this message translates to:
  /// **'Gone from this device. Other devices keep it.'**
  String get chatDeleteForMeNote;

  /// No description provided for @chatDeleteForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get chatDeleteForEveryone;

  /// No description provided for @chatDeleteForEveryoneNote.
  ///
  /// In en, this message translates to:
  /// **'Asks their app to forget it. It cannot take back what was already read, screenshotted, or restored from a backup.'**
  String get chatDeleteForEveryoneNote;

  /// No description provided for @chatPickerNoResponse.
  ///
  /// In en, this message translates to:
  /// **'The file picker did not respond.'**
  String get chatPickerNoResponse;

  /// No description provided for @chatPickerFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker: {reason}'**
  String chatPickerFailed(String reason);

  /// No description provided for @chatCouldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read {name}.'**
  String chatCouldNotReadFile(String name);

  /// No description provided for @chatBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Block {name}?'**
  String chatBlockTitle(String name);

  /// No description provided for @chatBlockBody.
  ///
  /// In en, this message translates to:
  /// **'Their messages stop arriving. They are not told, and it looks to them as though nothing changed. You can lift it in Privacy & Security.'**
  String get chatBlockBody;

  /// No description provided for @chatBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get chatBlock;

  /// No description provided for @chatBlocked.
  ///
  /// In en, this message translates to:
  /// **'{name} is blocked.'**
  String chatBlocked(String name);

  /// No description provided for @chatCouldNotBlock.
  ///
  /// In en, this message translates to:
  /// **'Could not block them.'**
  String get chatCouldNotBlock;

  /// No description provided for @chatMicrophoneDenied.
  ///
  /// In en, this message translates to:
  /// **'Privio cannot record without microphone access. You can grant it in your device settings.'**
  String get chatMicrophoneDenied;

  /// No description provided for @chatNoGroupLink.
  ///
  /// In en, this message translates to:
  /// **'No link for this group yet — pull to refresh.'**
  String get chatNoGroupLink;

  /// No description provided for @chatInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Invite link'**
  String get chatInviteLink;

  /// No description provided for @chatInviteLinkNote.
  ///
  /// In en, this message translates to:
  /// **'Share it anywhere — it carries no key. Whoever opens it joins the group, and the key to its name reaches their device encrypted.'**
  String get chatInviteLinkNote;

  /// No description provided for @chatTyping.
  ///
  /// In en, this message translates to:
  /// **'typing…'**
  String get chatTyping;

  /// No description provided for @chatVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get chatVideoCall;

  /// No description provided for @chatVoiceCall.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get chatVoiceCall;

  /// No description provided for @chatMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get chatMore;

  /// No description provided for @chatGroupInfo.
  ///
  /// In en, this message translates to:
  /// **'Group info'**
  String get chatGroupInfo;

  /// No description provided for @chatSafetyNumber.
  ///
  /// In en, this message translates to:
  /// **'Safety number'**
  String get chatSafetyNumber;

  /// No description provided for @chatActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get chatActivate;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatHoldToRecord.
  ///
  /// In en, this message translates to:
  /// **'Hold the microphone to record a voice message.'**
  String get chatHoldToRecord;

  /// No description provided for @chatReplyingToYourself.
  ///
  /// In en, this message translates to:
  /// **'Replying to yourself'**
  String get chatReplyingToYourself;

  /// No description provided for @chatReplyingTo.
  ///
  /// In en, this message translates to:
  /// **'Replying to {name}'**
  String chatReplyingTo(String name);

  /// No description provided for @chatReplying.
  ///
  /// In en, this message translates to:
  /// **'Replying'**
  String get chatReplying;

  /// No description provided for @chatCancelReply.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get chatCancelReply;

  /// No description provided for @contactsTitle.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contactsTitle;

  /// No description provided for @contactsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get contactsSearch;

  /// No description provided for @contactsLastSeen.
  ///
  /// In en, this message translates to:
  /// **'@{username} · last seen {when}'**
  String contactsLastSeen(String username, String when);

  /// No description provided for @contactsSeenJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get contactsSeenJustNow;

  /// No description provided for @contactsSeenMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String contactsSeenMinutes(int count);

  /// No description provided for @contactsSeenAtTime.
  ///
  /// In en, this message translates to:
  /// **'at {time}'**
  String contactsSeenAtTime(String time);

  /// No description provided for @contactsSeenDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String contactsSeenDays(int count);

  /// No description provided for @contactsCouldNotAdd.
  ///
  /// In en, this message translates to:
  /// **'Could not add that user'**
  String get contactsCouldNotAdd;

  /// No description provided for @contactsAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get contactsAddTitle;

  /// No description provided for @contactsAddNote.
  ///
  /// In en, this message translates to:
  /// **'Enter their exact Privio username. Nothing is uploaded from your address book, and nobody can find you by browsing.'**
  String get contactsAddNote;

  /// No description provided for @contactsUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'username'**
  String get contactsUsernameHint;

  /// No description provided for @contactsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get contactsEmptyTitle;

  /// No description provided for @contactsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add someone by their exact username, or share your invite link from the Account tab.'**
  String get contactsEmptyBody;

  /// No description provided for @groupCouldNotCreate.
  ///
  /// In en, this message translates to:
  /// **'Could not create the group'**
  String get groupCouldNotCreate;

  /// No description provided for @groupNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get groupNewTitle;

  /// No description provided for @groupCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get groupCreate;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupNameEncryptedNote.
  ///
  /// In en, this message translates to:
  /// **'The name is encrypted. Privio stores a group it cannot name.'**
  String get groupNameEncryptedNote;

  /// No description provided for @groupChooseMembers.
  ///
  /// In en, this message translates to:
  /// **'Choose members'**
  String get groupChooseMembers;

  /// No description provided for @groupSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String groupSelectedCount(int count);

  /// No description provided for @groupAddContactsFirst.
  ///
  /// In en, this message translates to:
  /// **'Add some contacts first — a group needs people in it.'**
  String get groupAddContactsFirst;

  /// No description provided for @groupInfoCouldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Could not read who is in this group.'**
  String get groupInfoCouldNotRead;

  /// No description provided for @groupAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'Only an admin can change this'**
  String get groupAdminOnly;

  /// No description provided for @groupRename.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get groupRename;

  /// No description provided for @groupRenameAction.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get groupRenameAction;

  /// No description provided for @groupRenamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed. Everyone else opens the new name with the key they already have.'**
  String get groupRenamed;

  /// No description provided for @groupCouldNotRename.
  ///
  /// In en, this message translates to:
  /// **'Could not rename the group.'**
  String get groupCouldNotRename;

  /// No description provided for @groupRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String groupRemoveTitle(String name);

  /// No description provided for @groupRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'They stop receiving what is sent from now on. What they already received stays on their device — nothing here can reach it.'**
  String get groupRemoveBody;

  /// No description provided for @groupCouldNotRemove.
  ///
  /// In en, this message translates to:
  /// **'Could not remove them.'**
  String get groupCouldNotRemove;

  /// No description provided for @groupLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave this group?'**
  String get groupLeaveTitle;

  /// No description provided for @groupLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'You stop receiving what is sent to it, and the conversation goes from this device with everything in it. Nobody is told; the others see you disappear from the member list.'**
  String get groupLeaveBody;

  /// No description provided for @groupLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get groupLeave;

  /// No description provided for @groupLeaveRow.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get groupLeaveRow;

  /// No description provided for @groupDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this group?'**
  String get groupDeleteTitle;

  /// No description provided for @groupDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'It goes for everyone: nobody can send to it again. What has already been delivered stays on the devices that received it, which is every message anyone has read.'**
  String get groupDeleteBody;

  /// No description provided for @groupDeleteRow.
  ///
  /// In en, this message translates to:
  /// **'Delete group for everyone'**
  String get groupDeleteRow;

  /// No description provided for @groupYouSuffix.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get groupYouSuffix;

  /// No description provided for @groupAdminSuffix.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get groupAdminSuffix;

  /// No description provided for @navChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get navChats;

  /// No description provided for @navChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get navChannels;

  /// No description provided for @navCalls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get navCalls;

  /// No description provided for @navContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get navContacts;

  /// No description provided for @navAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get navAccount;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Secure Messenger'**
  String get splashTagline;

  /// No description provided for @splashPromise.
  ///
  /// In en, this message translates to:
  /// **'Encrypted. Private. Yours.'**
  String get splashPromise;

  /// No description provided for @splashInitialising.
  ///
  /// In en, this message translates to:
  /// **'Initializing secure environment'**
  String get splashInitialising;

  /// No description provided for @accountPickerFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the picker: {reason}'**
  String accountPickerFailed(String reason);

  /// No description provided for @accountCouldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read {name}: {reason}'**
  String accountCouldNotReadFile(String name, String reason);

  /// No description provided for @accountCouldNotSetPicture.
  ///
  /// In en, this message translates to:
  /// **'Could not set the picture'**
  String get accountCouldNotSetPicture;

  /// No description provided for @accountTapToAddPicture.
  ///
  /// In en, this message translates to:
  /// **'Tap to add a picture'**
  String get accountTapToAddPicture;

  /// No description provided for @accountPictureEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted — only your contacts can see it'**
  String get accountPictureEncrypted;

  /// No description provided for @accountUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get accountUsername;

  /// No description provided for @accountStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get accountStatus;

  /// No description provided for @accountStatusDefault.
  ///
  /// In en, this message translates to:
  /// **'Hey there! I am using Privio.'**
  String get accountStatusDefault;

  /// No description provided for @accountStatusNone.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get accountStatusNone;

  /// No description provided for @accountStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get accountStatusTitle;

  /// No description provided for @accountStatusHint.
  ///
  /// In en, this message translates to:
  /// **'What are you up to?'**
  String get accountStatusHint;

  /// No description provided for @accountStatusEmoji.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get accountStatusEmoji;

  /// No description provided for @accountStatusEmojiNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get accountStatusEmojiNone;

  /// No description provided for @accountStatusClearsAfter.
  ///
  /// In en, this message translates to:
  /// **'Clears after'**
  String get accountStatusClearsAfter;

  /// No description provided for @accountStatusNeverClears.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get accountStatusNeverClears;

  /// No description provided for @accountStatus30Minutes.
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get accountStatus30Minutes;

  /// No description provided for @accountStatus1Hour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get accountStatus1Hour;

  /// No description provided for @accountStatus4Hours.
  ///
  /// In en, this message translates to:
  /// **'4 hours'**
  String get accountStatus4Hours;

  /// No description provided for @accountStatusToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get accountStatusToday;

  /// No description provided for @accountStatus1Week.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get accountStatus1Week;

  /// The moment a status clears, on the account row.
  ///
  /// In en, this message translates to:
  /// **'Until {time}'**
  String accountStatusUntil(String time);

  /// No description provided for @accountStatusCouldNotSave.
  ///
  /// In en, this message translates to:
  /// **'Your status was not saved. What you typed is still here — try again.'**
  String get accountStatusCouldNotSave;

  /// No description provided for @accountStatusSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get accountStatusSaving;

  /// No description provided for @accountStatusExplainer.
  ///
  /// In en, this message translates to:
  /// **'Anyone allowed to see your status reads this. It is not encrypted the way your messages are, and it is not your online status.'**
  String get accountStatusExplainer;

  /// No description provided for @privacyProfileStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get privacyProfileStatus;

  /// No description provided for @privacyProfileStatusEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get privacyProfileStatusEveryone;

  /// No description provided for @privacyProfileStatusContacts.
  ///
  /// In en, this message translates to:
  /// **'My contacts'**
  String get privacyProfileStatusContacts;

  /// No description provided for @privacyProfileStatusNobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get privacyProfileStatusNobody;

  /// No description provided for @accountId.
  ///
  /// In en, this message translates to:
  /// **'Account ID'**
  String get accountId;

  /// No description provided for @accountInviteRow.
  ///
  /// In en, this message translates to:
  /// **'Invite link / QR code'**
  String get accountInviteRow;

  /// No description provided for @accountLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get accountLogOut;

  /// No description provided for @accountLogOutQuestion.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get accountLogOutQuestion;

  /// No description provided for @accountLogOutBody.
  ///
  /// In en, this message translates to:
  /// **'Your messages stay encrypted on this device until you delete them. You will need your password to sign back in.'**
  String get accountLogOutBody;

  /// No description provided for @accountDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accountDelete;

  /// No description provided for @accountDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this account?'**
  String get accountDeleteTitle;

  /// No description provided for @accountDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Your devices, your keys, the messages still waiting to be delivered, your contacts, your group memberships and your backup are all deleted on the server. Everything on this phone goes with them.\n\nIt cannot reach what other people have already received, and your username becomes free for somebody else to take.\n\nThere is no undo and no recovery — not with the recovery key, not by writing to anybody.'**
  String get accountDeleteBody;

  /// No description provided for @accountYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Your password'**
  String get accountYourPassword;

  /// No description provided for @accountDeleteIt.
  ///
  /// In en, this message translates to:
  /// **'Delete it'**
  String get accountDeleteIt;

  /// No description provided for @inviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get inviteTitle;

  /// No description provided for @inviteTabLink.
  ///
  /// In en, this message translates to:
  /// **'Invite Link'**
  String get inviteTabLink;

  /// No description provided for @inviteTabQr.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get inviteTabQr;

  /// No description provided for @inviteYourLink.
  ///
  /// In en, this message translates to:
  /// **'Your invite link'**
  String get inviteYourLink;

  /// No description provided for @inviteCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite link copied'**
  String get inviteCopied;

  /// No description provided for @inviteCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get inviteCopyLink;

  /// No description provided for @inviteCopyInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Copy invite link'**
  String get inviteCopyInviteLink;

  /// No description provided for @inviteNote.
  ///
  /// In en, this message translates to:
  /// **'Share this link with others to invite them to Privio. It reveals your username and nothing else.'**
  String get inviteNote;

  /// No description provided for @inviteScanToConnect.
  ///
  /// In en, this message translates to:
  /// **'Scan to connect with @{username}'**
  String inviteScanToConnect(String username);

  /// No description provided for @callsClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear call history'**
  String get callsClearHistory;

  /// No description provided for @callsClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear call history?'**
  String get callsClearTitle;

  /// No description provided for @callsClearBody.
  ///
  /// In en, this message translates to:
  /// **'This list is only on this device — clearing it removes it from here and from nowhere else, because it was never anywhere else.'**
  String get callsClearBody;

  /// No description provided for @callsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get callsClear;

  /// No description provided for @callsNeverLeavesNote.
  ///
  /// In en, this message translates to:
  /// **'This list never leaves the device. The server routes a call\'s setup the way it routes a message — sealed, and unreadable to it — so it holds no record of who called whom.'**
  String get callsNeverLeavesNote;

  /// No description provided for @callsCallSomeone.
  ///
  /// In en, this message translates to:
  /// **'Call {name}'**
  String callsCallSomeone(String name);

  /// No description provided for @callsDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get callsDeclined;

  /// No description provided for @callsNotTaken.
  ///
  /// In en, this message translates to:
  /// **'Not taken'**
  String get callsNotTaken;

  /// No description provided for @callsBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get callsBusy;

  /// No description provided for @callsCouldNotConnect.
  ///
  /// In en, this message translates to:
  /// **'Could not connect'**
  String get callsCouldNotConnect;

  /// No description provided for @callsMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get callsMissed;

  /// No description provided for @callsNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'No answer'**
  String get callsNoAnswer;

  /// No description provided for @callsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No calls yet'**
  String get callsEmptyTitle;

  /// No description provided for @callsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Start one from a chat. The call is set up over the Signal session that chat already uses, so the addresses your two devices swap to find each other are sealed to each other and not to the server.'**
  String get callsEmptyBody;

  /// No description provided for @callCalling.
  ///
  /// In en, this message translates to:
  /// **'Calling…'**
  String get callCalling;

  /// No description provided for @callIncomingVideo.
  ///
  /// In en, this message translates to:
  /// **'Incoming video call'**
  String get callIncomingVideo;

  /// No description provided for @callIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming call'**
  String get callIncoming;

  /// No description provided for @callConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get callConnecting;

  /// No description provided for @callEnded.
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get callEnded;

  /// No description provided for @callDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get callDecline;

  /// No description provided for @callAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get callAccept;

  /// No description provided for @callMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get callMute;

  /// No description provided for @callUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get callUnmute;

  /// No description provided for @callCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get callCamera;

  /// No description provided for @callCameraOff.
  ///
  /// In en, this message translates to:
  /// **'Camera off'**
  String get callCameraOff;

  /// No description provided for @callEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get callEnd;

  /// No description provided for @callSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get callSpeaker;

  /// No description provided for @welcomePromiseEncrypted.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted'**
  String get welcomePromiseEncrypted;

  /// No description provided for @welcomePromiseNoPhone.
  ///
  /// In en, this message translates to:
  /// **'No phone number required'**
  String get welcomePromiseNoPhone;

  /// No description provided for @welcomePromiseControl.
  ///
  /// In en, this message translates to:
  /// **'You\'re in control'**
  String get welcomePromiseControl;

  /// No description provided for @welcomePromiseByDesign.
  ///
  /// In en, this message translates to:
  /// **'Privacy by design'**
  String get welcomePromiseByDesign;

  /// No description provided for @welcomeTo.
  ///
  /// In en, this message translates to:
  /// **'Welcome to'**
  String get welcomeTo;

  /// No description provided for @welcomeGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get welcomeGetStarted;

  /// No description provided for @welcomeHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get welcomeHaveAccount;

  /// No description provided for @welcomeImportBackup.
  ///
  /// In en, this message translates to:
  /// **'Import from backup'**
  String get welcomeImportBackup;

  /// No description provided for @authCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authCreateTitle;

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authWelcomeBack;

  /// No description provided for @authCreateNote.
  ///
  /// In en, this message translates to:
  /// **'Pick a username. No phone number, no email — nothing to link this account to anything else.'**
  String get authCreateNote;

  /// No description provided for @authSignInNote.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your username and password.'**
  String get authSignInNote;

  /// No description provided for @authUsernameRule.
  ///
  /// In en, this message translates to:
  /// **'3–32 characters: a–z, 0–9, dot or underscore'**
  String get authUsernameRule;

  /// No description provided for @authPasswordRule.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters — this one protects everything'**
  String get authPasswordRule;

  /// No description provided for @authPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get authPasswordRequired;

  /// No description provided for @authTotpHint.
  ///
  /// In en, this message translates to:
  /// **'two-factor code'**
  String get authTotpHint;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authCreateNew.
  ///
  /// In en, this message translates to:
  /// **'Create a new account'**
  String get authCreateNew;

  /// No description provided for @authPasswordOnlyWay.
  ///
  /// In en, this message translates to:
  /// **'Your password is the only way into this account. Privio cannot reset it, because Privio cannot read anything it would unlock.'**
  String get authPasswordOnlyWay;

  /// No description provided for @pinEnterPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Enter your passphrase'**
  String get pinEnterPassphrase;

  /// No description provided for @pinEnterPasscode.
  ///
  /// In en, this message translates to:
  /// **'Enter your passcode'**
  String get pinEnterPasscode;

  /// No description provided for @pinPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get pinPassphrase;

  /// No description provided for @pinWrong.
  ///
  /// In en, this message translates to:
  /// **'That is not it.'**
  String get pinWrong;

  /// No description provided for @pinUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get pinUnlock;

  /// No description provided for @activationTitle.
  ///
  /// In en, this message translates to:
  /// **'Activate Privio'**
  String get activationTitle;

  /// No description provided for @activationSignedInNote.
  ///
  /// In en, this message translates to:
  /// **'Your account is ready. This server asks for a license key before it will relay your messages.'**
  String get activationSignedInNote;

  /// No description provided for @activationNewNote.
  ///
  /// In en, this message translates to:
  /// **'This server asks for a license key before it will relay messages. Enter yours now and it is activated as soon as your account exists.'**
  String get activationNewNote;

  /// No description provided for @activationActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activationActivate;

  /// No description provided for @activationNoKeyYet.
  ///
  /// In en, this message translates to:
  /// **'I do not have a key yet'**
  String get activationNoKeyYet;

  /// No description provided for @activationWithoutKeyNote.
  ///
  /// In en, this message translates to:
  /// **'Without a key you can create an account, sign in and read what arrives, but not send. You can enter it later under Settings › Privio License.'**
  String get activationWithoutKeyNote;

  /// No description provided for @activationFreeSoftwareNote.
  ///
  /// In en, this message translates to:
  /// **'{name} is free software under {license}. The key does not unlock the app — you already have all of it, and can build it yourself. It pays for the hosted service that relays your messages.'**
  String activationFreeSoftwareNote(String name, String license);

  /// No description provided for @backupCouldNotReach.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Privio to check the backup.'**
  String get backupCouldNotReach;

  /// No description provided for @backupDone.
  ///
  /// In en, this message translates to:
  /// **'Backed up. Privio cannot read it.'**
  String get backupDone;

  /// No description provided for @backupUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be uploaded.'**
  String get backupUploadFailed;

  /// No description provided for @backupBadKey.
  ///
  /// In en, this message translates to:
  /// **'That does not look like a recovery key.'**
  String get backupBadKey;

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Restored 1 conversation.} other{Restored {count} conversations.}}'**
  String backupRestored(int count);

  /// No description provided for @backupKeyDidNotOpen.
  ///
  /// In en, this message translates to:
  /// **'That key did not open the backup, or there is none to open.'**
  String get backupKeyDidNotOpen;

  /// No description provided for @backupLast.
  ///
  /// In en, this message translates to:
  /// **'Last backup'**
  String get backupLast;

  /// No description provided for @backupOnServer.
  ///
  /// In en, this message translates to:
  /// **'On the server'**
  String get backupOnServer;

  /// No description provided for @backupNothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get backupNothingYet;

  /// No description provided for @backupAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get backupAlways;

  /// No description provided for @backupNow.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNow;

  /// No description provided for @backupAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic backup'**
  String get backupAutomatic;

  /// No description provided for @backupIntervalDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get backupIntervalDaily;

  /// No description provided for @backupIntervalWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get backupIntervalWeekly;

  /// No description provided for @backupRecoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Recovery key'**
  String get backupRecoveryKey;

  /// No description provided for @backupRestoreRow.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup'**
  String get backupRestoreRow;

  /// No description provided for @backupSealedNote.
  ///
  /// In en, this message translates to:
  /// **'Backups are sealed on this device with your recovery key. Privio cannot open them and cannot reset the key — if you lose it, the backup is gone. Write it down somewhere safe.\n\nA backup holds your conversations, not your keys: restoring on a new device gives you your history, and that device sets up its own identity for what comes next.'**
  String get backupSealedNote;

  /// No description provided for @backupNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get backupNever;

  /// No description provided for @backupToday.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String backupToday(String time);

  /// No description provided for @backupWriteItDown.
  ///
  /// In en, this message translates to:
  /// **'Write this down. It is the only thing that opens your backups, and nobody — including Privio — can produce it again for you.'**
  String get backupWriteItDown;

  /// No description provided for @backupRestoreReplacesNote.
  ///
  /// In en, this message translates to:
  /// **'This replaces whatever is on this device with what is in the backup.'**
  String get backupRestoreReplacesNote;

  /// No description provided for @backupRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get backupRestore;

  /// No description provided for @twoFactorOnToast.
  ///
  /// In en, this message translates to:
  /// **'Two-factor is on. Keep the recovery of your authenticator safe.'**
  String get twoFactorOnToast;

  /// No description provided for @twoFactorOffToast.
  ///
  /// In en, this message translates to:
  /// **'Two-factor is off.'**
  String get twoFactorOffToast;

  /// No description provided for @twoFactorTurnOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off two-factor'**
  String get twoFactorTurnOffTitle;

  /// No description provided for @twoFactorTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get twoFactorTurnOff;

  /// No description provided for @twoFactorTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get twoFactorTurnOn;

  /// No description provided for @twoFactorServerNote.
  ///
  /// In en, this message translates to:
  /// **'The code is checked at login, on the server. It protects the account itself — someone who learns your password still cannot sign a new device in. It is not what encrypts your messages: that is the key on this device, and no code can replace it.'**
  String get twoFactorServerNote;

  /// No description provided for @twoFactorOffBody.
  ///
  /// In en, this message translates to:
  /// **'With two-factor on, signing in needs a six-digit code from your authenticator app as well as your password.'**
  String get twoFactorOffBody;

  /// No description provided for @twoFactorSetUp.
  ///
  /// In en, this message translates to:
  /// **'Set it up'**
  String get twoFactorSetUp;

  /// No description provided for @twoFactorScanThis.
  ///
  /// In en, this message translates to:
  /// **'Scan this'**
  String get twoFactorScanThis;

  /// No description provided for @twoFactorScanNote.
  ///
  /// In en, this message translates to:
  /// **'Add it to your authenticator app, then type the code it shows. Two-factor is not on until that code has been checked.'**
  String get twoFactorScanNote;

  /// No description provided for @twoFactorTypeKey.
  ///
  /// In en, this message translates to:
  /// **'Or type this key'**
  String get twoFactorTypeKey;

  /// No description provided for @twoFactorKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Key copied.'**
  String get twoFactorKeyCopied;

  /// No description provided for @twoFactorOnBody.
  ///
  /// In en, this message translates to:
  /// **'Signing in asks for a code from your authenticator app.'**
  String get twoFactorOnBody;

  /// No description provided for @passcodeFourDigits.
  ///
  /// In en, this message translates to:
  /// **'4 digits'**
  String get passcodeFourDigits;

  /// No description provided for @passcodeSixDigits.
  ///
  /// In en, this message translates to:
  /// **'6 digits'**
  String get passcodeSixDigits;

  /// No description provided for @passcodeFourDigitsNote.
  ///
  /// In en, this message translates to:
  /// **'Ten thousand combinations. Quick, and enough against someone who picks the phone up.'**
  String get passcodeFourDigitsNote;

  /// No description provided for @passcodeSixDigitsNote.
  ///
  /// In en, this message translates to:
  /// **'A million combinations, and still a keypad.'**
  String get passcodeSixDigitsNote;

  /// No description provided for @passcodePhraseNote.
  ///
  /// In en, this message translates to:
  /// **'Letters, and digits or symbols if you want them. The only one of the three that stands up to someone with the phone and time.'**
  String get passcodePhraseNote;

  /// No description provided for @passcodeNeedsFourDigits.
  ///
  /// In en, this message translates to:
  /// **'Four digits.'**
  String get passcodeNeedsFourDigits;

  /// No description provided for @passcodeNeedsSixDigits.
  ///
  /// In en, this message translates to:
  /// **'Six digits.'**
  String get passcodeNeedsSixDigits;

  /// No description provided for @passcodePhraseTooShort.
  ///
  /// In en, this message translates to:
  /// **'At least {count} characters.'**
  String passcodePhraseTooShort(int count);

  /// No description provided for @passcodePhraseNeedsLetter.
  ///
  /// In en, this message translates to:
  /// **'A passphrase needs at least one letter. Digits and symbols are welcome alongside it.'**
  String get passcodePhraseNeedsLetter;

  /// No description provided for @lockEntriesDiffer.
  ///
  /// In en, this message translates to:
  /// **'The two entries are not the same.'**
  String get lockEntriesDiffer;

  /// No description provided for @lockOnToast.
  ///
  /// In en, this message translates to:
  /// **'App lock on. Privio asks for it when it comes back.'**
  String get lockOnToast;

  /// No description provided for @lockOffToast.
  ///
  /// In en, this message translates to:
  /// **'App lock off.'**
  String get lockOffToast;

  /// No description provided for @lockTurnOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off the app lock?'**
  String get lockTurnOffTitle;

  /// No description provided for @lockTurnOffBody.
  ///
  /// In en, this message translates to:
  /// **'Anyone holding an unlocked phone reaches your messages. A duress code set for the lock screen is removed with it.'**
  String get lockTurnOffBody;

  /// No description provided for @lockTurnOffRow.
  ///
  /// In en, this message translates to:
  /// **'Turn off the app lock'**
  String get lockTurnOffRow;

  /// No description provided for @lockWhatItIsNote.
  ///
  /// In en, this message translates to:
  /// **'A passcode on this device, asked for whenever Privio comes back to the foreground. It is not your account password and it never leaves the phone — it guards the history already encrypted on it.'**
  String get lockWhatItIsNote;

  /// No description provided for @lockNoBiometricsNote.
  ///
  /// In en, this message translates to:
  /// **'There is no face or fingerprint option. Those are the one credential someone can hold a phone up to your face to use, or press your finger onto while you are asleep — and in several places a court can order them where it cannot order a passcode.'**
  String get lockNoBiometricsNote;

  /// No description provided for @lockChangePasscode.
  ///
  /// In en, this message translates to:
  /// **'Change the passcode'**
  String get lockChangePasscode;

  /// No description provided for @lockChoosePasscode.
  ///
  /// In en, this message translates to:
  /// **'Choose a passcode'**
  String get lockChoosePasscode;

  /// No description provided for @lockAgain.
  ///
  /// In en, this message translates to:
  /// **'Again'**
  String get lockAgain;

  /// No description provided for @lockChangeIt.
  ///
  /// In en, this message translates to:
  /// **'Change it'**
  String get lockChangeIt;

  /// No description provided for @lockTurnItOn.
  ///
  /// In en, this message translates to:
  /// **'Turn it on'**
  String get lockTurnItOn;

  /// No description provided for @lockForgettingNote.
  ///
  /// In en, this message translates to:
  /// **'Forgetting it means signing in again, which is a new device to the server: what was already delivered here is gone unless it is in a backup. There is no reset, because a reset anyone could ask for would not be a lock.'**
  String get lockForgettingNote;

  /// No description provided for @duressNoLockNote.
  ///
  /// In en, this message translates to:
  /// **'At the lock screen it does nothing yet, because there is no app lock on this device. Turn one on under Screen Lock, and a duress code shaped like that lock works there too — which is where a phone that is already signed in gets taken.'**
  String get duressNoLockNote;

  /// No description provided for @duressShapeNote.
  ///
  /// In en, this message translates to:
  /// **'This device unlocks with {kind}. A duress code of the same shape can be typed at the lock screen, where it destroys instead of unlocking. Any other shape works at sign-in only.'**
  String duressShapeNote(String kind);

  /// No description provided for @duressMatchesLock.
  ///
  /// In en, this message translates to:
  /// **'This one matches the lock on this device, so it works at the lock screen as well as at sign-in.'**
  String get duressMatchesLock;

  /// No description provided for @duressDoesNotMatchLock.
  ///
  /// In en, this message translates to:
  /// **'This one does not match the lock on this device ({kind}), so it works at sign-in only — the lock screen has nowhere to type it.'**
  String duressDoesNotMatchLock(String kind);

  /// No description provided for @duressAtLeastFour.
  ///
  /// In en, this message translates to:
  /// **'Use at least four characters.'**
  String get duressAtLeastFour;

  /// No description provided for @duressCodesDiffer.
  ///
  /// In en, this message translates to:
  /// **'The two codes are not the same.'**
  String get duressCodesDiffer;

  /// No description provided for @duressSameAsUnlock.
  ///
  /// In en, this message translates to:
  /// **'That is the code that unlocks this device. A duress code has to be different: the lock screen checks it first, so the two being the same would destroy the account every time you unlocked — without saying so.'**
  String get duressSameAsUnlock;

  /// No description provided for @duressSetBoth.
  ///
  /// In en, this message translates to:
  /// **'Duress code set. It destroys the account at sign-in and at the lock screen.'**
  String get duressSetBoth;

  /// No description provided for @duressSetSignInOnly.
  ///
  /// In en, this message translates to:
  /// **'Duress code set. Typing it at sign-in destroys the account.'**
  String get duressSetSignInOnly;

  /// No description provided for @duressRemoved.
  ///
  /// In en, this message translates to:
  /// **'Duress code removed.'**
  String get duressRemoved;

  /// No description provided for @duressRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the duress code'**
  String get duressRemoveTitle;

  /// No description provided for @duressWarning.
  ///
  /// In en, this message translates to:
  /// **'Typing this code instead of your password at sign-in destroys the account: every device, every message still waiting, your contacts, your group memberships, your backup. There is no undo, and no confirmation — that is the point.'**
  String get duressWarning;

  /// No description provided for @duressIsSet.
  ///
  /// In en, this message translates to:
  /// **'A duress code is set'**
  String get duressIsSet;

  /// No description provided for @duressCannotShow.
  ///
  /// In en, this message translates to:
  /// **'Privio cannot show it to you — it is stored the way a password is. Setting a new one below replaces it.'**
  String get duressCannotShow;

  /// No description provided for @duressRemoveIt.
  ///
  /// In en, this message translates to:
  /// **'Remove it'**
  String get duressRemoveIt;

  /// No description provided for @duressReplaceIt.
  ///
  /// In en, this message translates to:
  /// **'Replace it'**
  String get duressReplaceIt;

  /// No description provided for @duressSetOne.
  ///
  /// In en, this message translates to:
  /// **'Set a duress code'**
  String get duressSetOne;

  /// No description provided for @duressAccountPassword.
  ///
  /// In en, this message translates to:
  /// **'Your Privio account password'**
  String get duressAccountPassword;

  /// No description provided for @duressLooksLikePin.
  ///
  /// In en, this message translates to:
  /// **'That is shorter than an account password. This field wants the password you chose when you created the account — not the PIN that unlocks the app.'**
  String get duressLooksLikePin;

  /// No description provided for @duressCodeField.
  ///
  /// In en, this message translates to:
  /// **'Duress code'**
  String get duressCodeField;

  /// No description provided for @duressCodeAgain.
  ///
  /// In en, this message translates to:
  /// **'Duress code again'**
  String get duressCodeAgain;

  /// No description provided for @duressReplaceCode.
  ///
  /// In en, this message translates to:
  /// **'Replace the code'**
  String get duressReplaceCode;

  /// No description provided for @duressSetCode.
  ///
  /// In en, this message translates to:
  /// **'Set the code'**
  String get duressSetCode;

  /// No description provided for @duressWhatItDoesNotDo.
  ///
  /// In en, this message translates to:
  /// **'What it does not do: the account name stays taken, so nobody can claim it afterwards, and it cannot reach a different device that is already signed in somewhere else. Anyone watching sees the attempt refused exactly as a mistyped password or PIN is refused.'**
  String get duressWhatItDoesNotDo;

  /// No description provided for @disguiseIntro.
  ///
  /// In en, this message translates to:
  /// **'A locked Privio opens to a working calculator instead of a lock screen. Any sum that comes to your passcode opens Privio when you press =, so the code itself never has to appear on screen. Every other sum is just a sum.'**
  String get disguiseIntro;

  /// No description provided for @disguiseOpenTo.
  ///
  /// In en, this message translates to:
  /// **'Open to'**
  String get disguiseOpenTo;

  /// No description provided for @disguiseLockScreen.
  ///
  /// In en, this message translates to:
  /// **'The lock screen'**
  String get disguiseLockScreen;

  /// No description provided for @disguiseCalculatorNamed.
  ///
  /// In en, this message translates to:
  /// **'{name} calculator'**
  String disguiseCalculatorNamed(String name);

  /// No description provided for @disguisePickNote.
  ///
  /// In en, this message translates to:
  /// **'Pick the one your phone already ships. A calculator that does not look like the usual one is the thing somebody notices.'**
  String get disguisePickNote;

  /// No description provided for @disguiseSeeIt.
  ///
  /// In en, this message translates to:
  /// **'See it'**
  String get disguiseSeeIt;

  /// No description provided for @disguiseErrorSuffix.
  ///
  /// In en, this message translates to:
  /// **'{reason} The lock screen changed anyway; the home screen did not.'**
  String disguiseErrorSuffix(String reason);

  /// No description provided for @disguiseNoLock.
  ///
  /// In en, this message translates to:
  /// **'There is no screen lock on this device yet, so there is no code to type into a calculator.'**
  String get disguiseNoLock;

  /// No description provided for @disguisePhraseLock.
  ///
  /// In en, this message translates to:
  /// **'Your screen lock is a passphrase. A calculator has ten keys and no letters, so there is no way to type it in. Switch the lock to 4 or 6 digits to use a disguise.'**
  String get disguisePhraseLock;

  /// No description provided for @disguiseOnHomeScreen.
  ///
  /// In en, this message translates to:
  /// **'On the home screen'**
  String get disguiseOnHomeScreen;

  /// No description provided for @disguiseWhatItDoesNotDo.
  ///
  /// In en, this message translates to:
  /// **'What this does not do'**
  String get disguiseWhatItDoesNotDo;

  /// No description provided for @disguiseNotADefence.
  ///
  /// In en, this message translates to:
  /// **'It is not a defence against anyone who has the phone for long. The app is still installed, and its size, its files and its network traffic are all still there to find by anyone who looks properly. What it is good at is the ordinary case — a screen glanced at, or a phone handed over unlocked.'**
  String get disguiseNotADefence;

  /// No description provided for @disguiseHomeScreenChanges.
  ///
  /// In en, this message translates to:
  /// **'On the home screen and in the app drawer, Privio becomes a calculator icon called \"Calculator\". Your launcher may take a few seconds to redraw, and an icon you pinned to the home screen yourself may need pinning again. Turning the disguise off puts it back.\n\nAndroid\'s own app list — Settings, app info, the name shown when Privio asks for a permission — still says Privio. That name is set when the app is built and no app can change it while running.'**
  String get disguiseHomeScreenChanges;

  /// No description provided for @disguiseIconUnchanged.
  ///
  /// In en, this message translates to:
  /// **'On this device the icon and the name do not change — only what the app opens to. Someone going through the home screen still finds Privio by name.'**
  String get disguiseIconUnchanged;

  /// No description provided for @disguiseClosePreview.
  ///
  /// In en, this message translates to:
  /// **'Close preview'**
  String get disguiseClosePreview;

  /// No description provided for @licenseActivatedToast.
  ///
  /// In en, this message translates to:
  /// **'Activated. This license now belongs to your account.'**
  String get licenseActivatedToast;

  /// No description provided for @licenseNotCheckedTitle.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet'**
  String get licenseNotCheckedTitle;

  /// No description provided for @licenseNotCheckedBody.
  ///
  /// In en, this message translates to:
  /// **'Privio has not been able to ask the server about this account yet. Pull the app back online and reopen this screen.'**
  String get licenseNotCheckedBody;

  /// No description provided for @licenseNotNeededTitle.
  ///
  /// In en, this message translates to:
  /// **'No license needed here'**
  String get licenseNotNeededTitle;

  /// No description provided for @licenseNotNeededBody.
  ///
  /// In en, this message translates to:
  /// **'This server does not require one. Licensing is for the hosted Privio service — a license for infrastructure you already run would mean nothing.'**
  String get licenseNotNeededBody;

  /// No description provided for @licenseStoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Handled by the store'**
  String get licenseStoreTitle;

  /// No description provided for @licenseStoreBody.
  ///
  /// In en, this message translates to:
  /// **'This build was paid for through the app store it came from, so there is no key to enter. If it is not active, restore your purchase in {store}.'**
  String licenseStoreBody(String store);

  /// No description provided for @licenseOnePurchaseNote.
  ///
  /// In en, this message translates to:
  /// **'One purchase, one key, one account, for good. A redeemed key is bound to the account that redeemed it and cannot be moved or used again.'**
  String get licenseOnePurchaseNote;

  /// No description provided for @licenseEnterTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your license key'**
  String get licenseEnterTitle;

  /// No description provided for @licenseEnterBody.
  ///
  /// In en, this message translates to:
  /// **'Buy a key at getprivio.com/license, then type it here. Until it is activated this account can sign in and read what has already arrived, but not send.'**
  String get licenseEnterBody;

  /// No description provided for @licenseActivated.
  ///
  /// In en, this message translates to:
  /// **'Activated'**
  String get licenseActivated;

  /// No description provided for @licenseRedeemedOn.
  ///
  /// In en, this message translates to:
  /// **'Redeemed on {date}.'**
  String licenseRedeemedOn(String date);

  /// No description provided for @licenseFromAppStore.
  ///
  /// In en, this message translates to:
  /// **'Bought through the App Store.'**
  String get licenseFromAppStore;

  /// No description provided for @licenseFromPlay.
  ///
  /// In en, this message translates to:
  /// **'Bought through Google Play.'**
  String get licenseFromPlay;

  /// No description provided for @licenseFromKey.
  ///
  /// In en, this message translates to:
  /// **'Activated with a license key. Lifetime access, no renewals.'**
  String get licenseFromKey;

  /// No description provided for @safetyTrustedToast.
  ///
  /// In en, this message translates to:
  /// **'The new key is trusted. Compare the number again before you rely on it.'**
  String get safetyTrustedToast;

  /// No description provided for @safetyMatches.
  ///
  /// In en, this message translates to:
  /// **'That matches one of the numbers below.'**
  String get safetyMatches;

  /// No description provided for @safetyNoMatch.
  ///
  /// In en, this message translates to:
  /// **'That matches none of the numbers below.'**
  String get safetyNoMatch;

  /// No description provided for @safetyNothingYet.
  ///
  /// In en, this message translates to:
  /// **'There is nothing to compare yet. A number exists once you and {name} have exchanged a message, because only then has this device pinned a key of theirs.'**
  String safetyNothingYet(String name);

  /// No description provided for @safetyReadThese.
  ///
  /// In en, this message translates to:
  /// **'Read these digits to {name} — on a call, or in person. If they see the same ones, no one is sitting between you. If they do not, stop using this chat for anything you would not say in public.'**
  String safetyReadThese(String name);

  /// No description provided for @safetyMarkNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Mark as not verified'**
  String get safetyMarkNotVerified;

  /// No description provided for @safetyMarkVerified.
  ///
  /// In en, this message translates to:
  /// **'Mark as verified'**
  String get safetyMarkVerified;

  /// No description provided for @safetyMarkNote.
  ///
  /// In en, this message translates to:
  /// **'Marking this verified records the exact keys on screen. If any of them changes, or a new device joins {name}, the mark goes back to changed on its own — it is a record of what you checked, not a promise about what happens next.'**
  String safetyMarkNote(String name);

  /// No description provided for @safetyVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get safetyVerified;

  /// No description provided for @safetyChangedSince.
  ///
  /// In en, this message translates to:
  /// **'Changed since you checked'**
  String get safetyChangedSince;

  /// No description provided for @safetyNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get safetyNotVerified;

  /// No description provided for @safetyTheirDevice.
  ///
  /// In en, this message translates to:
  /// **'Their device {index}'**
  String safetyTheirDevice(int index);

  /// No description provided for @safetyCompareTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare a number they sent you'**
  String get safetyCompareTitle;

  /// No description provided for @safetyCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get safetyCompare;

  /// No description provided for @safetyKeyNotYours.
  ///
  /// In en, this message translates to:
  /// **'The key on the server is not the one you had'**
  String get safetyKeyNotYours;

  /// No description provided for @safetyRefusedUntilDecide.
  ///
  /// In en, this message translates to:
  /// **'Messages to this chat are refused until you decide. Reinstalling Privio, or signing in on a new device, does this legitimately and is the usual reason. So does a server handing you a key of its own, which looks exactly the same from here — which is why the number below is worth comparing again afterwards.'**
  String get safetyRefusedUntilDecide;

  /// No description provided for @safetyTrustNewKey.
  ///
  /// In en, this message translates to:
  /// **'Trust the new key'**
  String get safetyTrustNewKey;

  /// No description provided for @safetyKeyChangedArrived.
  ///
  /// In en, this message translates to:
  /// **'Their key changed, and a message with it arrived'**
  String get safetyKeyChangedArrived;

  /// No description provided for @safetyKeyChangedBody.
  ///
  /// In en, this message translates to:
  /// **'The new key is already in use — a message that brings one cannot be turned away without handing anyone a way to silence a chat. Reinstalling does this. So does someone stepping in. The number below is the difference, and it is only worth anything compared out loud.'**
  String get safetyKeyChangedBody;

  /// No description provided for @channelsCouldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open that link'**
  String get channelsCouldNotOpenLink;

  /// No description provided for @channelsJoinWithLink.
  ///
  /// In en, this message translates to:
  /// **'Join with a link'**
  String get channelsJoinWithLink;

  /// No description provided for @channelsNewChannel.
  ///
  /// In en, this message translates to:
  /// **'New channel'**
  String get channelsNewChannel;

  /// No description provided for @channelsTabFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get channelsTabFollowing;

  /// No description provided for @channelsTabDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get channelsTabDiscover;

  /// No description provided for @channelsSearchMine.
  ///
  /// In en, this message translates to:
  /// **'Search your channels'**
  String get channelsSearchMine;

  /// No description provided for @channelsSearchPublic.
  ///
  /// In en, this message translates to:
  /// **'Search public channels'**
  String get channelsSearchPublic;

  /// No description provided for @channelsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No channels yet'**
  String get channelsEmptyTitle;

  /// No description provided for @channelsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Create one, or find a public channel under Discover.'**
  String get channelsEmptyBody;

  /// No description provided for @channelsNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get channelsNothingFound;

  /// No description provided for @channelsDiscoverEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Search public channels by name, handle or description. Private channels never appear here.'**
  String get channelsDiscoverEmptyBody;

  /// No description provided for @channelsHandleAndMembers.
  ///
  /// In en, this message translates to:
  /// **'@{handle}  ·  {members}'**
  String channelsHandleAndMembers(String handle, String members);

  /// No description provided for @channelsJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join a channel'**
  String get channelsJoinTitle;

  /// No description provided for @channelsJoinNote.
  ///
  /// In en, this message translates to:
  /// **'Paste a channel link. It shows you the channel; joining is a button there. Joining does not hand you the key either — a member who has it sends it to your device, encrypted, right after.'**
  String get channelsJoinNote;

  /// No description provided for @categoryNews.
  ///
  /// In en, this message translates to:
  /// **'News'**
  String get categoryNews;

  /// No description provided for @categoryTechnology.
  ///
  /// In en, this message translates to:
  /// **'Technology'**
  String get categoryTechnology;

  /// No description provided for @categoryCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get categoryCommunity;

  /// No description provided for @categoryEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get categoryEducation;

  /// No description provided for @categoryCulture.
  ///
  /// In en, this message translates to:
  /// **'Culture'**
  String get categoryCulture;

  /// No description provided for @newChannelPictureUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Privio could not read {name}. Try a different picture.'**
  String newChannelPictureUnreadable(String name);

  /// No description provided for @newChannelCouldNotCreate.
  ///
  /// In en, this message translates to:
  /// **'Could not create the channel'**
  String get newChannelCouldNotCreate;

  /// No description provided for @newChannelWithoutPicture.
  ///
  /// In en, this message translates to:
  /// **'The channel was created without the picture.'**
  String get newChannelWithoutPicture;

  /// No description provided for @newChannelCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get newChannelCreate;

  /// No description provided for @newChannelPublicPictureNote.
  ///
  /// In en, this message translates to:
  /// **'A public channel\'s picture is shown on its web page and in link previews, so it is stored unencrypted — the same as its name, handle and description.'**
  String get newChannelPublicPictureNote;

  /// No description provided for @newChannelHandle.
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get newChannelHandle;

  /// No description provided for @newChannelHandleRule.
  ///
  /// In en, this message translates to:
  /// **'3-32 characters: a-z, 0-9, underscore or dot'**
  String get newChannelHandleRule;

  /// No description provided for @newChannelCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get newChannelCategory;

  /// No description provided for @newChannelRestrictSaving.
  ///
  /// In en, this message translates to:
  /// **'Restrict saving'**
  String get newChannelRestrictSaving;

  /// No description provided for @newChannelRestrictNote.
  ///
  /// In en, this message translates to:
  /// **'Asks readers’ apps not to save or forward posts. A request, not a guarantee — anyone who can read a post can photograph it.'**
  String get newChannelRestrictNote;

  /// No description provided for @newChannelPrivateBody.
  ///
  /// In en, this message translates to:
  /// **'Reachable only with an invite link. The name is uploaded encrypted, so the server stores a channel it cannot name.'**
  String get newChannelPrivateBody;

  /// No description provided for @newChannelPublicBody.
  ///
  /// In en, this message translates to:
  /// **'Listed and searchable. The name, handle and description are public by definition; the posts stay end-to-end encrypted.'**
  String get newChannelPublicBody;

  /// No description provided for @membersCouldNotLift.
  ///
  /// In en, this message translates to:
  /// **'Could not lift that.'**
  String get membersCouldNotLift;

  /// No description provided for @membersCouldNotChange.
  ///
  /// In en, this message translates to:
  /// **'Could not change that member'**
  String get membersCouldNotChange;

  /// No description provided for @membersTitle.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersTitle;

  /// No description provided for @membersWhoRuns.
  ///
  /// In en, this message translates to:
  /// **'Who runs this channel'**
  String get membersWhoRuns;

  /// No description provided for @membersSilencedCanRead.
  ///
  /// In en, this message translates to:
  /// **'Can read, cannot post or react'**
  String get membersSilencedCanRead;

  /// No description provided for @membersAllowAgain.
  ///
  /// In en, this message translates to:
  /// **'Allow again'**
  String get membersAllowAgain;

  /// No description provided for @membersRoleAndPermissions.
  ///
  /// In en, this message translates to:
  /// **'Role and permissions'**
  String get membersRoleAndPermissions;

  /// No description provided for @membersOwnerEverything.
  ///
  /// In en, this message translates to:
  /// **'Owner · everything'**
  String get membersOwnerEverything;

  /// No description provided for @membersSubscriberReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Subscriber · read only'**
  String get membersSubscriberReadOnly;

  /// No description provided for @membersGrantPost.
  ///
  /// In en, this message translates to:
  /// **'post'**
  String get membersGrantPost;

  /// No description provided for @membersGrantEdit.
  ///
  /// In en, this message translates to:
  /// **'edit'**
  String get membersGrantEdit;

  /// No description provided for @membersGrantDeletePosts.
  ///
  /// In en, this message translates to:
  /// **'delete posts'**
  String get membersGrantDeletePosts;

  /// No description provided for @membersGrantManageMembers.
  ///
  /// In en, this message translates to:
  /// **'manage members'**
  String get membersGrantManageMembers;

  /// No description provided for @membersGrantDeleteChannel.
  ///
  /// In en, this message translates to:
  /// **'delete channel'**
  String get membersGrantDeleteChannel;

  /// No description provided for @membersRoleLine.
  ///
  /// In en, this message translates to:
  /// **'{role} · {granted}'**
  String membersRoleLine(String role, String granted);

  /// No description provided for @membersSubscriber.
  ///
  /// In en, this message translates to:
  /// **'Subscriber'**
  String get membersSubscriber;

  /// No description provided for @membersTogglePost.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get membersTogglePost;

  /// No description provided for @membersToggleEditChannel.
  ///
  /// In en, this message translates to:
  /// **'Edit the channel'**
  String get membersToggleEditChannel;

  /// No description provided for @membersToggleDeletePosts.
  ///
  /// In en, this message translates to:
  /// **'Delete posts'**
  String get membersToggleDeletePosts;

  /// No description provided for @membersToggleManageMembers.
  ///
  /// In en, this message translates to:
  /// **'Manage members'**
  String get membersToggleManageMembers;

  /// No description provided for @membersToggleDeleteChannel.
  ///
  /// In en, this message translates to:
  /// **'Delete the channel'**
  String get membersToggleDeleteChannel;

  /// No description provided for @membersGreyedOutNote.
  ///
  /// In en, this message translates to:
  /// **'Greyed-out permissions are ones you do not hold yourself. Nobody can hand out more than they have.'**
  String get membersGreyedOutNote;

  /// No description provided for @membersSubscriberNote.
  ///
  /// In en, this message translates to:
  /// **'A subscriber reads the channel and nothing else.'**
  String get membersSubscriberNote;

  /// No description provided for @membersRemoveFromChannel.
  ///
  /// In en, this message translates to:
  /// **'Remove from channel'**
  String get membersRemoveFromChannel;

  /// No description provided for @membersStoppedFromPosting.
  ///
  /// In en, this message translates to:
  /// **'Stopped from posting'**
  String get membersStoppedFromPosting;

  /// No description provided for @membersAudienceNote.
  ///
  /// In en, this message translates to:
  /// **'Only the people who run this channel are listed. Who reads it is not shown to other readers — including you.'**
  String get membersAudienceNote;

  /// No description provided for @channelPicture.
  ///
  /// In en, this message translates to:
  /// **'Picture'**
  String get channelPicture;

  /// No description provided for @channelLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied.'**
  String get channelLinkCopied;

  /// No description provided for @adminsMakeSomebodyFirst.
  ///
  /// In en, this message translates to:
  /// **'Make somebody an admin first.'**
  String get adminsMakeSomebodyFirst;

  /// No description provided for @subscribersCouldNotAddAnybody.
  ///
  /// In en, this message translates to:
  /// **'Could not add anybody.'**
  String get subscribersCouldNotAddAnybody;

  /// No description provided for @subscribersAddCount.
  ///
  /// In en, this message translates to:
  /// **'Add {count}'**
  String subscribersAddCount(int count);

  /// No description provided for @threadCouldNotPost.
  ///
  /// In en, this message translates to:
  /// **'Could not post that comment.'**
  String get threadCouldNotPost;

  /// No description provided for @threadCouldNotRemove.
  ///
  /// In en, this message translates to:
  /// **'Could not remove that comment.'**
  String get threadCouldNotRemove;

  /// No description provided for @threadStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop {name} posting?'**
  String threadStopTitle(String name);

  /// No description provided for @threadStopBody.
  ///
  /// In en, this message translates to:
  /// **'They stay in the channel and can go on reading it. They cannot comment or react until you undo this.\n\nRemoving them from the channel is the other, heavier thing: that rotates the key and takes their reading with it.'**
  String get threadStopBody;

  /// No description provided for @threadStopThem.
  ///
  /// In en, this message translates to:
  /// **'Stop them'**
  String get threadStopThem;

  /// No description provided for @threadStopThemPosting.
  ///
  /// In en, this message translates to:
  /// **'Stop them posting'**
  String get threadStopThemPosting;

  /// No description provided for @threadCouldNotDoThat.
  ///
  /// In en, this message translates to:
  /// **'Could not do that.'**
  String get threadCouldNotDoThat;

  /// No description provided for @threadTitle.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get threadTitle;

  /// No description provided for @threadUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get threadUnknown;

  /// No description provided for @threadEncryptedNoKey.
  ///
  /// In en, this message translates to:
  /// **'Encrypted — this device has no key for it.'**
  String get threadEncryptedNoKey;

  /// No description provided for @threadCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get threadCommentHint;

  /// No description provided for @threadNoKeyForChannel.
  ///
  /// In en, this message translates to:
  /// **'No key for this channel'**
  String get threadNoKeyForChannel;

  /// No description provided for @threadDeletedAccount.
  ///
  /// In en, this message translates to:
  /// **'Deleted account'**
  String get threadDeletedAccount;

  /// No description provided for @threadEncryptedNoKeyHere.
  ///
  /// In en, this message translates to:
  /// **'Encrypted — no key for it on this device.'**
  String get threadEncryptedNoKeyHere;

  /// No description provided for @threadEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get threadEmptyTitle;

  /// No description provided for @threadEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Comments are encrypted with the channel key, like the posts. The server stores them and cannot read them.'**
  String get threadEmptyBody;

  /// No description provided for @threadStoppedToast.
  ///
  /// In en, this message translates to:
  /// **'{name} can still read the channel, but not post in it.'**
  String threadStoppedToast(String name);

  /// No description provided for @threadThem.
  ///
  /// In en, this message translates to:
  /// **'They'**
  String get threadThem;

  /// No description provided for @threadThemObject.
  ///
  /// In en, this message translates to:
  /// **'them'**
  String get threadThemObject;

  /// No description provided for @feedCouldNotAskForKey.
  ///
  /// In en, this message translates to:
  /// **'Could not ask for the key.'**
  String get feedCouldNotAskForKey;

  /// No description provided for @feedKeyArrived.
  ///
  /// In en, this message translates to:
  /// **'The key arrived. You can post again.'**
  String get feedKeyArrived;

  /// No description provided for @feedAskedAgain.
  ///
  /// In en, this message translates to:
  /// **'Asked again. The key is delivered by another member, so it arrives when one of them is online.'**
  String get feedAskedAgain;

  /// No description provided for @feedCouldNotJoin.
  ///
  /// In en, this message translates to:
  /// **'Could not join'**
  String get feedCouldNotJoin;

  /// No description provided for @feedPickFutureTime.
  ///
  /// In en, this message translates to:
  /// **'Pick a time that has not gone yet.'**
  String get feedPickFutureTime;

  /// No description provided for @feedCouldNotPublishPoll.
  ///
  /// In en, this message translates to:
  /// **'Could not publish that poll.'**
  String get feedCouldNotPublishPoll;

  /// No description provided for @feedScheduledFor.
  ///
  /// In en, this message translates to:
  /// **'Scheduled for {when}. It is under \"Scheduled\" until then.'**
  String feedScheduledFor(String when);

  /// No description provided for @feedCouldNotPublish.
  ///
  /// In en, this message translates to:
  /// **'Could not publish'**
  String get feedCouldNotPublish;

  /// No description provided for @feedCouldNotChangeLink.
  ///
  /// In en, this message translates to:
  /// **'Could not change the link.'**
  String get feedCouldNotChangeLink;

  /// No description provided for @feedOldLinkDead.
  ///
  /// In en, this message translates to:
  /// **'The old link is dead. Anyone holding it will need the new one.'**
  String get feedOldLinkDead;

  /// No description provided for @feedSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get feedSaved;

  /// No description provided for @feedCouldNotChangeReactions.
  ///
  /// In en, this message translates to:
  /// **'Could not change the reactions.'**
  String get feedCouldNotChangeReactions;

  /// No description provided for @feedCouldNotChangePost.
  ///
  /// In en, this message translates to:
  /// **'Could not change the post.'**
  String get feedCouldNotChangePost;

  /// No description provided for @feedPublished.
  ///
  /// In en, this message translates to:
  /// **'Published.'**
  String get feedPublished;

  /// No description provided for @feedCouldNotPublishIt.
  ///
  /// In en, this message translates to:
  /// **'Could not publish it.'**
  String get feedCouldNotPublishIt;

  /// No description provided for @feedCouldNotChangeThat.
  ///
  /// In en, this message translates to:
  /// **'Could not change that.'**
  String get feedCouldNotChangeThat;

  /// No description provided for @feedCommentsOn.
  ///
  /// In en, this message translates to:
  /// **'Readers can comment on posts now.'**
  String get feedCommentsOn;

  /// No description provided for @feedCommentsOff.
  ///
  /// In en, this message translates to:
  /// **'Comments are off. Existing threads are hidden, not deleted.'**
  String get feedCommentsOff;

  /// No description provided for @feedCouldNotReadNumbers.
  ///
  /// In en, this message translates to:
  /// **'Could not read the numbers.'**
  String get feedCouldNotReadNumbers;

  /// No description provided for @feedNobodyToHandTo.
  ///
  /// In en, this message translates to:
  /// **'There is nobody else in this channel to hand it to.'**
  String get feedNobodyToHandTo;

  /// No description provided for @feedOwnsNow.
  ///
  /// In en, this message translates to:
  /// **'{name} owns this channel now. You are an admin in it.'**
  String feedOwnsNow(String name);

  /// No description provided for @feedCouldNotHandOn.
  ///
  /// In en, this message translates to:
  /// **'Could not hand the channel on.'**
  String get feedCouldNotHandOn;

  /// No description provided for @feedReported.
  ///
  /// In en, this message translates to:
  /// **'Reported. Thank you.'**
  String get feedReported;

  /// No description provided for @feedCouldNotSendThat.
  ///
  /// In en, this message translates to:
  /// **'Could not send that.'**
  String get feedCouldNotSendThat;

  /// No description provided for @feedRemovePicture.
  ///
  /// In en, this message translates to:
  /// **'Remove picture'**
  String get feedRemovePicture;

  /// No description provided for @feedPictureRemoved.
  ///
  /// In en, this message translates to:
  /// **'Picture removed.'**
  String get feedPictureRemoved;

  /// No description provided for @feedCouldNotRemovePicture.
  ///
  /// In en, this message translates to:
  /// **'Could not remove the picture.'**
  String get feedCouldNotRemovePicture;

  /// No description provided for @feedCouldNotSetPicture.
  ///
  /// In en, this message translates to:
  /// **'Could not set the picture.'**
  String get feedCouldNotSetPicture;

  /// No description provided for @feedPictureUpdated.
  ///
  /// In en, this message translates to:
  /// **'Channel picture updated.'**
  String get feedPictureUpdated;

  /// No description provided for @feedDeleteChannelTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete channel?'**
  String get feedDeleteChannelTitle;

  /// No description provided for @feedDeleteChannelBody.
  ///
  /// In en, this message translates to:
  /// **'The channel and every post in it are removed for everyone. Nothing undoes this.'**
  String get feedDeleteChannelBody;

  /// No description provided for @feedCouldNotDeleteChannel.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the channel'**
  String get feedCouldNotDeleteChannel;

  /// No description provided for @feedCouldNotLeaveChannel.
  ///
  /// In en, this message translates to:
  /// **'Could not leave the channel'**
  String get feedCouldNotLeaveChannel;

  /// No description provided for @feedScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get feedScheduled;

  /// No description provided for @feedRequestsToJoin.
  ///
  /// In en, this message translates to:
  /// **'Requests to join'**
  String get feedRequestsToJoin;

  /// No description provided for @feedChannelPicture.
  ///
  /// In en, this message translates to:
  /// **'Channel picture'**
  String get feedChannelPicture;

  /// No description provided for @feedAddPicture.
  ///
  /// In en, this message translates to:
  /// **'Add a picture'**
  String get feedAddPicture;

  /// No description provided for @feedTurnCommentsOff.
  ///
  /// In en, this message translates to:
  /// **'Turn comments off'**
  String get feedTurnCommentsOff;

  /// No description provided for @feedTurnCommentsOn.
  ///
  /// In en, this message translates to:
  /// **'Turn comments on'**
  String get feedTurnCommentsOn;

  /// No description provided for @feedHandChannelOn.
  ///
  /// In en, this message translates to:
  /// **'Hand this channel on'**
  String get feedHandChannelOn;

  /// No description provided for @feedDeleteChannel.
  ///
  /// In en, this message translates to:
  /// **'Delete channel'**
  String get feedDeleteChannel;

  /// No description provided for @dayToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dayToday;

  /// No description provided for @dayYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dayYesterday;

  /// No description provided for @feedNoSearchResultsBody.
  ///
  /// In en, this message translates to:
  /// **'The search runs on this device, over the posts it has already loaded and could open. The server cannot search them: it holds them sealed.'**
  String get feedNoSearchResultsBody;

  /// No description provided for @feedEdited.
  ///
  /// In en, this message translates to:
  /// **'· edited'**
  String get feedEdited;

  /// No description provided for @feedCommentCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Comment} =1{1 comment} other{{count} comments}}'**
  String feedCommentCount(int count);

  /// No description provided for @feedUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get feedUnpin;

  /// No description provided for @feedPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get feedPin;

  /// No description provided for @feedRemoveFile.
  ///
  /// In en, this message translates to:
  /// **'Remove the file'**
  String get feedRemoveFile;

  /// No description provided for @feedAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach a picture or a file'**
  String get feedAttach;

  /// No description provided for @feedPublishLater.
  ///
  /// In en, this message translates to:
  /// **'Publish later'**
  String get feedPublishLater;

  /// No description provided for @feedAskQuestion.
  ///
  /// In en, this message translates to:
  /// **'Ask a question'**
  String get feedAskQuestion;

  /// No description provided for @feedWritePost.
  ///
  /// In en, this message translates to:
  /// **'Write a post'**
  String get feedWritePost;

  /// No description provided for @feedEditPost.
  ///
  /// In en, this message translates to:
  /// **'Edit post'**
  String get feedEditPost;

  /// No description provided for @feedPost.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get feedPost;

  /// No description provided for @feedEditUnseenNote.
  ///
  /// In en, this message translates to:
  /// **'Nobody has seen this yet, so it will not be marked as edited.'**
  String get feedEditUnseenNote;

  /// No description provided for @feedEditSeenNote.
  ///
  /// In en, this message translates to:
  /// **'The post will be marked as edited. Its file, if it has one, stays as it is.'**
  String get feedEditSeenNote;

  /// No description provided for @feedWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get feedWaiting;

  /// No description provided for @feedEncryptedNoKeyHere.
  ///
  /// In en, this message translates to:
  /// **'Encrypted — no key on this device.'**
  String get feedEncryptedNoKeyHere;

  /// No description provided for @feedDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get feedDiscard;

  /// No description provided for @feedPublishNow.
  ///
  /// In en, this message translates to:
  /// **'Publish now'**
  String get feedPublishNow;

  /// No description provided for @feedNothingWaiting.
  ///
  /// In en, this message translates to:
  /// **'Nothing waiting'**
  String get feedNothingWaiting;

  /// No description provided for @feedNothingWaitingBody.
  ///
  /// In en, this message translates to:
  /// **'Posts you schedule wait here until their time comes. Nobody else can see them, or that they exist.'**
  String get feedNothingWaitingBody;

  /// No description provided for @feedTodayAt.
  ///
  /// In en, this message translates to:
  /// **'today at {time}'**
  String feedTodayAt(String time);

  /// No description provided for @feedTomorrowAt.
  ///
  /// In en, this message translates to:
  /// **'tomorrow at {time}'**
  String feedTomorrowAt(String time);

  /// No description provided for @feedDateAt.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String feedDateAt(String date, String time);

  /// No description provided for @feedReactionsNote.
  ///
  /// In en, this message translates to:
  /// **'What readers can put under a post. Reactions already on a post stay, even if you take the emoji off this list.'**
  String get feedReactionsNote;

  /// No description provided for @feedChosenOfLimit.
  ///
  /// In en, this message translates to:
  /// **'{chosen} of {limit}'**
  String feedChosenOfLimit(int chosen, int limit);

  /// No description provided for @feedPollNoKey.
  ///
  /// In en, this message translates to:
  /// **'A poll this device has no key for.'**
  String get feedPollNoKey;

  /// No description provided for @feedPollPickUpTo.
  ///
  /// In en, this message translates to:
  /// **'Pick up to {count}'**
  String feedPollPickUpTo(int count);

  /// No description provided for @feedPollPickOne.
  ///
  /// In en, this message translates to:
  /// **'Pick one'**
  String get feedPollPickOne;

  /// No description provided for @feedPollCloses.
  ///
  /// In en, this message translates to:
  /// **'closes {when}'**
  String feedPollCloses(String when);

  /// No description provided for @feedPollVoters.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 voter} other{{count} voters}}'**
  String feedPollVoters(int count);

  /// No description provided for @feedPollClearAnswer.
  ///
  /// In en, this message translates to:
  /// **'Clear my answer'**
  String get feedPollClearAnswer;

  /// No description provided for @feedPollAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get feedPollAnswer;

  /// No description provided for @feedPollQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get feedPollQuestion;

  /// No description provided for @feedPollAnswerN.
  ///
  /// In en, this message translates to:
  /// **'Answer {index}'**
  String feedPollAnswerN(int index);

  /// No description provided for @feedPollAddAnswer.
  ///
  /// In en, this message translates to:
  /// **'Add an answer'**
  String get feedPollAddAnswer;

  /// No description provided for @feedPollSeveral.
  ///
  /// In en, this message translates to:
  /// **'Several answers'**
  String get feedPollSeveral;

  /// No description provided for @feedPollNote.
  ///
  /// In en, this message translates to:
  /// **'The question and the answers are encrypted with the channel key, like a post. The server counts the votes without ever learning what any of them say.'**
  String get feedPollNote;

  /// No description provided for @feedPollAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get feedPollAsk;

  /// No description provided for @feedCouldNotOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Could not open that file.'**
  String get feedCouldNotOpenFile;

  /// No description provided for @feedOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get feedOpened;

  /// No description provided for @statsPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get statsPosts;

  /// No description provided for @statsWaitingToPublish.
  ///
  /// In en, this message translates to:
  /// **'Waiting to publish'**
  String get statsWaitingToPublish;

  /// No description provided for @statsPeopleWhoVoted.
  ///
  /// In en, this message translates to:
  /// **'People who voted'**
  String get statsPeopleWhoVoted;

  /// No description provided for @statsWaitingToJoin.
  ///
  /// In en, this message translates to:
  /// **'Waiting to join'**
  String get statsWaitingToJoin;

  /// No description provided for @statsNoViewCountNote.
  ///
  /// In en, this message translates to:
  /// **'There is no view count, and that is a decision rather than a gap. Counting who has read a post — without counting anybody twice — means keeping a row for every reader of every post, which is a record of what each person read. Everything above is counted from something somebody chose to do.'**
  String get statsNoViewCountNote;

  /// No description provided for @feedPollClosed.
  ///
  /// In en, this message translates to:
  /// **'closed'**
  String get feedPollClosed;

  /// No description provided for @inviteNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get inviteNever;

  /// No description provided for @inviteExpires.
  ///
  /// In en, this message translates to:
  /// **'expires {when}'**
  String inviteExpires(String when);

  /// No description provided for @requestsAsked.
  ///
  /// In en, this message translates to:
  /// **'Asked {when}'**
  String requestsAsked(String when);

  /// No description provided for @inviteAskMeFirst.
  ///
  /// In en, this message translates to:
  /// **'Ask me first'**
  String get inviteAskMeFirst;

  /// No description provided for @inviteAskMeFirstNote.
  ///
  /// In en, this message translates to:
  /// **'People who follow the link wait for your approval instead of walking in. They hold no key until you let them in.'**
  String get inviteAskMeFirstNote;

  /// No description provided for @inviteExpiresLabel.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get inviteExpiresLabel;

  /// No description provided for @invitePickATime.
  ///
  /// In en, this message translates to:
  /// **'Pick a time'**
  String get invitePickATime;

  /// No description provided for @inviteHowMany.
  ///
  /// In en, this message translates to:
  /// **'How many can join on it'**
  String get inviteHowMany;

  /// No description provided for @inviteNoLimit.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get inviteNoLimit;

  /// No description provided for @inviteJoinedSoFar.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person has joined on this link so far.} other{{count} have joined on this link so far.}} Opening it and walking away does not count.'**
  String inviteJoinedSoFar(int count);

  /// No description provided for @inviteReplaceLink.
  ///
  /// In en, this message translates to:
  /// **'Replace the link'**
  String get inviteReplaceLink;

  /// No description provided for @inviteReplaceNote.
  ///
  /// In en, this message translates to:
  /// **'Replacing is how a link is revoked: the old one stops working at once, everywhere. There is no half-working link left behind.'**
  String get inviteReplaceNote;

  /// No description provided for @inviteReplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace the link?'**
  String get inviteReplaceTitle;

  /// No description provided for @inviteReplaceBody.
  ///
  /// In en, this message translates to:
  /// **'The link you have shared stops working immediately — in messages, on posters, wherever it was pasted. Nobody holding it can join.\n\nPeople already in the channel stay in. There is no way to bring the old link back.'**
  String get inviteReplaceBody;

  /// No description provided for @inviteReplaceIt.
  ///
  /// In en, this message translates to:
  /// **'Replace it'**
  String get inviteReplaceIt;

  /// No description provided for @inviteExpired.
  ///
  /// In en, this message translates to:
  /// **'This link has expired — nobody can join on it.'**
  String get inviteExpired;

  /// No description provided for @inviteUsedUp.
  ///
  /// In en, this message translates to:
  /// **'This link has been used up.'**
  String get inviteUsedUp;

  /// No description provided for @inviteNeedsApproval.
  ///
  /// In en, this message translates to:
  /// **'Joining needs your approval'**
  String get inviteNeedsApproval;

  /// No description provided for @inviteOpenJoin.
  ///
  /// In en, this message translates to:
  /// **'Anyone with it joins straight away'**
  String get inviteOpenJoin;

  /// No description provided for @inviteUsedOf.
  ///
  /// In en, this message translates to:
  /// **'{used} of {max} used'**
  String inviteUsedOf(int used, int max);

  /// No description provided for @inviteShareNote.
  ///
  /// In en, this message translates to:
  /// **'Share this anywhere — it carries no key. Whoever opens it joins the channel, and the key to read it is sent to their device afterwards, encrypted, by someone who already has it.'**
  String get inviteShareNote;

  /// No description provided for @requestsNobodyWaiting.
  ///
  /// In en, this message translates to:
  /// **'Nobody waiting'**
  String get requestsNobodyWaiting;

  /// No description provided for @requestsNobodyWaitingBody.
  ///
  /// In en, this message translates to:
  /// **'People who follow the invite link appear here while the link is set to ask you first.'**
  String get requestsNobodyWaitingBody;

  /// No description provided for @requestsNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get requestsNo;

  /// No description provided for @requestsLetIn.
  ///
  /// In en, this message translates to:
  /// **'Let in'**
  String get requestsLetIn;

  /// No description provided for @feedSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get feedSettings;

  /// No description provided for @feedKeyRotating.
  ///
  /// In en, this message translates to:
  /// **'Someone left this channel, so it is changing its key (version {epoch}). Posts from before are still readable. New ones open once the new key reaches this device.'**
  String feedKeyRotating(int epoch);

  /// No description provided for @feedWaitingForKey.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the key. It is sent to this device, encrypted, by someone already in the channel — the server never holds it.'**
  String get feedWaitingForKey;

  /// No description provided for @feedJoinNote.
  ///
  /// In en, this message translates to:
  /// **'Joining gets you the posts. The key that opens them is sent to your device afterwards by a member, never by the server.'**
  String get feedJoinNote;

  /// No description provided for @feedJoinChannel.
  ///
  /// In en, this message translates to:
  /// **'Join channel'**
  String get feedJoinChannel;

  /// No description provided for @feedNoPostsYet.
  ///
  /// In en, this message translates to:
  /// **'No posts yet'**
  String get feedNoPostsYet;

  /// No description provided for @feedPickNewOwnerNote.
  ///
  /// In en, this message translates to:
  /// **'Only somebody already in the channel. Handing it to a stranger would put them in charge of a key they do not hold.'**
  String get feedPickNewOwnerNote;

  /// No description provided for @feedTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Give the channel to {name}?'**
  String feedTransferTitle(String name);

  /// No description provided for @feedTransferBody.
  ///
  /// In en, this message translates to:
  /// **'They will own it. You stay on as an admin with everything you have now except the right to delete the channel — and they can remove you afterwards.\n\nYou cannot undo this yourself. That is why it asks for your password rather than trusting an unlocked phone.'**
  String get feedTransferBody;

  /// No description provided for @feedYourPrivioPassword.
  ///
  /// In en, this message translates to:
  /// **'Your Privio password'**
  String get feedYourPrivioPassword;

  /// No description provided for @feedHandItOn.
  ///
  /// In en, this message translates to:
  /// **'Hand it on'**
  String get feedHandItOn;

  /// No description provided for @feedReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report this channel'**
  String get feedReportTitle;

  /// No description provided for @feedReportPublicNote.
  ///
  /// In en, this message translates to:
  /// **'The report carries this channel and the reason you pick. Whoever runs the server can see a public channel\'s name and description, because those are how it is searched for — but not its posts, which are encrypted.'**
  String get feedReportPublicNote;

  /// No description provided for @feedReportPrivateNote.
  ///
  /// In en, this message translates to:
  /// **'The report carries this channel and the reason you pick, and nothing else. Its name and its posts are encrypted, so whoever runs the server cannot read them. That is the honest limit of what reporting a private channel does.'**
  String get feedReportPrivateNote;

  /// No description provided for @feedReportNoMessageNote.
  ///
  /// In en, this message translates to:
  /// **'There is no message box on purpose: it would be the one place in Privio where somebody pastes the encrypted thing they are reporting into a field the server can read.'**
  String get feedReportNoMessageNote;

  /// No description provided for @reportSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get reportSpam;

  /// No description provided for @reportAbuse.
  ///
  /// In en, this message translates to:
  /// **'Abuse or harassment'**
  String get reportAbuse;

  /// No description provided for @reportIllegal.
  ///
  /// In en, this message translates to:
  /// **'Illegal content'**
  String get reportIllegal;

  /// No description provided for @reportImpersonation.
  ///
  /// In en, this message translates to:
  /// **'Pretending to be someone else'**
  String get reportImpersonation;

  /// No description provided for @reportOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get reportOther;

  /// No description provided for @feedReactionLimit.
  ///
  /// In en, this message translates to:
  /// **'Reactions'**
  String get feedReactionLimit;

  /// No description provided for @failureUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Privio.'**
  String get failureUnreachable;

  /// No description provided for @failureUnreachableCheckConnection.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Privio. Check your connection.'**
  String get failureUnreachableCheckConnection;

  /// No description provided for @failureUnreachableTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Privio. Check your connection and try again.'**
  String get failureUnreachableTryAgain;

  /// No description provided for @failureCouldNotSave.
  ///
  /// In en, this message translates to:
  /// **'Could not save that. Check your connection.'**
  String get failureCouldNotSave;

  /// No description provided for @failureChangeNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Privio. The change has not been saved.'**
  String get failureChangeNotSaved;

  /// No description provided for @failureRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Wait a moment.'**
  String get failureRateLimited;

  /// No description provided for @failureTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a few minutes.'**
  String get failureTooManyAttempts;

  /// No description provided for @failureLicenseRequired.
  ///
  /// In en, this message translates to:
  /// **'Activate your license to send messages.'**
  String get failureLicenseRequired;

  /// No description provided for @failureIdentityChanged.
  ///
  /// In en, this message translates to:
  /// **'The safety number changed. Nothing was sent — check it before you do.'**
  String get failureIdentityChanged;

  /// No description provided for @failureCouldNotSendMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not send message'**
  String get failureCouldNotSendMessage;

  /// No description provided for @failureCouldNotSendFile.
  ///
  /// In en, this message translates to:
  /// **'Could not send file'**
  String get failureCouldNotSendFile;

  /// No description provided for @failureCouldNotReadMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not read a message'**
  String get failureCouldNotReadMessage;

  /// No description provided for @failureMessagesUnreadable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A message could not be read} other{{count} messages could not be read}}'**
  String failureMessagesUnreadable(int count);

  /// No description provided for @failureCouldNotOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Could not open that file.'**
  String get failureCouldNotOpenFile;

  /// No description provided for @failureNotAnImage.
  ///
  /// In en, this message translates to:
  /// **'That file is not an image Privio can use.'**
  String get failureNotAnImage;

  /// No description provided for @failureCouldNotSetPicture.
  ///
  /// In en, this message translates to:
  /// **'Could not set the picture'**
  String get failureCouldNotSetPicture;

  /// No description provided for @failureDeletedHereOnly.
  ///
  /// In en, this message translates to:
  /// **'Deleted here. The request to delete it there did not go out.'**
  String get failureDeletedHereOnly;

  /// No description provided for @failureCouldNotCreateGroup.
  ///
  /// In en, this message translates to:
  /// **'Could not create the group'**
  String get failureCouldNotCreateGroup;

  /// No description provided for @failureNotAGroupLink.
  ///
  /// In en, this message translates to:
  /// **'That does not look like a Privio group link.'**
  String get failureNotAGroupLink;

  /// No description provided for @failureGroupNotFound.
  ///
  /// In en, this message translates to:
  /// **'That group does not exist, or the link is wrong.'**
  String get failureGroupNotFound;

  /// No description provided for @failureGroupKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'This device does not have the group key yet.'**
  String get failureGroupKeyMissing;

  /// No description provided for @failureNotAChannelLink.
  ///
  /// In en, this message translates to:
  /// **'That does not look like a Privio channel link.'**
  String get failureNotAChannelLink;

  /// No description provided for @failureHandleTaken.
  ///
  /// In en, this message translates to:
  /// **'That handle is already in use.'**
  String get failureHandleTaken;

  /// No description provided for @failureChannelNotFound.
  ///
  /// In en, this message translates to:
  /// **'That channel does not exist, or the link is wrong.'**
  String get failureChannelNotFound;

  /// No description provided for @failureNotAMember.
  ///
  /// In en, this message translates to:
  /// **'You are not in this channel.'**
  String get failureNotAMember;

  /// No description provided for @failureInsufficientPermission.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to do that.'**
  String get failureInsufficientPermission;

  /// No description provided for @failureCannotChangeOwnRole.
  ///
  /// In en, this message translates to:
  /// **'You cannot change your own role.'**
  String get failureCannotChangeOwnRole;

  /// No description provided for @failureOwnerIsFixed.
  ///
  /// In en, this message translates to:
  /// **'The channel owner cannot be changed or removed.'**
  String get failureOwnerIsFixed;

  /// No description provided for @failureTargetOutranksYou.
  ///
  /// In en, this message translates to:
  /// **'That member holds permissions you do not.'**
  String get failureTargetOutranksYou;

  /// No description provided for @failureCannotGrantWhatYouLack.
  ///
  /// In en, this message translates to:
  /// **'You cannot grant a permission you do not hold yourself.'**
  String get failureCannotGrantWhatYouLack;

  /// No description provided for @failureOwnerCannotLeave.
  ///
  /// In en, this message translates to:
  /// **'Hand the channel over or delete it instead.'**
  String get failureOwnerCannotLeave;

  /// No description provided for @failureUsernameTaken.
  ///
  /// In en, this message translates to:
  /// **'That username is already taken.'**
  String get failureUsernameTaken;

  /// No description provided for @failureInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Username or password is incorrect.'**
  String get failureInvalidCredentials;

  /// No description provided for @failureTotpRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your two-factor code.'**
  String get failureTotpRequired;

  /// No description provided for @failureInvalidTwoFactorCode.
  ///
  /// In en, this message translates to:
  /// **'That two-factor code is not right.'**
  String get failureInvalidTwoFactorCode;

  /// No description provided for @failureTooManyDevices.
  ///
  /// In en, this message translates to:
  /// **'This account already has the maximum number of devices.'**
  String get failureTooManyDevices;

  /// The server said why the form was rejected; its wording is passed through.
  ///
  /// In en, this message translates to:
  /// **'Check the username and password: {detail}'**
  String failureCheckUsernameAndPassword(String detail);

  /// No description provided for @failureInvalidTotp.
  ///
  /// In en, this message translates to:
  /// **'That code is not right. Check the clock on your phone and try again.'**
  String get failureInvalidTotp;

  /// No description provided for @failureTotpAlreadyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Two-factor is already on for this account.'**
  String get failureTotpAlreadyEnabled;

  /// No description provided for @failureTotpNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'Start the setup again — the secret is gone.'**
  String get failureTotpNotSetUp;

  /// No description provided for @failureInvalidPassword.
  ///
  /// In en, this message translates to:
  /// **'That password is not right.'**
  String get failureInvalidPassword;

  /// No description provided for @failureDuressMatchesPassword.
  ///
  /// In en, this message translates to:
  /// **'The duress code has to be different from your password, or an ordinary sign-in would destroy the account.'**
  String get failureDuressMatchesPassword;

  /// No description provided for @failureDeviceNotFound.
  ///
  /// In en, this message translates to:
  /// **'That device is already signed out.'**
  String get failureDeviceNotFound;

  /// No description provided for @failureCouldNotLiftBlock.
  ///
  /// In en, this message translates to:
  /// **'Could not lift that block.'**
  String get failureCouldNotLiftBlock;

  /// The shape a licence key has. Not translated: it is the literal pattern.
  ///
  /// In en, this message translates to:
  /// **'That key is not complete. It looks like {format}.'**
  String failureLicenseKeyIncomplete(String format);

  /// No description provided for @failureNotALicenseKey.
  ///
  /// In en, this message translates to:
  /// **'That does not look like a Privio license key.'**
  String get failureNotALicenseKey;

  /// No description provided for @failureLicenseNotFound.
  ///
  /// In en, this message translates to:
  /// **'No license matches that key. Check it and try again.'**
  String get failureLicenseNotFound;

  /// No description provided for @failureLicenseAlreadyRedeemed.
  ///
  /// In en, this message translates to:
  /// **'That key has already been used by another account. A key can only be redeemed once.'**
  String get failureLicenseAlreadyRedeemed;

  /// No description provided for @failureLicenseRevoked.
  ///
  /// In en, this message translates to:
  /// **'That license was revoked. Contact support if you paid for it.'**
  String get failureLicenseRevoked;

  /// No description provided for @failureAccountAlreadyLicensed.
  ///
  /// In en, this message translates to:
  /// **'This account already has a license, so the key you entered has not been used.'**
  String get failureAccountAlreadyLicensed;

  /// No description provided for @failureNoPlayServices.
  ///
  /// In en, this message translates to:
  /// **'This phone has no Google Play services, so Privio cannot be woken while it is closed. Messages arrive while Privio is open.'**
  String get failureNoPlayServices;

  /// No description provided for @failureNoApnsToken.
  ///
  /// In en, this message translates to:
  /// **'iOS did not issue a push token for Privio, so it cannot be woken while it is closed. Messages arrive while Privio is open.'**
  String get failureNoApnsToken;

  /// No description provided for @failureNoPushService.
  ///
  /// In en, this message translates to:
  /// **'No push service answered. Messages arrive while Privio is open.'**
  String get failureNoPushService;

  /// No description provided for @failureNoDistributor.
  ///
  /// In en, this message translates to:
  /// **'No UnifiedPush distributor answered. Install one — ntfy, for example — and try again.'**
  String get failureNoDistributor;

  /// No description provided for @failureDistributorUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Privio cannot reach that distributor. It has to be an https address on the public internet.'**
  String get failureDistributorUnreachable;

  /// No description provided for @failureChannelKeyAwaitingGeneration.
  ///
  /// In en, this message translates to:
  /// **'This channel is changing its key after a member left. You can post again once someone who manages the channel opens Privio.'**
  String get failureChannelKeyAwaitingGeneration;

  /// No description provided for @failureChannelKeyPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the new channel key to reach this device. Your post is not lost — try again in a moment.'**
  String get failureChannelKeyPending;

  /// No description provided for @failureUnexpected.
  ///
  /// In en, this message translates to:
  /// **'Something did not work as expected. Try again.'**
  String get failureUnexpected;

  /// No description provided for @failureCallDevicesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Privio could not open the camera or microphone.'**
  String get failureCallDevicesUnavailable;

  /// No description provided for @failureCallMicrophoneUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Privio could not open the microphone.'**
  String get failureCallMicrophoneUnavailable;

  /// No description provided for @failureCallNotOpen.
  ///
  /// In en, this message translates to:
  /// **'The call was not open.'**
  String get failureCallNotOpen;

  /// No description provided for @deepLinkChannelGone.
  ///
  /// In en, this message translates to:
  /// **'That link does not point at a channel any more. Ask whoever sent it for a new one.'**
  String get deepLinkChannelGone;

  /// No description provided for @chatsPreviewDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get chatsPreviewDeleted;

  /// No description provided for @chatsPreviewPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get chatsPreviewPhoto;

  /// No description provided for @chatsPreviewVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get chatsPreviewVideo;

  /// No description provided for @chatsPreviewVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get chatsPreviewVoice;

  /// No description provided for @chatsPreviewFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get chatsPreviewFile;

  /// No description provided for @notificationsPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off for Privio in your system settings. Messages still arrive while Privio is open — you will not be told about them, and a call will not ring.'**
  String get notificationsPermissionDenied;

  /// No description provided for @notificationsPermissionNotAsked.
  ///
  /// In en, this message translates to:
  /// **'Privio has not been allowed to notify you yet.'**
  String get notificationsPermissionNotAsked;

  /// No description provided for @failureCallMediaNotEncrypted.
  ///
  /// In en, this message translates to:
  /// **'The call was ended: the other side asked for a connection Privio cannot encrypt. Privio never falls back to an unencrypted call.'**
  String get failureCallMediaNotEncrypted;

  /// No description provided for @failureCallFarEndNotBound.
  ///
  /// In en, this message translates to:
  /// **'The call was ended: nothing in the setup proved who was at the other end. Privio does not connect a call it cannot tie to a key.'**
  String get failureCallFarEndNotBound;

  /// No description provided for @failureCallCertificateChanged.
  ///
  /// In en, this message translates to:
  /// **'The call was ended: the other end changed midway through. A call has one other end, and this one had two.'**
  String get failureCallCertificateChanged;

  /// The other person, by username. Never translated.
  ///
  /// In en, this message translates to:
  /// **'The call was ended: the security number for {who} is not the one Privio had. Compare it with them on another channel before calling again.'**
  String failureCallIdentityChanged(String who);

  /// No description provided for @failureCallWrongParty.
  ///
  /// In en, this message translates to:
  /// **'The call was ended: a message about it came from someone who is not on it.'**
  String get failureCallWrongParty;

  /// No description provided for @failureCallNotVerified.
  ///
  /// In en, this message translates to:
  /// **'The call was ended: you only take calls from people whose security number you have confirmed, and {who}\'s is not confirmed on this device.'**
  String failureCallNotVerified(String who);

  /// No description provided for @callEncrypted.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted'**
  String get callEncrypted;

  /// No description provided for @callEncryptedVerified.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted · verified'**
  String get callEncryptedVerified;

  /// No description provided for @securityVerifiedCallsOnly.
  ///
  /// In en, this message translates to:
  /// **'Only calls from verified contacts'**
  String get securityVerifiedCallsOnly;

  /// No description provided for @securityVerifiedCallsOnlyBody.
  ///
  /// In en, this message translates to:
  /// **'Every call is end-to-end encrypted either way. With this on, Privio also refuses a call unless you have compared the security number with that person and marked it confirmed — so a key this device merely met first is not enough. Calls from anyone else end with an explanation, on both sides.'**
  String get securityVerifiedCallsOnlyBody;

  /// No description provided for @privacyCalls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get privacyCalls;

  /// No description provided for @appearanceAccentColour.
  ///
  /// In en, this message translates to:
  /// **'Accent colour'**
  String get appearanceAccentColour;

  /// No description provided for @appearanceAccentNote.
  ///
  /// In en, this message translates to:
  /// **'This changes how Privio looks on this device, for this account. Nobody you write to sees it, and your other accounts keep their own. Red, for deleting and hanging up, stays red whichever accent you pick.'**
  String get appearanceAccentNote;

  /// No description provided for @accentGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get accentGreen;

  /// No description provided for @accentBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get accentBlue;

  /// No description provided for @accentTeal.
  ///
  /// In en, this message translates to:
  /// **'Turquoise'**
  String get accentTeal;

  /// No description provided for @accentPurple.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get accentPurple;

  /// No description provided for @accentPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get accentPink;

  /// No description provided for @accentRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get accentRed;

  /// No description provided for @accentOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get accentOrange;

  /// No description provided for @accentYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get accentYellow;

  /// No description provided for @accentPrivioDefault.
  ///
  /// In en, this message translates to:
  /// **'Privio default'**
  String get accentPrivioDefault;

  /// No description provided for @appearanceAccentReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get appearanceAccentReset;

  /// No description provided for @appearanceAccentPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get appearanceAccentPreview;

  /// No description provided for @appearancePreviewSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get appearancePreviewSend;

  /// No description provided for @appearancePreviewSetting.
  ///
  /// In en, this message translates to:
  /// **'Read receipts'**
  String get appearancePreviewSetting;

  /// No description provided for @appearancePreviewMessage.
  ///
  /// In en, this message translates to:
  /// **'This is what your own messages will look like.'**
  String get appearancePreviewMessage;

  /// Announced by a screen reader for the chosen swatch.
  ///
  /// In en, this message translates to:
  /// **'{colour}, selected'**
  String accentSelected(String colour);

  /// No description provided for @appearanceAppIcon.
  ///
  /// In en, this message translates to:
  /// **'App icon'**
  String get appearanceAppIcon;

  /// No description provided for @appearanceAppIconNote.
  ///
  /// In en, this message translates to:
  /// **'This is the icon on your home screen, and it belongs to this phone rather than to your account: signing in as somebody else does not change it. It stays as you set it when you pick a different accent colour.'**
  String get appearanceAppIconNote;

  /// No description provided for @appearanceAppIconMatchAccent.
  ///
  /// In en, this message translates to:
  /// **'Use the current accent colour'**
  String get appearanceAppIconMatchAccent;

  /// No description provided for @appearanceAppIconReset.
  ///
  /// In en, this message translates to:
  /// **'Restore the original icon'**
  String get appearanceAppIconReset;

  /// No description provided for @appearanceAppIconSlow.
  ///
  /// In en, this message translates to:
  /// **'The home screen can take a few seconds to redraw. That wait belongs to the launcher, not to Privio.'**
  String get appearanceAppIconSlow;

  /// No description provided for @appearanceAppIconUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This device cannot change the app icon, so Privio does not offer to.'**
  String get appearanceAppIconUnavailable;

  /// No description provided for @appearanceAppIconOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get appearanceAppIconOriginal;

  /// No description provided for @failureAppIconUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The app icon could not be changed: this device does not offer it.'**
  String get failureAppIconUnsupported;

  /// No description provided for @failureAppIconHiddenByDisguise.
  ///
  /// In en, this message translates to:
  /// **'The home screen is showing the calculator while the disguise is on, so the icon colour has not been changed. Switch the disguise off first.'**
  String get failureAppIconHiddenByDisguise;

  /// No description provided for @appIconSelected.
  ///
  /// In en, this message translates to:
  /// **'{colour} icon, selected'**
  String appIconSelected(String colour);

  /// No description provided for @appIconChoose.
  ///
  /// In en, this message translates to:
  /// **'{colour} icon'**
  String appIconChoose(String colour);
}

class _AppTextDelegate extends LocalizationsDelegate<AppText> {
  const _AppTextDelegate();

  @override
  Future<AppText> load(Locale locale) {
    return SynchronousFuture<AppText>(lookupAppText(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppTextDelegate old) => false;
}

AppText lookupAppText(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppTextDe();
    case 'en':
      return AppTextEn();
    case 'es':
      return AppTextEs();
    case 'fr':
      return AppTextFr();
    case 'it':
      return AppTextIt();
  }

  throw FlutterError(
    'AppText.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
