import 'dart:async';

import 'package:file_picker/file_picker.dart';
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

  /// Presses the key delivery again, and says what happened.
  ///
  /// Silence would be the worst answer here: the state this fixes already looks
  /// like nothing is happening, so a retry that also looks like nothing is
  /// indistinguishable from a broken button.
  Future<void> _retryKey(String channelId) async {
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.retryKey(channelId);
    if (!mounted) return;
    final fresh = controller.channelById(channelId);
    if (fresh != null) setState(() => _channel = fresh);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !ok
              ? controller.error ?? 'Could not ask for the key.'
              : fresh?.hasCurrentKey ?? false
                  ? 'The key arrived. You can post again.'
                  : 'Asked again. The key is delivered by another member, so it '
                      'arrives when one of them is online.',
        ),
      ),
    );
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

  /// The file waiting to go with the next post, if any.
  ChannelUpload? _pending;

  /// Picks a file for the next post.
  ///
  /// Nothing is uploaded here. The bytes wait in memory until the post is
  /// published, because that is when the channel key is read — and reading it
  /// any earlier would risk sealing under a key that has since been rotated.
  Future<void> _attach() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile().timeout(const Duration(minutes: 2));
    } on Object catch (failure) {
      if (mounted) _say('Could not open the picker: $failure');
      return;
    }
    if (picked == null || !mounted) return;
    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object catch (failure) {
      if (mounted) _say('Could not read ${picked.name}: $failure');
      return;
    }
    if (!mounted) return;
    setState(
      () => _pending = ChannelUpload(bytes: bytes, name: picked!.name),
    );
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _publish() async {
    final text = _composer.text.trim();
    // A picture with no caption is a post; an empty box is not.
    if (text.isEmpty && _pending == null) return;

    setState(() => _sending = true);
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.publish(_channel.id, text, file: _pending);
    if (!mounted) return;
    setState(() => _sending = false);

    if (ok) {
      _composer.clear();
      setState(() => _pending = null);
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
              if (channel.isMember && !channel.hasCurrentKey)
                _MissingKeyBanner(
                  // Two different situations behind one padlock, and the
                  // difference decides whether waiting is any use: a device
                  // that has never had a key is waiting for a first delivery,
                  // while one that holds older versions is waiting for a
                  // rotation somebody set off by leaving or being removed.
                  rotating: channel.hasKey,
                  epoch: channel.keyEpoch,
                  onRetry: () => _retryKey(channel.id),
                ),
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
                  pending: _pending,
                  onAttach: _attach,
                  onDropAttachment: () => setState(() => _pending = null),
                  // Never the old key. Posting under a superseded version is
                  // exactly what a rotation exists to prevent, and the server
                  // would refuse it anyway — so the composer says why instead
                  // of failing on send.
                  enabled: channel.hasCurrentKey,
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
          if (post.opened) ...[
            if (post.body.isNotEmpty) Text(post.body, style: theme.textTheme.bodyMedium),
            if (post.attachment != null) ...[
              if (post.body.isNotEmpty) const SizedBox(height: PrivioSpacing.sm),
              _AttachmentTile(channelId: channel.id, post: post),
            ],
          ] else
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
    this.pending,
    this.onAttach,
    this.onDropAttachment,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  /// The file that will go with the next post, before it is sealed.
  final ChannelUpload? pending;
  final VoidCallback? onAttach;
  final VoidCallback? onDropAttachment;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(PrivioSpacing.md),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PrivioColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // What is about to be sent, so nobody publishes a file they picked
            // and forgot about.
            if (pending != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file_rounded, size: 16, color: PrivioColors.accent),
                    const SizedBox(width: PrivioSpacing.xs),
                    Expanded(
                      child: Text(
                        '${pending!.name ?? 'File'} · ${_readableSize(pending!.bytes.length)}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      onPressed: sending ? null : onDropAttachment,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: 'Remove the file',
                    ),
                  ],
                ),
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: enabled && !sending ? onAttach : null,
                  icon: const Icon(Icons.attach_file_rounded),
                  tooltip: 'Attach a picture or a file',
                ),
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
          ],
        ),
      ),
    );
  }
}

/// A post's file: what it is, and a way to open it.
///
/// Nothing is downloaded until it is asked for. A channel feed that fetched
/// every picture on the way past would spend a stranger's data allowance on a
/// channel they are only glancing at — and on a metered connection that is a
/// cost, not a convenience.
class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({required this.channelId, required this.post});

  final String channelId;
  final ChannelPost post;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _busy = false;
  Uint8List? _opened;

  Future<void> _open() async {
    final attachment = widget.post.attachment;
    if (attachment == null || _busy) return;
    setState(() => _busy = true);
    final controller = PrivioScope.of(context).channels;
    final bytes = await controller.openAttachment(widget.channelId, widget.post);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _opened = bytes;
    });
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not open that file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.post.attachment!;
    final opened = _opened;

    // Once an image is open it is the point, so it replaces its own row.
    if (opened != null && attachment.isImage) {
      return ClipRRect(
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        child: Image.memory(opened, fit: BoxFit.cover),
      );
    }

    return InkWell(
      onTap: _busy ? null : _open,
      borderRadius: const BorderRadius.all(PrivioRadius.card),
      child: Container(
        padding: const EdgeInsets.all(PrivioSpacing.md),
        decoration: const BoxDecoration(
          color: PrivioColors.surfaceRaised,
          borderRadius: BorderRadius.all(PrivioRadius.card),
        ),
        child: Row(
          children: [
            if (_busy)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(
                attachment.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
                size: 18,
                color: PrivioColors.accent,
              ),
            const SizedBox(width: PrivioSpacing.md),
            Expanded(
              child: Text(
                attachment.name ?? (attachment.isImage ? 'Picture' : 'File'),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            Text(
              opened != null ? 'Opened' : _readableSize(attachment.bytes),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bytes as something a person reads without counting zeros.
String _readableSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
  const _MissingKeyBanner({this.rotating = false, this.epoch = 1, this.onRetry});

  /// Tries the key delivery again. Null leaves the banner as an explanation.
  final VoidCallback? onRetry;

  /// True when this device already reads some of the channel and is waiting for
  /// a new version, rather than waiting for its first key ever.
  final bool rotating;

  final int epoch;

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
          Icon(
            rotating ? Icons.autorenew_rounded : Icons.key_off_rounded,
            size: 18,
            color: PrivioColors.warning,
          ),
          const SizedBox(width: PrivioSpacing.md),
          Expanded(
            child: Text(
              rotating
                  ? 'Someone left this channel, so it is changing its key '
                      '(version $epoch). Posts from before are still readable. '
                      'New ones open once the new key reaches this device.'
                  : 'Waiting for the key. It is sent to this device, encrypted, '
                      'by someone already in the channel — the server never '
                      'holds it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: PrivioSpacing.sm),
            TextButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
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
