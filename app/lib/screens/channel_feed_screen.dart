import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';
import 'channel_members_screen.dart';
import '../widgets/privio_back_button.dart';

/// One channel's feed.
///
/// Posts are decrypted on this device with the channel key. A post that will
/// not open is shown as a padlock rather than dropped: a reader who is missing
/// the key should see that something is there and that they cannot read it,
/// which is a different problem from an empty channel.
class ChannelFeedScreen extends StatefulWidget {
  const ChannelFeedScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelFeedScreen> createState() => _ChannelFeedScreenState();
}

class _ChannelFeedScreenState extends State<ChannelFeedScreen> {
  final TextEditingController _composer = TextEditingController();
  late ChannelInfo _channel = widget.channel;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final controller = PrivioScope.of(context).channels;
    if (_channel.isMember) await controller.loadPosts(_channel.id);
    final fresh = controller.channelById(_channel.id);
    if (fresh != null && mounted) setState(() => _channel = fresh);
  }

  Future<void> _join() async {
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.join(_channel);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not join')),
      );
      return;
    }
    final joined = controller.channelById(_channel.id);
    if (joined != null) setState(() => _channel = joined);
    await _load();
  }

  Future<void> _publish() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.publish(_channel.id, text);
    if (!mounted) return;
    setState(() => _sending = false);

    if (ok) {
      _composer.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not publish')),
      );
    }
  }

  Future<void> _share() async {
    final controller = PrivioScope.of(context).channels;

    final link = controller.inviteLink(_channel);
    if (!mounted) return;

    if (link == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _InviteDialog(link: link),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surfaceRaised,
        title: const Text('Delete channel?'),
        content: const Text(
          'The channel and every post in it are removed for everyone. '
          'Nothing undoes this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = PrivioScope.of(context).channels;
    final ok = await controller.delete(_channel.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not delete the channel')),
      );
    }
  }

  Future<void> _leave() async {
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.leave(_channel.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not leave the channel')),
      );
    }
  }

  Future<void> _openMembers() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChannelMembersScreen(channel: _channel)),
    );
  }

  void _onMenu(String action) {
    switch (action) {
      case 'invite':
        _share();
      case 'members':
        _openMembers();
      case 'leave':
        _leave();
      case 'delete':
        _confirmDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final controller = state.channels;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Re-read on every build: a key can arrive while this screen is open,
        // and the padlocks should clear where the reader is already looking.
        final channel = controller.channelById(_channel.id) ?? _channel;
        final posts = controller.postsIn(channel.id);
        final canPost = channel.permissions.canPost;

        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(channel.title, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  '${channel.isPublic ? 'Public' : 'Private'} · '
                  '${channel.memberLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              if (channel.isMember)
                PopupMenuButton<String>(
                  onSelected: _onMenu,
                  color: PrivioColors.surfaceRaised,
                  itemBuilder: (_) => [
                    if (channel.inviteCode != null)
                      const PopupMenuItem(value: 'invite', child: Text('Invite link')),
                    const PopupMenuItem(value: 'members', child: Text('Members')),
                    if (channel.role != 'owner')
                      const PopupMenuItem(value: 'leave', child: Text('Leave channel')),
                    if (channel.permissions.canDeleteChannel)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete channel', style: TextStyle(color: PrivioColors.danger)),
                      ),
                  ],
                ),
              const SizedBox(width: PrivioSpacing.xs),
            ],
          ),
          body: Column(
            children: [
              if (!channel.hasKey && channel.isMember) const _MissingKeyBanner(),
              Expanded(
                child: !channel.isMember
                    ? _JoinPrompt(channel: channel, onJoin: _join)
                    : posts.isEmpty
                        ? const _EmptyFeed()
                        : RefreshIndicator(
                            color: PrivioColors.accent,
                            backgroundColor: PrivioColors.surface,
                            onRefresh: () => controller.loadPosts(channel.id),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(PrivioSpacing.gutter),
                              itemCount: posts.length,
                              itemBuilder: (context, index) => _PostCard(
                                post: posts[index],
                                channel: channel,
                                onPin: () => controller.pin(
                                  channel.id,
                                  posts[index].id,
                                  pinned: !posts[index].pinned,
                                ),
                                onDelete: () =>
                                    controller.deletePost(channel.id, posts[index].id),
                              ),
                            ),
                          ),
              ),
              if (channel.isMember && canPost)
                _Composer(
                  controller: _composer,
                  sending: _sending,
                  enabled: channel.hasKey,
                  onSend: _publish,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.channel,
    required this.onPin,
    required this.onDelete,
  });

  final ChannelPost post;
  final ChannelInfo channel;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canModerate =
        channel.permissions.canEditChannel || channel.permissions.canDeletePosts;

    return Container(
      margin: const EdgeInsets.only(bottom: PrivioSpacing.md),
      padding: const EdgeInsets.all(PrivioSpacing.lg),
      decoration: BoxDecoration(
        color: PrivioColors.surfaceRaised,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        border: post.pinned
            ? Border.all(color: PrivioColors.accentDim)
            : Border.all(color: PrivioColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (post.pinned) ...[
                const Icon(Icons.push_pin_rounded, size: 14, color: PrivioColors.accent),
                const SizedBox(width: PrivioSpacing.xs),
              ],
              Expanded(
                child: Text(
                  post.authorUsername ?? 'Unknown',
                  style: theme.textTheme.labelLarge?.copyWith(color: PrivioColors.accentBright),
                ),
              ),
              Text(_formatTime(post.createdAt), style: theme.textTheme.bodySmall),
              if (canModerate)
                PopupMenuButton<String>(
                  color: PrivioColors.surfaceHigh,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  onSelected: (value) => value == 'pin' ? onPin() : onDelete(),
                  itemBuilder: (_) => [
                    if (channel.permissions.canEditChannel)
                      PopupMenuItem(value: 'pin', child: Text(post.pinned ? 'Unpin' : 'Pin')),
                    if (channel.permissions.canDeletePosts)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: PrivioColors.danger)),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.sm),
          if (post.opened)
            Text(post.body, style: theme.textTheme.bodyMedium)
          else
            Row(
              children: [
                const Icon(Icons.lock_rounded, size: 16, color: PrivioColors.textTertiary),
                const SizedBox(width: PrivioSpacing.sm),
                Expanded(
                  child: Text(
                    'Encrypted — this device has no key for it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime when) {
    final now = DateTime.now();
    final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    if (sameDay) return '$hh:$mm';
    return '${when.day}/${when.month} $hh:$mm';
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: enabled ? 'Write a post' : 'No key for this channel',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            IconButton.filled(
              onPressed: enabled && !sending ? onSend : null,
              style: IconButton.styleFrom(backgroundColor: PrivioColors.accent),
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, color: PrivioColors.background, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteDialog extends StatelessWidget {
  const _InviteDialog({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: const Text('Invite link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(link, style: theme.textTheme.bodySmall),
          const SizedBox(height: PrivioSpacing.md),
          Text(
            'Share this anywhere — it carries no key. Whoever opens it joins the '
            'channel, and the key to read it is sent to their device afterwards, '
            'encrypted, by someone who already has it.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Copy'),
        ),
      ],
    );
  }
}

class _MissingKeyBanner extends StatelessWidget {
  const _MissingKeyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(PrivioSpacing.gutter),
      padding: const EdgeInsets.all(PrivioSpacing.md),
      decoration: BoxDecoration(
        color: PrivioColors.warning.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(PrivioRadius.card),
      ),
      child: Row(
        children: [
          const Icon(Icons.key_off_rounded, size: 18, color: PrivioColors.warning),
          const SizedBox(width: PrivioSpacing.md),
          Expanded(
            child: Text(
              'Waiting for the key. It is sent to this device, encrypted, by '
              'someone already in the channel — the server never holds it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinPrompt extends StatelessWidget {
  const _JoinPrompt({required this.channel, required this.onJoin});

  final ChannelInfo channel;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign_outlined, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text(channel.title, style: theme.textTheme.titleMedium),
            if (channel.description != null) ...[
              const SizedBox(height: PrivioSpacing.xs),
              Text(
                channel.description!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: PrivioSpacing.md),
            Text(
              'Joining gets you the posts. The key that opens them is sent to '
              'your device afterwards by a member, never by the server.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            FilledButton(onPressed: onJoin, child: const Text('Join channel')),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text('No posts yet', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
