import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/security_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import '../widgets/web_storage_notice.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import 'blocked_users_screen.dart';
import 'screen_lock_screen.dart';
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
                    ? const Icon(Icons.check_rounded, color: PrivioColors.accent)
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

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final conversations = state.conversations;
    final security = state.security;
    final text = AppText.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsPrivacy),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([conversations, security]),
        builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
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
              // Per chat rather than global: a timer that applied to every
              // conversation at once would be a setting nobody could use.
              SettingsRow(
                label: text.privacyDisappearing,
                value: text.privacyPerChat,
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
              SettingsRow(
                label: text.privacyBlockedUsers,
                value: security.blocked?.length.toString(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BlockedUsersScreen()),
                ),
              ),
            ],
          ),
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
