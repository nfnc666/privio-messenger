import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/disappearing_timer_sheet.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// The account-wide disappearing-message setting, and what it does and does
/// not reach.
///
/// The whole screen is an argument about one thing: a default is not a command.
/// It governs chats that have never been decided, and it leaves alone every
/// chat somebody settled by hand — until they say otherwise here, in front of
/// a list of exactly what is about to change.
///
/// There is no second timer system behind this. The setting is one number on
/// the account; a chat resolves its own answer against it, and every send path
/// asks `ConversationController.disappearAfter` for the result.
class DisappearingSettingsScreen extends StatefulWidget {
  const DisappearingSettingsScreen({super.key});

  @override
  State<DisappearingSettingsScreen> createState() => _DisappearingSettingsScreenState();
}

class _DisappearingSettingsScreenState extends State<DisappearingSettingsScreen> {
  bool _busy = false;

  Future<void> _chooseDefault(AppState state) async {
    final chosen = await DisappearingTimerSheet.chooseDefault(
      context,
      current: state.conversations.defaultDisappearAfter,
    );
    if (chosen == null || !mounted) return;
    final text = AppText.of(context);
    final ok = await state.conversations.setDefaultDisappearAfter(chosen.value);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.failureCouldNotSave)),
      );
    }
    setState(() {});
  }

  /// Shows what applying the default would do, then does it if asked.
  ///
  /// The preview is the point. "Apply to existing chats" with no numbers in
  /// front of it is a button whose effect somebody finds out about afterwards,
  /// in other people's chats.
  Future<void> _applyToExisting(AppState state) async {
    final text = AppText.of(context);
    final affected = state.conversations.chatsAffectedByDefault();
    var includeExceptions = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: PrivioColors.surface,
          title: Text(
            text.disappearingApplyPreviewTitle(
              DisappearingTimerSheet.label(text, state.conversations.defaultDisappearAfter),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text.disappearingApplyFollowing(affected.following.length)),
              if (affected.exceptions.isNotEmpty) ...[
                const SizedBox(height: PrivioSpacing.sm),
                Text(text.disappearingApplyExceptions(affected.exceptions.length)),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeExceptions,
                  onChanged: (value) =>
                      setDialogState(() => includeExceptions = value ?? false),
                  title: Text(
                    text.disappearingApplyIncludeExceptions,
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(text.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.accents.accent),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(text.disappearingApplyConfirm),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result = await state.conversations
        .applyDefaultToFollowingChats(includeExceptions: includeExceptions);
    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          [
            text.disappearingApplied(result.changed),
            // Named rather than silently left out: a group this account cannot
            // change is not a group that was done.
            if (result.skipped.isNotEmpty) text.disappearingSkippedGroups(result.skipped.length),
          ].join(' '),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final state = PrivioScope.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final conversations = state.conversations;
        final exceptions = conversations.timerExceptions();

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: Text(text.disappearingSettingsTitle),
          ),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PrivioSpacing.gutter,
                  PrivioSpacing.lg,
                  PrivioSpacing.gutter,
                  PrivioSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.disappearingSettingsIntro,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      text.disappearingStartsOnSend,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      text.disappearingScreenshotCaveat,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: PrivioColors.textTertiary),
                    ),
                  ],
                ),
              ),
              SettingsSection(
                caption: text.disappearingDefaultSection,
                children: [
                  SettingsRow(
                    icon: Icons.timer_outlined,
                    label: text.disappearingSettingsRow,
                    value: DisappearingTimerSheet.label(
                      text,
                      conversations.defaultDisappearAfter,
                    ),
                    onTap: _busy ? null : () => unawaited(_chooseDefault(state)),
                  ),
                  SettingsRow(
                    icon: Icons.checklist_rtl_rounded,
                    label: text.disappearingApplyToExisting,
                    onTap: _busy ? null : () => unawaited(_applyToExisting(state)),
                  ),
                  SettingsRow(
                    icon: Icons.rule_folder_outlined,
                    label: text.disappearingExceptionsRow,
                    value: '${exceptions.length}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _ExceptionsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Chats whose own setting differs from the account default, and a way back.
///
/// Listing every chat ever set by hand would ask somebody to tidy up chats
/// that already agree with them. What is here is only what differs — see
/// `ConversationController.timerExceptions`.
class _ExceptionsScreen extends StatelessWidget {
  const _ExceptionsScreen();

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final state = PrivioScope.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final conversations = state.conversations;
        final exceptions = conversations.timerExceptions();

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: Text(text.disappearingExceptionsTitle),
            actions: [
              if (exceptions.isNotEmpty)
                TextButton(
                  onPressed: () => unawaited(
                    conversations.applyDefaultToFollowingChats(includeExceptions: true),
                  ),
                  child: Text(text.disappearingResetAll),
                ),
            ],
          ),
          body: exceptions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(PrivioSpacing.xxl),
                    child: Text(
                      text.disappearingExceptionsEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: PrivioColors.textSecondary),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: exceptions.length,
                  itemBuilder: (context, index) {
                    final id = exceptions[index];
                    final chat = conversations.chats.where((c) => c.id == id).firstOrNull;
                    final timer = conversations.chatTimer(id);
                    return ListTile(
                      title: Text(chat?.title ?? id),
                      subtitle: Text(
                        DisappearingTimerSheet.label(text, timer.after),
                      ),
                      trailing: TextButton(
                        // Back to following, which is not the same as turning
                        // the timer off: the chat rejoins whatever the account
                        // says, now and later.
                        onPressed: () => unawaited(
                          conversations.setChatTimer(id, const ChatTimer.followDefault()),
                        ),
                        child: Text(text.disappearingResetToDefault),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
