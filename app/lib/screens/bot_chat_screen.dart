import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/bot_chat_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/channel_text.dart';
import '../l10n/failure_text.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/poll_option_row.dart';
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
/// * **A poll says who sees the answer.** The bot does, by name — that is the
///   difference from a channel poll, and it is printed on the card rather than
///   left for somebody to assume.
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
                          busy: controller.busy,
                          onPress: (button) => unawaited(
                            controller.press(controller.messages[index].id, button.id),
                          ),
                          onVote: (options) =>
                              controller.vote(controller.messages[index].id, options),
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
  const _Bubble({
    required this.message,
    required this.onPress,
    required this.onVote,
    this.busy = false,
  });

  final BotMessage message;
  final void Function(BotButton button) onPress;
  final Future<bool> Function(List<int> options) onVote;
  final bool busy;

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
            if (message.hasMedia) ...[
              _Media(message: message),
              const SizedBox(height: PrivioSpacing.xs),
            ],
            // A picture with no caption arrives with a single space, so an
            // empty-looking line is not drawn under it.
            if (message.text.trim().isNotEmpty) Text(message.text),
            if (message.poll != null) ...[
              if (message.text.trim().isNotEmpty) const SizedBox(height: PrivioSpacing.sm),
              _BotPollCard(poll: message.poll!, busy: busy, onVote: onVote),
            ],
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

/// A poll a bot asked.
///
/// Answered the way a channel poll is — one tap is the answer in a one-answer
/// poll and tapping it again takes it back; a poll that takes several gathers
/// them and sends with a button — so the two kinds of poll do not teach two
/// habits. What is different is said on the card: the bot sees who answered
/// what, and whether anybody else's answers are shown is the bot's choice.
class _BotPollCard extends StatefulWidget {
  const _BotPollCard({required this.poll, required this.busy, required this.onVote});

  final BotPoll poll;
  final bool busy;
  final Future<bool> Function(List<int> options) onVote;

  @override
  State<_BotPollCard> createState() => _BotPollCardState();
}

class _BotPollCardState extends State<_BotPollCard> {
  bool _sending = false;

  /// What is picked but not yet sent, in a poll that takes several answers.
  /// Null while untouched, so the server's own answer shows.
  Set<int>? _draft;

  Set<int> get _selected => _draft ?? widget.poll.myVotes;

  bool get _canAnswer => !widget.poll.isClosed && !widget.busy && !_sending;

  @override
  void didUpdateWidget(covariant _BotPollCard old) {
    super.didUpdateWidget(old);
    // A reload brought the server's answer: a draft from before it would show
    // a choice that is no longer the one on record.
    // Compared by content: every reload builds new sets, and comparing those by
    // identity would throw away a half-made choice whenever anything else in
    // the chat refreshed.
    if (!setEquals(old.poll.myVotes, widget.poll.myVotes)) _draft = null;
  }

  Future<void> _send(List<int> options) async {
    if (_sending) return;
    setState(() => _sending = true);
    await widget.onVote(options);
    // Cleared either way: on success the reload has the server's answer, and on
    // failure a draft left behind would show a vote nobody cast.
    if (mounted) {
      setState(() {
        _sending = false;
        _draft = null;
      });
    }
  }

  void _tap(int index) {
    final poll = widget.poll;
    if (!_canAnswer) return;
    if (!poll.takesSeveral) {
      unawaited(_send(poll.myVotes.contains(index) ? const [] : [index]));
      return;
    }
    final next = {..._selected};
    if (next.contains(index)) {
      next.remove(index);
    } else if (next.length < poll.maxChoices) {
      next.add(index);
    } else {
      return;
    }
    setState(() => _draft = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final poll = widget.poll;
    final voters = poll.voters;

    final facts = [
      if (poll.takesSeveral) text.feedPollPickUpTo(poll.maxChoices) else text.feedPollPickOne,
      if (poll.isClosed)
        text.feedPollClosed
      else if (poll.closesAt != null)
        text.feedPollCloses(formatWhenLabel(text, poll.closesAt!)),
      if (voters != null) text.feedPollVoters(voters),
    ].join(' · ');

    // Why there are no bars, when there are none. "Nobody voted" and "not
    // yours to see" look identical as empty tracks, and they are not the same.
    final String? resultsNote = poll.resultsVisible
        ? null
        : poll.showResults
            ? text.botPollResultsAfterAnswer
            : text.botPollResultsHidden;

    return Container(
      padding: const EdgeInsets.all(PrivioSpacing.md),
      decoration: const BoxDecoration(
        color: PrivioColors.surfaceHigh,
        borderRadius: BorderRadius.all(PrivioRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(poll.question, style: theme.textTheme.titleSmall),
          const SizedBox(height: PrivioSpacing.xs),
          Text(facts, style: theme.textTheme.bodySmall),
          const SizedBox(height: PrivioSpacing.sm),
          for (var index = 0; index < poll.options.length; index++)
            PollOptionRow(
              label: poll.options[index],
              count: poll.countFor(index),
              share: poll.shareOf(index),
              chosen: _selected.contains(index),
              showResults: poll.resultsVisible,
              enabled: _canAnswer,
              onTap: () => _tap(index),
            ),
          if (poll.takesSeveral && !poll.isClosed) ...[
            const SizedBox(height: PrivioSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _canAnswer ? () => unawaited(_send(_selected.toList())) : null,
                child: Text(
                  _selected.isEmpty ? text.feedPollClearAnswer : text.feedPollAnswer,
                ),
              ),
            ),
          ],
          const SizedBox(height: PrivioSpacing.xs),
          // The one thing a bot poll must not let anybody assume otherwise.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.visibility_outlined,
                  size: 14,
                  color: PrivioColors.textTertiary,
                ),
              ),
              const SizedBox(width: PrivioSpacing.xs),
              Expanded(
                child: Text(
                  [text.botPollBotSees, if (resultsNote != null) resultsNote].join(' '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A picture or a file a bot sent.
///
/// The bytes are fetched once and kept in memory by the controller. A declared
/// image that does not decode falls back to the file row rather than showing a
/// broken frame: the kind came from the bot, and the bot can be wrong.
class _Media extends StatelessWidget {
  const _Media({required this.message});

  final BotMessage message;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).botChat;
    final mediaId = message.mediaId;
    if (mediaId == null) {
      // The blob expired and the sweeper took it. The message stays, which is
      // the honest thing to draw.
      return _FileRow(message: message, note: text.botChatFileGone);
    }

    return FutureBuilder<Uint8List?>(
      future: controller.mediaBytes(mediaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _FileRow(message: message, busy: true);
        }
        final bytes = snapshot.data;
        if (bytes == null) return _FileRow(message: message, note: text.botChatFileGone);
        if (!message.isImage) {
          return InkWell(
            onTap: () => PhotoViewer.open(context, bytes: bytes, name: message.fileName),
            child: _FileRow(message: message),
          );
        }
        return ClipRRect(
          borderRadius: const BorderRadius.all(PrivioRadius.bubble),
          child: GestureDetector(
            onTap: () => PhotoViewer.open(context, bytes: bytes, name: message.fileName),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _FileRow(message: message, note: text.botChatImageBroken),
            ),
          ),
        );
      },
    );
  }
}

/// A file, as a row with its name and size.
class _FileRow extends StatelessWidget {
  const _FileRow({required this.message, this.note, this.busy = false});

  final BotMessage message;
  final String? note;
  final bool busy;

  String _size() {
    final bytes = message.byteSize;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final failed = note != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: PrivioColors.surfaceHigh,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  failed ? Icons.error_outline_rounded : Icons.insert_drive_file_outlined,
                  size: 20,
                  color: failed ? PrivioColors.danger : PrivioColors.textSecondary,
                ),
        ),
        const SizedBox(width: PrivioSpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.fileName ?? _size(),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                note ?? _size(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: failed ? PrivioColors.danger : null,
                    ),
              ),
            ],
          ),
        ),
      ],
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
