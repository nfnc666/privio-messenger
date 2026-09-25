import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/bot_chat_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import 'bots_screen.dart';

/// A conversation with a bot somebody else runs.
///
/// Three things this screen insists on, in order of how easy they would be to
/// get wrong:
///
/// * **It says what a bot is before the first message.** Not in a settings
///   screen: the moment it matters is the moment somebody is about to write.
/// * **A bot cannot write until it is started.** Before that there is no text
///   field, only the description, the command list and a **Start** button — so
///   the decision is made on what the bot says it does.
/// * **A button is drawn from what the bot sent and pressed once.** A pressed
///   button is shown pressed rather than offered again, because the server
///   refuses a second press and a live-looking button that does nothing is
///   worse than one that looks spent.
class BotChatScreen extends StatefulWidget {
  const BotChatScreen({super.key, required this.botId, this.username});

  /// The bot to open. Empty when opening by [username] instead.
  final String botId;

  /// Opened by exact username, from a link or from the *Open a bot* field.
  final String? username;

  @override
  State<BotChatScreen> createState() => _BotChatScreenState();
}

class _BotChatScreenState extends State<BotChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _warned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final state = PrivioScope.of(context);
    final account = state.accountId;
    if (account == null) return;
    final name = widget.username;
    if (name != null && name.isNotEmpty) {
      await state.botChat.openByUsername(account, name);
    } else {
      await state.botChat.open(account, widget.botId);
    }
    if (mounted) _scrollToEnd();
  }

  /// Said once per opening, before anything is sent.
  Future<void> _warnOnce() async {
    if (_warned || !mounted) return;
    _warned = true;
    final text = AppText.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.botsBadge),
        content: Text(text.botsNotEncrypted),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(text.botsUnderstood),
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    await _warnOnce();
    if (!mounted) return;
    await PrivioScope.of(context).botChat.start();
    if (mounted) _scrollToEnd();
  }

  Future<void> _send(String line) async {
    if (line.trim().isEmpty) return;
    await _warnOnce();
    if (!mounted) return;
    _input.clear();
    await PrivioScope.of(context).botChat.send(line);
    if (mounted) _scrollToEnd();
  }

  Future<void> _stop(BotProfile profile) async {
    final text = AppText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.botChatStopConfirm(profile.username)),
        content: Text(text.botChatStopExplain),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.botChatStop),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await PrivioScope.of(context).botChat.stop();
  }

  /// The published command list, as something to tap rather than remember.
  Future<void> _commands(BotProfile profile) async {
    final text = AppText.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: profile.commands.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(PrivioSpacing.gutter),
                child: Text(text.botChatCommandsEmpty),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final command in profile.commands)
                    ListTile(
                      title: Text('/${command.command}'),
                      subtitle: Text(command.description),
                      onTap: () => Navigator.of(context).pop('/${command.command}'),
                    ),
                ],
              ),
      ),
    );
    if (picked != null) await _send(picked);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).botChat;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final profile = controller.profile;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    profile?.name ?? widget.username ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const BotBadge(),
              ],
            );
          },
        ),
        actions: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final profile = controller.profile;
              if (profile == null) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (choice) {
                  if (choice == 'stop') unawaited(_stop(profile));
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'stop', child: Text(text.botChatStop)),
                ],
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final profile = controller.profile;
          if (profile == null) {
            return Center(
              child: controller.failure != null
                  ? Padding(
                      padding: const EdgeInsets.all(PrivioSpacing.gutter),
                      child: Text(
                        controller.failure!.words(text),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: PrivioColors.danger),
                      ),
                    )
                  : const CircularProgressIndicator(),
            );
          }

          return Column(
            children: [
              _Header(profile: profile),
              Expanded(
                child: controller.messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(PrivioSpacing.gutter),
                          child: Text(
                            text.botChatEmpty,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(PrivioSpacing.gutter),
                        itemCount: controller.messages.length,
                        itemBuilder: (context, index) => _Bubble(
                          message: controller.messages[index],
                          onPress: (button) => unawaited(
                            controller.press(controller.messages[index].id, button.id),
                          ),
                        ),
                      ),
              ),
              if (controller.failure != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                  child: Text(
                    controller.failure!.words(text),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: PrivioColors.danger),
                  ),
                ),
              if (profile.started)
                _Composer(
                  input: _input,
                  busy: controller.busy,
                  onSend: (line) => unawaited(_send(line)),
                  onCommands: () => unawaited(_commands(profile)),
                )
              else
                _StartBar(
                  stopped: profile.stopped,
                  busy: controller.busy,
                  onStart: () => unawaited(_start()),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Who this is, and what it says it does.
class _Header extends StatelessWidget {
  const _Header({required this.profile});

  final BotProfile profile;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Container(
      width: double.infinity,
      color: PrivioColors.surfaceRaised,
      padding: const EdgeInsets.all(PrivioSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('@${profile.username}', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: PrivioSpacing.xs),
          Text(profile.description ?? text.botChatNoDescription),
          const SizedBox(height: PrivioSpacing.sm),
          // The operator, said on the screen rather than in a document: what a
          // bot is, is the thing somebody needs before they type.
          Text(
            text.botChatOperator,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// One message, with its buttons if it has any.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onPress});

  final BotMessage message;
  final void Function(BotButton button) onPress;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: PrivioSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.md,
          vertical: PrivioSpacing.sm,
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: message.mine ? context.accents.surface : PrivioColors.surfaceRaised,
          borderRadius: const BorderRadius.all(PrivioRadius.bubble),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text),
            for (final button in message.buttons) ...[
              const SizedBox(height: PrivioSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: message.pressed.contains(button.id)
                    // Pressed. Shown as what happened, not as an invitation to
                    // press again — the server refuses that, and a button that
                    // looks live but does nothing is the worse of the two.
                    ? OutlinedButton(
                        onPressed: null,
                        child: Text('${button.label} · ${text.botChatButtonPressed}'),
                      )
                    : OutlinedButton(
                        onPressed: () => onPress(button),
                        child: Text(button.label),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What stands where the text field would be, before the bot is started.
class _StartBar extends StatelessWidget {
  const _StartBar({required this.stopped, required this.busy, required this.onStart});

  final bool stopped;
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.gutter),
        child: Column(
          children: [
            Text(
              stopped ? text.botChatStopped : text.botChatStartHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onStart,
                child: Text(text.botChatStart),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.busy,
    required this.onSend,
    required this.onCommands,
  });

  final TextEditingController input;
  final bool busy;
  final void Function(String line) onSend;
  final VoidCallback onCommands;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.md),
        child: Row(
          children: [
            IconButton(
              onPressed: onCommands,
              tooltip: text.botChatCommands,
              icon: const Icon(Icons.menu_rounded),
            ),
            Expanded(
              child: TextField(
                controller: input,
                onSubmitted: onSend,
                decoration: InputDecoration(hintText: text.botChatHint, isDense: true),
              ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            IconButton(
              onPressed: busy ? null : () => onSend(input.text),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
