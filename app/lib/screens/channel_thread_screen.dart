import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';
import '../widgets/linked_text.dart';
import '../widgets/privio_back_button.dart';

/// The conversation under one channel post.
///
/// A thread reads forwards, unlike the feed above it: the post is the top of
/// the screen and the replies run down from it in the order they were written.
///
/// Comments are sealed with the same channel key as the post, so a device that
/// cannot read the post cannot read the thread either — and a padlock here
/// means exactly what it means in the feed. Moderation can only ever be
/// "remove this" and "stop this account writing more", because the server
/// cannot read a word of it and a channel that promised filtering would be
/// promising something it would have to break encryption to deliver.
class ChannelThreadScreen extends StatefulWidget {
  const ChannelThreadScreen({required this.channel, required this.post, super.key});

  final ChannelInfo channel;
  final ChannelPost post;

  @override
  State<ChannelThreadScreen> createState() => _ChannelThreadScreenState();
}

class _ChannelThreadScreenState extends State<ChannelThreadScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PrivioScope.of(context).channels.loadComments(widget.channel.id, widget.post.id);
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.comment(widget.channel.id, widget.post.id, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _composer.clear();
    } else {
      _say(controller.error ?? 'Could not post that comment.');
    }
  }

  Future<void> _remove(ChannelComment comment) async {
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.deleteComment(
      widget.channel.id,
      widget.post.id,
      comment.id,
    );
    if (!mounted) return;
    if (!ok) _say(controller.error ?? 'Could not remove that comment.');
  }

  /// Silencing somebody from the thread they are speaking in, which is where an
  /// admin actually notices they should be.
  Future<void> _silence(ChannelComment comment) async {
    final accountId = comment.authorAccountId;
    if (accountId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surfaceRaised,
        title: Text('Stop ${comment.authorUsername ?? 'them'} posting?'),
        content: const Text(
          'They stay in the channel and can go on reading it. They cannot '
          'comment or react until you undo this.\n\n'
          'Removing them from the channel is the other, heavier thing: that '
          'rotates the key and takes their reading with it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop them'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = PrivioScope.of(context).channels;
    final ok = await controller.setBanned(widget.channel.id, accountId, banned: true);
    if (!mounted) return;
    _say(
      ok
          ? '${comment.authorUsername ?? 'They'} can still read the channel, but not post in it.'
          : controller.error ?? 'Could not do that.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final controller = state.channels;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final comments = controller.commentsOn(widget.post.id);

        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: const Text('Comments'),
          ),
          body: Column(
            children: [
              // The post itself, so the thread has something to be about
              // without scrolling back to the feed.
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(PrivioSpacing.gutter),
                padding: const EdgeInsets.all(PrivioSpacing.lg),
                decoration: BoxDecoration(
                  color: PrivioColors.surfaceRaised,
                  borderRadius: const BorderRadius.all(PrivioRadius.card),
                  border: Border.all(color: PrivioColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.post.authorUsername ?? 'Unknown',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: PrivioColors.accentBright),
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      widget.post.opened
                          ? widget.post.body
                          : 'Encrypted — this device has no key for it.',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: comments.isEmpty
                    ? const _NoComments()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PrivioSpacing.gutter,
                        ),
                        itemCount: comments.length,
                        itemBuilder: (context, index) => _CommentRow(
                          comment: comments[index],
                          channel: widget.channel,
                          mine: comments[index].authorUsername != null &&
                              comments[index].authorUsername == state.username,
                          onRemove: () => _remove(comments[index]),
                          onSilence: () => _silence(comments[index]),
                        ),
                      ),
              ),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                  child: Text(
                    controller.error!,
                    style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                  ),
                ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(PrivioSpacing.md),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: PrivioColors.border)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _composer,
                          // A device with no current key cannot seal a comment,
                          // and the server would refuse it anyway.
                          enabled: widget.channel.hasCurrentKey,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: widget.channel.hasCurrentKey
                                ? 'Comment'
                                : 'No key for this channel',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: PrivioSpacing.sm),
                      IconButton.filled(
                        onPressed:
                            widget.channel.hasCurrentKey && !_sending ? _send : null,
                        style: IconButton.styleFrom(backgroundColor: PrivioColors.accent),
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: PrivioColors.background,
                                size: 18,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.channel,
    required this.mine,
    required this.onRemove,
    required this.onSilence,
  });

  final ChannelComment comment;
  final ChannelInfo channel;
  final bool mine;
  final VoidCallback onRemove;
  final VoidCallback onSilence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canModerate = channel.permissions.canDeletePosts;
    final canSilence = channel.permissions.canManageMembers &&
        !mine &&
        comment.authorAccountId != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.authorUsername ?? 'Deleted account',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: PrivioColors.accentBright),
                    ),
                    const SizedBox(width: PrivioSpacing.sm),
                    Text(_time(comment.createdAt), style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 2),
                if (comment.opened)
                  LinkedText(comment.body, style: theme.textTheme.bodyMedium)
                else
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_rounded,
                        size: 14,
                        color: PrivioColors.textTertiary,
                      ),
                      const SizedBox(width: PrivioSpacing.xs),
                      Text(
                        'Encrypted — no key for it on this device.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (mine || canModerate || canSilence)
            PopupMenuButton<String>(
              color: PrivioColors.surfaceHigh,
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              onSelected: (value) => value == 'remove' ? onRemove() : onSilence(),
              itemBuilder: (_) => [
                if (mine || canModerate)
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(
                      mine ? 'Delete' : 'Remove',
                      style: const TextStyle(color: PrivioColors.danger),
                    ),
                  ),
                if (canSilence)
                  const PopupMenuItem(value: 'silence', child: Text('Stop them posting')),
              ],
            ),
        ],
      ),
    );
  }

  static String _time(DateTime when) {
    final now = DateTime.now();
    final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    return sameDay ? '$hh:$mm' : '${when.day}.${when.month}. $hh:$mm';
  }
}

class _NoComments extends StatelessWidget {
  const _NoComments();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mode_comment_outlined,
              size: 36,
              color: PrivioColors.textTertiary,
            ),
            const SizedBox(height: PrivioSpacing.md),
            Text('No comments yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.xs),
            Text(
              'Comments are encrypted with the channel key, like the posts. '
              'The server stores them and cannot read them.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
