import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calls/call.dart';
import '../calls/call_signal.dart';
import '../core/app_state.dart';
import '../core/profile_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/channel_text.dart';
import '../l10n/failure_text.dart';
import '../models/contact_profile.dart';
import '../models/models.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/profile_action_button.dart';
import '../widgets/settings_row.dart';
import 'chat_screen.dart';
import 'safety_number_screen.dart';

/// One person, as this account is allowed to see them.
///
/// Reached from the header of a one-to-one chat and from a sender's name in a
/// group. Both of those knew an account id and a name and had nowhere to send
/// a tap: the only way to see anything about somebody was the contacts list,
/// which shows a name, a handle and a timestamp and no way to act on any of it.
///
/// **It is addressed by account id, never by name.** A display name is chosen
/// by the person it names, is not unique and can be changed to somebody else's;
/// opening a profile by name would be a way to be shown the wrong person by
/// someone who wanted to be. The id comes from the conversation or from the
/// message that was tapped, and the name on screen is whatever the server
/// returns for that id.
///
/// What it shows is decided on the server — see `routes/contacts.ts`. A status
/// or a last-seen time that this viewer may not see arrives as null and is
/// simply not drawn: there is no row saying "hidden", because being told that
/// something is being withheld is itself something the owner did not publish.
class ContactProfileScreen extends StatefulWidget {
  const ContactProfileScreen({
    required this.accountId,
    super.key,
    this.knownName,
    this.openedFromTheirChat = false,
  });

  final String accountId;

  /// What the caller already had on screen, so the bar is not empty while the
  /// first read is in flight. Replaced by the server's answer the moment it
  /// arrives, and never used to decide anything.
  final String? knownName;

  /// Whether the chat with this person is the screen underneath.
  ///
  /// When it is, "Message" pops back to it rather than pushing a second copy —
  /// which is what keeps the scroll position and the half-written message the
  /// user left there, and is the difference between going back to a
  /// conversation and opening a new one on top of it.
  final bool openedFromTheirChat;

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  /// True while an action of this screen's own is in flight, so a second tap
  /// cannot start a second add, block or report.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(PrivioScope.of(context).profiles.load(widget.accountId));
    });
  }

  ContactProfile? get _profile {
    final view = PrivioScope.of(context).profiles.viewOf(widget.accountId);
    return view is ProfileReady ? view.profile : null;
  }

  String get _name => _profile?.label ?? widget.knownName ?? '';

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs one action, refuses a second while it runs, and re-reads the profile
  /// afterwards so the buttons state what the *server* thinks rather than what
  /// this device hoped.
  Future<void> _act(Future<bool> Function() action, {required String onFailure}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    await PrivioScope.of(context).profiles.load(widget.accountId, force: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _say(onFailure);
  }

  // --- The four actions -----------------------------------------------------

  /// Opens the chat with this person without ever making a second one.
  ///
  /// Two ways, and which one applies is not a detail: if this profile was
  /// opened from their own chat, the chat is the screen underneath and popping
  /// back to it is the only correct answer — it is still exactly as it was
  /// left. Otherwise the conversation is looked up by *account id*, which is
  /// the conversation's own identity in the store, so opening it twice from two
  /// places lands in the same chat rather than making another.
  Future<void> _message() async {
    if (widget.openedFromTheirChat) {
      Navigator.of(context).pop();
      return;
    }
    final state = PrivioScope.of(context);
    final profile = _profile;
    if (profile == null) return;
    final conversationId = await state.conversations.openConversation(profile.username);
    if (conversationId == null || !mounted) {
      if (mounted) {
        _say(state.conversations.failure?.words(AppText.of(context)) ??
            AppText.of(context).profileCouldNotLoad);
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(accountId: conversationId, title: profile.label),
      ),
    );
  }

  Future<void> _call(CallMedia media) async {
    final profile = _profile;
    if (profile == null) return;
    await PrivioScope.of(context).services.calls.place(
          CallParty(accountId: profile.accountId, username: profile.username),
          media: media,
        );
  }

  Future<void> _openSafetyNumber(ContactProfile profile) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SafetyNumberScreen(
            accountId: profile.accountId,
            title: profile.label,
          ),
        ),
      );

  // --- Contacts, blocking, reporting ----------------------------------------

  Future<void> _addContact(ContactProfile profile) async {
    final text = AppText.of(context);
    await _act(
      () => PrivioScope.of(context).conversations.addContact(profile.username),
      onFailure: text.profileCouldNotAddContact,
    );
    if (!mounted) return;
    if (_profile?.isContact ?? false) _say(text.profileContactAdded);
  }

  Future<void> _removeContact(ContactProfile profile) async {
    final text = AppText.of(context);
    final yes = await _confirm(
      title: text.profileRemoveContactTitle(profile.label),
      body: text.profileRemoveContactBody,
      action: text.commonRemove,
      destructive: true,
    );
    if (!yes || !mounted) return;
    await _act(
      () => PrivioScope.of(context).conversations.removeContact(profile.accountId),
      onFailure: text.profileCouldNotRemoveContact,
    );
    if (!mounted) return;
    if (!(_profile?.isContact ?? true)) _say(text.profileContactRemoved);
  }

  /// Blocks, with the same words the chat uses.
  ///
  /// Blocking drops the conversation from this device — that is what
  /// `ConversationController.block` has always done, and a chat that can never
  /// grow again is not worth keeping on the list. So this screen leaves too:
  /// what is underneath it may be the very chat that has just been removed.
  Future<void> _block(ContactProfile profile) async {
    final text = AppText.of(context);
    final yes = await _confirm(
      title: text.chatBlockTitle(profile.label),
      body: text.chatBlockBody,
      action: text.chatBlock,
      destructive: true,
    );
    if (!yes || !mounted) return;

    final blocked = await PrivioScope.of(context).conversations.block(profile.accountId);
    if (!mounted) return;
    if (!blocked) {
      _say(text.chatCouldNotBlock);
      return;
    }
    _say(text.chatBlocked(profile.label));
    // The navigator is taken once, before anything is popped. Reading it out of
    // `context` a second time would be reading it out of a widget that has just
    // been removed. Two pops when the chat is what is underneath: blocking
    // dropped that conversation, so leaving it on screen would leave somebody
    // looking at a chat that no longer exists.
    final navigator = Navigator.of(context);
    navigator.pop();
    if (widget.openedFromTheirChat) navigator.pop();
  }

  Future<void> _unblock(ContactProfile profile) async {
    final text = AppText.of(context);
    final yes = await _confirm(
      title: text.blockedUnblockTitle(profile.label),
      body: text.blockedUnblockBody,
      action: text.blockedUnblock,
    );
    if (!yes || !mounted) return;
    final security = PrivioScope.of(context).security;
    await _act(
      () async {
        await security.unblock(profile.accountId);
        return security.failure == null;
      },
      onFailure: security.failure?.words(text) ?? text.failureCouldNotLiftBlock,
    );
  }

  Future<void> _report(ContactProfile profile) async {
    final text = AppText.of(context);
    final reason = await showModalBottomSheet<ReportReason>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.xxl,
                PrivioSpacing.xl,
                PrivioSpacing.xxl,
                PrivioSpacing.sm,
              ),
              child: Text(
                text.profileReportTitle(profile.label),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.xxl,
                0,
                PrivioSpacing.xxl,
                PrivioSpacing.md,
              ),
              // Said before the reasons rather than after the fact: somebody
              // about to report a person is usually expecting the messages to
              // go with it, and they do not exist to send.
              child: Text(
                text.profileReportBody,
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ),
            for (final reason in ReportReason.values)
              ListTile(
                title: Text(reportReasonLabel(AppText.of(sheetContext), reason)),
                onTap: () => Navigator.of(sheetContext).pop(reason),
              ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    final outcome =
        await PrivioScope.of(context).profiles.report(profile.accountId, reason.wire);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(switch (outcome) {
      ReportOutcome.filed => text.profileReported,
      ReportOutcome.alreadyFiled => text.profileAlreadyReported,
      ReportOutcome.failed => text.profileCouldNotReport,
    });
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppText.of(dialogContext).commonCancel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: PrivioColors.danger)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  // --- Drawing --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final text = AppText.of(context);

    return ListenableBuilder(
      listenable: state.profiles,
      builder: (context, _) {
        final view = state.profiles.viewOf(widget.accountId);
        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: Text(_name.isEmpty ? text.profileTitle : _name),
          ),
          body: switch (view) {
            ProfileLoading() => Center(
                child: CircularProgressIndicator(color: context.accents.accent),
              ),
            ProfileGone() => _Explanation(
                icon: Icons.person_off_outlined,
                title: text.profileGoneTitle,
                body: text.profileGoneBody,
              ),
            ProfileUnavailable(:final failure) => _Explanation(
                icon: Icons.cloud_off_rounded,
                title: text.profileCouldNotLoad,
                body: failure.words(text),
                onRetry: () => unawaited(
                  state.profiles.load(widget.accountId, force: true),
                ),
                retryLabel: text.commonRetry,
              ),
            ProfileReady(:final profile) => _body(state, text, profile),
          },
        );
      },
    );
  }

  Widget _body(AppState state, AppText text, ContactProfile profile) {
    final theme = Theme.of(context);
    final avatar = state.conversations.avatarFor(profile.accountId);
    final status = profile.status;

    return ListView(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
      children: [
        const SizedBox(height: PrivioSpacing.lg),
        Center(
          child: GestureDetector(
            // Only when there is a picture to enlarge. A tap that opens a
            // full-screen pair of initials is a tap that did nothing.
            onTap: avatar == null
                ? null
                : () => unawaited(
                      PhotoViewer.open(context, bytes: avatar, name: profile.label),
                    ),
            child: PrivioAvatar(
              label: profile.label,
              size: 96,
              seed: profile.accountId.hashCode.abs(),
              imageBytes: avatar,
            ),
          ),
        ),
        const SizedBox(height: PrivioSpacing.md),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
            child: Text(
              profile.label,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ),
        const SizedBox(height: PrivioSpacing.xs),
        Center(
          child: Text(
            '@${profile.username}',
            style: theme.textTheme.bodyMedium?.copyWith(color: PrivioColors.textSecondary),
          ),
        ),
        // Only when the server was willing to say. Absent is absent: there is
        // no line explaining that there might have been one.
        if (profile.lastSeenAt != null) ...[
          const SizedBox(height: PrivioSpacing.xs),
          Center(
            child: Text(
              text.profileLastSeen(_when(text, profile.lastSeenAt!)),
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
        if (status.isSet) ...[
          const SizedBox(height: PrivioSpacing.sm),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
              child: Text(
                status.emoji == null
                    ? status.text ?? ''
                    : '${status.emoji} ${status.text ?? ''}'.trim(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
        const SizedBox(height: PrivioSpacing.lg),

        if (profile.isSelf)
          // Your own profile, reached by tapping your own name in a group. It
          // shows what everybody else would see and offers none of the actions
          // that only make sense against somebody else — and no editing either,
          // because editing lives on the Account screen and two places to
          // change one picture is one place too many.
          _Note(title: text.profileYouTitle, body: text.profileYouBody)
        else ...[
          if (profile.isBlocked)
            _Note(
              title: text.profileBlockedTitle,
              body: text.profileBlockedBody,
              tint: PrivioColors.warning,
              action: text.blockedUnblock,
              onAction: _busy ? null : () => unawaited(_unblock(profile)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
            child: Row(
              children: [
                ProfileActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: text.profileMessageAction,
                  onTap: () => unawaited(_message()),
                ),
                const SizedBox(width: PrivioSpacing.sm),
                ProfileActionButton(
                  icon: Icons.call_outlined,
                  label: text.profileCallAction,
                  onTap: () => unawaited(_call(CallMedia.audio)),
                ),
                const SizedBox(width: PrivioSpacing.sm),
                ProfileActionButton(
                  icon: Icons.videocam_outlined,
                  label: text.profileVideoAction,
                  onTap: () => unawaited(_call(CallMedia.video)),
                ),
                const SizedBox(width: PrivioSpacing.sm),
                // Verification rather than an overflow menu. Everything an
                // overflow would have held — add, block, report — is a
                // labelled row below, and two ways to reach one thing is one
                // way too many. This is the action with nowhere else to be,
                // and on a screen about who somebody is it earns the space.
                ProfileActionButton(
                  icon: Icons.verified_user_outlined,
                  label: text.profileVerifyAction,
                  onTap: () => unawaited(_openSafetyNumber(profile)),
                ),
              ],
            ),
          ),
          const SizedBox(height: PrivioSpacing.lg),
        ],

        SettingsSection(
          children: [
            SettingsRow(
              icon: Icons.alternate_email_rounded,
              label: text.accountUsername,
              value: profile.username,
            ),
            SettingsRow(
              icon: Icons.fingerprint_rounded,
              label: text.profilePrivioId,
              value: _shortId(profile.accountId),
              // The full id is what a support request or a bug report needs,
              // and it is far too long to read off a screen.
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: profile.accountId));
                _say(text.profileIdCopied);
              },
            ),
          ],
        ),

        if (!profile.isSelf) ...[
          const SizedBox(height: PrivioSpacing.lg),
          SettingsSection(
            children: [
              SettingsRow(
                icon: profile.isContact
                    ? Icons.person_remove_outlined
                    : Icons.person_add_alt_1_rounded,
                label: profile.isContact ? text.profileRemoveContact : text.profileAddContact,
                enabled: !_busy,
                onTap: () => unawaited(
                  profile.isContact ? _removeContact(profile) : _addContact(profile),
                ),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          SettingsSection(
            children: [
              SettingsRow(
                label: text.profileReport,
                destructive: true,
                enabled: !_busy,
                onTap: () => unawaited(_report(profile)),
              ),
              if (!profile.isBlocked)
                SettingsRow(
                  label: text.chatBlock,
                  destructive: true,
                  enabled: !_busy,
                  onTap: () => unawaited(_block(profile)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// When somebody was last connected, in the reader's language.
  ///
  /// The same wording the contacts list uses, because it is the same fact —
  /// and deliberately never the word "online": the server reports a moment, and
  /// turning a moment into a state would be this app inferring something about
  /// somebody else and presenting the guess as fact.
  static String _when(AppText text, DateTime at) {
    final now = DateTime.now();
    final difference = now.difference(at);
    if (difference.inMinutes < 1) return text.contactsSeenJustNow;
    if (difference.inMinutes < 60) return text.contactsSeenMinutes(difference.inMinutes);
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    final time = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    if (sameDay) return text.contactsSeenAtTime(time);
    if (difference.inDays < 7) return text.contactsSeenDays(difference.inDays);
    return formatDate(text, at);
  }
}

String _shortId(String accountId) =>
    accountId.length <= 8 ? accountId : '${accountId.substring(0, 8)}…';

/// A card that explains something, optionally with one thing to do about it.
class _Note extends StatelessWidget {
  const _Note({
    required this.title,
    required this.body,
    this.tint,
    this.action,
    this.onAction,
  });

  final String title;
  final String body;
  final Color? tint;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.gutter,
        0,
        PrivioSpacing.gutter,
        PrivioSpacing.lg,
      ),
      child: Container(
        padding: const EdgeInsets.all(PrivioSpacing.lg),
        decoration: BoxDecoration(
          color: PrivioColors.surfaceRaised,
          borderRadius: BorderRadius.circular(PrivioSpacing.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(color: tint),
            ),
            const SizedBox(height: PrivioSpacing.xs),
            Text(body, style: theme.textTheme.bodySmall),
            if (action != null) ...[
              const SizedBox(height: PrivioSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: onAction, child: Text(action!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The whole screen, when there is nothing to show: a deleted account, or a
/// read that did not come back.
class _Explanation extends StatelessWidget {
  const _Explanation({
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
    this.retryLabel,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.lg),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.sm),
            Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            if (onRetry != null && retryLabel != null) ...[
              const SizedBox(height: PrivioSpacing.lg),
              FilledButton(onPressed: onRetry, child: Text(retryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
