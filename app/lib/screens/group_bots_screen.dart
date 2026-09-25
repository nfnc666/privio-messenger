import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../models/group_bot.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// The bots in a group, and what each of them may do.
///
/// Admins only for every change; a member may open it and see who is here,
/// because somebody writing in a group is entitled to know who receives it.
class GroupBotsScreen extends StatefulWidget {
  const GroupBotsScreen({required this.groupId, required this.isAdmin, super.key});

  final String groupId;
  final bool isAdmin;

  @override
  State<GroupBotsScreen> createState() => _GroupBotsScreenState();
}

class _GroupBotsScreenState extends State<GroupBotsScreen> {
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    await PrivioScope.of(context).conversations.refreshGroupBots(widget.groupId);
    if (mounted) setState(() => _loading = false);
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// Adds a bot, after saying in full what that means.
  ///
  /// The disclosure is a screen somebody has to read past rather than a line
  /// under a switch, because the thing being disclosed — that a person outside
  /// this group will receive messages from it — is the whole decision.
  Future<void> _add(AppState state) async {
    final text = AppText.of(context);
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.groupBotsAddTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '@name'),
            ),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              text.groupBotsAddHint,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(text.commonNext),
          ),
        ],
      ),
    );
    if (username == null || username.isEmpty || !mounted) return;

    final cleaned = username.startsWith('@') ? username.substring(1) : username;
    final resolved = await state.conversations.lookupBot(cleaned);
    if (!mounted) return;
    if (resolved == null) {
      _say(state.conversations.failure?.words(text) ?? text.groupBotsNotFound);
      return;
    }

    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _WhatItCanRead(botName: resolved.label),
    );
    if (agreed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await state.conversations.addGroupBot(widget.groupId, resolved.botId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _say(state.conversations.failure?.words(text) ?? text.groupBotsCouldNotAdd);
  }

  Future<void> _setRight(AppState state, GroupBot bot, String right, bool value) async {
    final text = AppText.of(context);
    setState(() => _busy = true);
    final ok = await state.conversations
        .setGroupBotRight(widget.groupId, bot.botId, right, value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _say(state.conversations.failure?.words(text) ?? text.groupBotsCouldNotChange);
  }

  /// Turning on "reads everything" asks again, because it is the one switch
  /// that changes what the other members' messages are handed over to.
  Future<void> _setReadsAll(AppState state, GroupBot bot, bool value) async {
    final text = AppText.of(context);
    if (value) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: PrivioColors.surface,
          title: Text(text.groupBotsReadAllTitle),
          content: Text(text.groupBotsReadAllBody(bot.label)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(text.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(text.groupBotsReadAllConfirm),
            ),
          ],
        ),
      );
      if (agreed != true || !mounted) return;
    }
    await _setRight(state, bot, 'readsAllMessages', value);
  }

  Future<void> _remove(AppState state, GroupBot bot) async {
    final text = AppText.of(context);
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.groupBotsRemoveTitle(bot.label)),
        // Said rather than left to be assumed: removing stops what comes next
        // and reaches nothing that already went.
        content: Text(text.groupBotsRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.groupBotsRemoveAction),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await state.conversations.removeGroupBot(widget.groupId, bot.botId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _say(state.conversations.failure?.words(text) ?? text.groupBotsCouldNotChange);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final state = PrivioScope.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final bots = state.conversations.botsIn(widget.groupId);

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: Text(text.groupBotsTitle),
            actions: [
              if (widget.isAdmin)
                IconButton(
                  onPressed: _busy ? null : () => unawaited(_add(state)),
                  icon: const Icon(Icons.add_rounded),
                  tooltip: text.groupBotsAddTitle,
                ),
            ],
          ),
          body: _loading
              ? Center(child: CircularProgressIndicator(color: context.accents.accent))
              : ListView(
                  padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(PrivioSpacing.gutter),
                      child: Text(
                        text.groupBotsIntro,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (bots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PrivioSpacing.gutter,
                        ),
                        child: Text(
                          text.groupBotsNone,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    for (final bot in bots) ...[
                      SettingsSection(
                        caption: '@${bot.username}',
                        children: [
                          ListTile(
                            leading: PrivioAvatar(
                              label: bot.label,
                              seed: bot.botId.hashCode.abs(),
                            ),
                            title: Row(
                              children: [
                                Flexible(child: Text(bot.label)),
                                const SizedBox(width: PrivioSpacing.xs),
                                const _BotBadge(),
                              ],
                            ),
                            subtitle: Text(
                              bot.readsAllMessages
                                  ? text.groupBotsReadsEverything
                                  : text.groupBotsReadsAddressed,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          _Right(
                            label: text.groupBotsMaySend,
                            value: bot.maySend,
                            enabled: widget.isAdmin && !_busy,
                            onChanged: (v) =>
                                unawaited(_setRight(state, bot, 'maySend', v)),
                          ),
                          _Right(
                            label: text.groupBotsMayModerate,
                            value: bot.mayModerate,
                            enabled: widget.isAdmin && !_busy,
                            onChanged: (v) =>
                                unawaited(_setRight(state, bot, 'mayModerate', v)),
                          ),
                          _Right(
                            label: text.groupBotsMayRestrict,
                            value: bot.mayRestrictMembers,
                            enabled: widget.isAdmin && !_busy,
                            onChanged: (v) =>
                                unawaited(_setRight(state, bot, 'mayRestrictMembers', v)),
                          ),
                          _Right(
                            label: text.groupBotsMayInvite,
                            value: bot.mayManageInvites,
                            enabled: widget.isAdmin && !_busy,
                            onChanged: (v) =>
                                unawaited(_setRight(state, bot, 'mayManageInvites', v)),
                          ),
                          _Right(
                            label: text.groupBotsReadAll,
                            value: bot.readsAllMessages,
                            enabled: widget.isAdmin && !_busy,
                            onChanged: (v) => unawaited(_setReadsAll(state, bot, v)),
                          ),
                          if (widget.isAdmin)
                            SettingsRow(
                              label: text.groupBotsRemoveAction,
                              destructive: true,
                              enabled: !_busy,
                              onTap: () => unawaited(_remove(state, bot)),
                            ),
                        ],
                      ),
                      const SizedBox(height: PrivioSpacing.lg),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// The "BOT" label, drawn wherever a bot appears.
class _BotBadge extends StatelessWidget {
  const _BotBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: context.accents.surface,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
        child: Text(
          'BOT',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.accents.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
        ),
      );
}

class _Right extends StatelessWidget {
  const _Right({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingsRow(
        label: label,
        enabled: enabled,
        trailing: Switch.adaptive(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      );
}

/// What a bot in this group will be able to read, before it is added.
///
/// A screen rather than a sentence under a switch. What is being agreed to is
/// that somebody outside this group receives messages from it, in the clear,
/// on their own server — and that is not a footnote.
class _WhatItCanRead extends StatelessWidget {
  const _WhatItCanRead({required this.botName});

  final String botName;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surface,
      title: Text(text.groupBotsDisclosureTitle(botName)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text.groupBotsDisclosureReads, style: theme.textTheme.bodyMedium),
            const SizedBox(height: PrivioSpacing.sm),
            Text(text.groupBotsDisclosureNotReads, style: theme.textTheme.bodyMedium),
            const SizedBox(height: PrivioSpacing.sm),
            Text(text.groupBotsDisclosureNoRights, style: theme.textTheme.bodyMedium),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              text.groupBotsDisclosureOperator,
              style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(text.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(text.groupBotsDisclosureAdd),
        ),
      ],
    );
  }
}
