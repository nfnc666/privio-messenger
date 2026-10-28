import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../theme/privio_colors.dart';
import 'poll_option_row.dart';

/// A poll inside a chat bubble: the question, the answers and — once this
/// account has voted or the poll has ended — the tally this device has counted.
///
/// Answered with the same rows as a channel poll. A one-answer poll is sent by
/// the tap itself, and tapping the chosen answer again takes the vote back; a
/// poll that takes several answers gathers them first and sends them with a
/// button, because a vote is always sent whole.
class ChatPollCard extends StatefulWidget {
  const ChatPollCard({
    super.key,
    required this.question,
    required this.poll,
    required this.myChoices,
    this.onVote,
  });

  final String question;
  final ChatPoll poll;
  final Set<int> myChoices;

  /// Null where this account cannot vote: a poll still waiting to go out, or
  /// one shown somewhere other than its chat.
  final ValueChanged<Set<int>>? onVote;

  @override
  State<ChatPollCard> createState() => _ChatPollCardState();
}

class _ChatPollCardState extends State<ChatPollCard> {
  late Set<int> _selected = {...widget.myChoices};

  @override
  void didUpdateWidget(ChatPollCard old) {
    super.didUpdateWidget(old);
    // A vote that arrived from this account's other device moves the ticks.
    if (old.myChoices != widget.myChoices) _selected = {...widget.myChoices};
  }

  bool get _canVote => widget.onVote != null && !widget.poll.closed;

  void _tap(int index) {
    if (!widget.poll.takesSeveral) {
      final choice = widget.myChoices.contains(index) ? <int>{} : {index};
      setState(() => _selected = choice);
      widget.onVote!(choice);
      return;
    }
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else if (_selected.length < widget.poll.maxChoices) {
        _selected.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final poll = widget.poll;
    final showResults = widget.myChoices.isNotEmpty || poll.closed;
    final changed = _selected.length != widget.myChoices.length ||
        !_selected.containsAll(widget.myChoices);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.poll_outlined, size: 16, color: PrivioColors.textSecondary),
            const SizedBox(width: PrivioSpacing.xs),
            Flexible(child: Text(widget.question, style: theme.textTheme.titleSmall)),
          ],
        ),
        const SizedBox(height: PrivioSpacing.xs),
        Text(
          [
            if (poll.takesSeveral) text.feedPollPickUpTo(poll.maxChoices) else text.feedPollPickOne,
            if (poll.closed) text.chatPollEnded,
            text.feedPollVoters(poll.voters),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.sm),
        for (var index = 0; index < poll.options.length; index++)
          PollOptionRow(
            label: poll.options[index],
            count: poll.countFor(index),
            share: poll.shareOf(index),
            chosen: _selected.contains(index),
            showResults: showResults,
            enabled: _canVote,
            onTap: () => _tap(index),
          ),
        if (poll.takesSeveral && _canVote && changed)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => widget.onVote!({..._selected}),
              child: Text(_selected.isEmpty ? text.feedPollClearAnswer : text.feedPollAnswer),
            ),
          ),
      ],
    );
  }
}
