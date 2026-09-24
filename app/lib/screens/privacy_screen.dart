import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/screen_shield_controller.dart';
import '../core/security_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import 'phone_contacts_screen.dart';
import '../widgets/web_storage_notice.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import '../widgets/disappearing_timer_sheet.dart';
import 'blocked_users_screen.dart';
import 'disappearing_settings_screen.dart';
import 'privacy_dashboard_screen.dart';
import 'screen_lock_screen.dart';
import 'security_activity_screen.dart';
import 'two_factor_screen.dart';
import 'duress_code_screen.dart';

/// Privacy and security.
///
/// Every row here is read from somewhere. That is worth saying because it was
/// not true: this screen used to state "Two-Factor Authentication: On" and
/// "Blocked Users: 3" from constants in the widget tree, over accounts that had
/// neither. Rows the product cannot back — who may see a profile photo, who may
/// see an About text — are gone rather than shown with a plausible value.
///
/// The two messaging switches are read from the account and written back to it,
/// and turning one off stops this device sending that thing — and stops it
/// showing other people's, because a setting that takes without giving would be
/// a different feature wearing this one's name.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final state = PrivioScope.of(context);
      // One read of the account, shared: the security half stays here, the
      // messaging switches go to the controller that enforces them.
      await state.security.load();
      final privacy = state.security.privacy;
      if (privacy != null) state.conversations.applyPrivacy(privacy);
    });
  }

  /// The word for one of the server's three values, in the reader's language.
  ///
  /// The values themselves never change — they are what is stored and what is
  /// sent — and only the words around them do.
  String _lastSeenLabel(AppText text, String value) => switch (value) {
        'contacts' => text.privacyLastSeenContacts,
        'nobody' => text.privacyLastSeenNobody,
        _ => text.privacyLastSeenEveryone,
      };

  /// Who may see when this account was last online. Three values, because
  /// that is what the server stores.
  Future<void> _chooseLastSeen(SecurityController security) async {
    final text = AppText.of(context);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in SecurityController.lastSeenChoices)
              ListTile(
                title: Text(_lastSeenLabel(text, value)),
                trailing: value == security.lastSeen
                    ? Icon(Icons.check_rounded, color: context.accents.accent)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (chosen != null) await security.setLastSeen(chosen);
  }

  String _profileStatusLabel(AppText text, String value) => switch (value) {
        'contacts' => text.privacyProfileStatusContacts,
        'nobody' => text.privacyProfileStatusNobody,
        _ => text.privacyProfileStatusEveryone,
      };

  /// Who may read the line this account published about itself.
  ///
  /// Its own chooser beside last-seen rather than folded into it. They read the
  /// same three values and mean different things: one hides an observation the
  /// server made, the other withholds something the user wrote.
  Future<void> _chooseProfileStatus(SecurityController security) async {
    final text = AppText.of(context);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in SecurityController.profileStatusChoices)
              ListTile(
                title: Text(_profileStatusLabel(text, value)),
                trailing: value == security.profileStatus
                    ? Icon(Icons.check_rounded, color: context.accents.accent)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (chosen != null) await security.setProfileStatusVisibility(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final conversations = state.conversations;
    final security = state.security;
    final calls = state.services.calls;
    final events = state.securityEvents;
    final text = AppText.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsPrivacy),
      ),
      body: ListenableBuilder(
        listenable:
            Listenable.merge([conversations, security, calls, state.screenShield, events]),
        builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          // First, because it is the answer to the question people arrive with.
          // Everything below it is a setting; this is the state.
          SettingsSection(
            caption: text.privacyOverview,
            children: [
              SettingsRow(
                icon: Icons.shield_outlined,
                label: text.privacyDashboardRow,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PrivacyDashboardScreen()),
                ),
              ),
            ],
          ),
          SettingsSection(
            caption: text.privacyWhoCanSee,
            children: [
              // The only one of these the server actually stores. A profile
              // photo is already encrypted to the people you have written to,
              // so there is no separate audience to choose.
              SettingsRow(
                label: text.privacyLastSeen,
                value: _lastSeenLabel(text, security.lastSeen),
                onTap: () => _chooseLastSeen(security),
              ),
              SettingsRow(
                label: text.privacyProfileStatus,
                value: _profileStatusLabel(text, security.profileStatus),
                onTap: () => _chooseProfileStatus(security),
              ),
              SettingsRow(
                label: text.privacyPhoneSection,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PhoneContactsScreen()),
                ),
              ),
            ],
          ),
          SettingsSection(
            caption: text.privacyMessaging,
            children: [
              SettingsRow(
                label: text.privacyReadReceipts,
                trailing: Switch(
                  value: conversations.readReceiptsEnabled,
                  onChanged: (value) => conversations.setReadReceipts(value),
                ),
              ),
              SettingsRow(
                label: text.privacyTypingIndicators,
                trailing: Switch(
                  value: conversations.typingIndicatorsEnabled,
                  onChanged: (value) => conversations.setTypingIndicators(value),
                ),
              ),
              // This row used to state "Per chat" and do nothing. There is an
              // account-wide default now, and it opens the screen that sets
              // it — including what applying it to existing chats would do.
              SettingsRow(
                label: text.disappearingSettingsRow,
                value: DisappearingTimerSheet.label(
                  text,
                  conversations.defaultDisappearAfter,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DisappearingSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
          if (WebStorageNotice.applies)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                PrivioSpacing.gutter,
                PrivioSpacing.sm,
                PrivioSpacing.gutter,
                PrivioSpacing.sm,
              ),
              child: WebStorageNotice(),
            ),
          SettingsSection(
            caption: text.privacyAccess,
            children: [
              SettingsRow(
                label: text.privacyScreenLock,
                value: state.screenLockSet ? text.privacyPin : text.commonOff,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ScreenLockScreen()),
                ),
              ),
              SettingsRow(
                label: text.privacyTwoFactor,
                // Null until the server has answered. Better a row with no
                // value for a moment than one that guesses.
                value: switch (security.twoFactorEnabled) {
                  true => text.commonOn,
                  false => text.commonOff,
                  null => null,
                },
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TwoFactorScreen()),
                ),
              ),
              SettingsRow(
                label: text.privacyDuressCode,
                value: switch (security.twoFactorEnabled) {
                  // The same read answers both, so the same null means "not
                  // asked yet" for this row too.
                  null => null,
                  _ => security.duressCodeSet ? text.privacySet : text.commonOff,
                },
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const DuressCodeScreen()),
                ),
              ),
              _ScreenShieldRow(controller: state.screenShield),
              SettingsRow(
                label: text.privacySecurityActivity,
                // The count is of the two kinds worth noticing, not of every
                // line: a row reading "47" next to "Security activity" says
                // nothing, and a row reading "1" when a contact's key changed
                // says the only thing this screen has to say.
                value: events.warnings > 0 ? events.warnings.toString() : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SecurityActivityScreen()),
                ),
              ),
              SettingsRow(
                label: text.privacyBlockedUsers,
                value: security.blocked?.length.toString(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BlockedUsersScreen()),
                ),
              ),
            ],
          ),
          SettingsSection(
            caption: text.privacyIdentity,
            children: [
              SettingsRow(
                label: text.privacyBlockOnKeyChange,
                subtitle: text.privacyBlockOnKeyChangeNote,
                trailing: Switch(
                  key: const ValueKey('block-on-key-change'),
                  value: conversations.blockOnKeyChange,
                  onChanged: (value) =>
                      unawaited(conversations.setBlockOnKeyChange(value)),
                ),
              ),
            ],
          ),
          SettingsSection(
            caption: text.privacyCalls,
            children: [
              SettingsRow(
                label: text.securityVerifiedCallsOnly,
                trailing: Switch(
                  key: const ValueKey('verified-calls-only'),
                  value: calls.requireVerified,
                  onChanged: (value) => unawaited(
                    calls.setRequireVerified(value, accountId: state.accountId),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.xxl,
              PrivioSpacing.sm,
              PrivioSpacing.xxl,
              0,
            ),
            child: Text(
              text.securityVerifiedCallsOnlyBody,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: PrivioSpacing.xl),
          // What the screen protection does *not* reach. Said here rather than
          // left to be inferred: a switch called "Screen protection" invites
          // the belief that it stops the person on the other end of the chat
          // from keeping a copy, and it does not.
          if (state.screenShield.capability.isSupported)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
              child: Text(
                text.privacyScreenShieldScope,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (state.screenShield.capability.isSupported)
            const SizedBox(height: PrivioSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
            child: Text(
              text.privacyMutualNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          ],
        ),
      ),
    );
  }
}


/// The Screen protection switch, and the sentence that is true on *this* phone.
///
/// Two platforms that do genuinely different things, so two explanations rather
/// than one that is true on Android and a lie on iOS. The row reads the
/// capability the device reported — not the build's edition, and not
/// `defaultTargetPlatform` — because what matters is what the window manager on
/// the other end of the channel actually answered.
class _ScreenShieldRow extends StatelessWidget {
  const _ScreenShieldRow({required this.controller});

  final ScreenShieldController controller;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final capability = controller.capability;

    // Nothing until the platform has answered. A row that said "unavailable"
    // before the channel replied would be a claim nobody made.
    final subtitle = !controller.asked
        ? null
        : capability.blocksCapture
            ? text.privacyScreenShieldAndroid
            : capability.detectsCapture
                ? text.privacyScreenShieldIos
                : text.privacyScreenShieldUnavailable;

    return SettingsRow(
      icon: Icons.screenshot_monitor_outlined,
      label: text.privacyScreenShield,
      subtitle: subtitle,
      // Shown but not usable where the platform cannot do it, rather than
      // hidden: somebody looking for this setting should find out that their
      // device cannot, not be left wondering where it went.
      enabled: capability.isSupported,
      trailing: Switch(
        key: const ValueKey('screen-shield'),
        value: controller.enabled,
        onChanged: capability.isSupported
            ? (value) => unawaited(controller.setEnabled(value))
            : null,
      ),
    );
  }
}
