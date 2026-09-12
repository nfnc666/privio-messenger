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

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

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

  /// No description provided for @settingsStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsStorage;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About PRIVIO'**
  String get settingsAbout;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

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
