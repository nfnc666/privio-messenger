import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../theme/privio_colors.dart';
import '../widgets/channel_avatar.dart';
import '../widgets/linked_text.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import 'channel_admins_screen.dart';
import 'channel_edit_screen.dart';
import 'channel_subscribers_screen.dart';

/// A channel's front page: who it is, what it links to, and what it holds.
///
/// It used to be an app bar and an overflow menu on the feed. That is where
/// everything ended up because there was nowhere else to put it, and it meant
/// the channel's own identity — its picture, its name, its link, how many
/// people are in it — was a 36-point avatar and two lines of grey text.
///
/// The layout follows the supplied design: a big round picture, the name and
/// the audience under it, four equal actions, then the link and the management
/// rows as separate cards on black. The accent is Privio's green throughout;
/// nothing here is blue.
class ChannelProfileScreen extends StatefulWidget {
  const ChannelProfileScreen({required this.channel, super.key, this.onSearch});

  final ChannelInfo channel;

  /// Opens search back on the feed, where the results are. Null when the
  /// profile was reached from somewhere that has no feed behind it.
  final VoidCallback? onSearch;

  @override
  State<ChannelProfileScreen> createState() => _ChannelProfileScreenState();
}

enum _Tab { media, links }

class _ChannelProfileScreenState extends State<ChannelProfileScreen> {
  _Tab _tab = _Tab.media;
  ChannelLive? _live;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final controller = PrivioScope.of(context).channels;
    await controller.loadPosts(widget.channel.id);
    if (!mounted) return;
    // Asked for rather than assumed: the answer includes whether this
    // deployment has a media server at all, which is what decides between a
    // working button and one that says why it is not.
    final live = await controller.live(widget.channel.id);
    if (mounted) setState(() => _live = live);
  }

  ChannelInfo get _channel =>
      PrivioScope.of(context).channels.channelById(widget.channel.id) ?? widget.channel;

  // --- The four actions -----------------------------------------------------

  Future<void> _toggleMute() async {
    final channel = _channel;
    final controller = PrivioScope.of(context).channels;
    if (channel.muted) {
      await controller.unmute(channel.id);
      return;
    }
    final until = await showModalBottomSheet<({DateTime? until, bool go})>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (_) => const _MuteSheet(),
    );
    if (until == null || !until.go || !mounted) return;
    await controller.mute(channel.id, until: until.until);
  }

  Future<void> _live_() async {
    final channel = _channel;
    final live = _live;
    final controller = PrivioScope.of(context).channels;

    // The honest case, and the common one: no media server is configured, so
    // there is nothing to join and the screen says exactly that instead of
    // opening something empty.
    if (live == null || !live.available) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: PrivioColors.surface,
          title: const Text('Livestreams are not set up'),
          content: const Text(
            'A livestream needs a media server: one person sends video and '
            'everybody else receives it, which cannot be done device to device '
            'the way a call is.\n\n'
            'This Privio server has none configured, so there is nothing to '
            'join yet. Whoever runs it can set one up.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Alright'),
            ),
          ],
        ),
      );
      return;
    }

    if (live.isRunning) {
      await _openLive(live);
      return;
    }
    if (!live.canStart) {
      _say('Nobody is streaming right now.');
      return;
    }
    final started = await controller.startLive(channel.id);
    if (!mounted) return;
    if (started == null) {
      _say(controller.error ?? 'Could not start the stream.');
      return;
    }
    setState(() => _live = started);
    await _openLive(started);
  }

  Future<void> _openLive(ChannelLive live) async {
    // Deliberately not a player yet: see docs/channels.md. The room and token
    // are real and the server issued them; what is missing is the client half
    // of an SFU, which is its own piece of work and is not going to be faked
    // with a dialog that pretends to be a video.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(live.canPublish ? 'You are live' : 'A stream is running'),
        content: Text(
          live.canPublish
              ? 'The room is open and your device has a token to publish to it. '
                  'Privio does not carry the video itself yet — the media server '
                  'does — so nothing is being sent from this screen.\n\n'
                  'End it when you are done.'
              : 'A stream is running and this device has a token to watch it. '
                  'Privio cannot show the video yet.',
        ),
        actions: [
          if (live.canPublish)
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await PrivioScope.of(context).channels.endLive(_channel.id);
                if (mounted) setState(() => _live = null);
              },
              child: const Text('End it', style: TextStyle(color: PrivioColors.danger)),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _more() async {
    final channel = _channel;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Copy link'),
              onTap: () => Navigator.of(sheetContext).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_rounded),
              title: const Text('QR code'),
              onTap: () => Navigator.of(sheetContext).pop('qr'),
            ),
            if (channel.permissions.canManageInvites)
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Invite settings'),
                onTap: () => Navigator.of(sheetContext).pop('invite'),
              ),
            if (channel.permissions.canEditChannel)
              ListTile(
                leading: const Icon(Icons.insights_rounded),
                title: const Text('Statistics'),
                onTap: () => Navigator.of(sheetContext).pop('stats'),
              ),
            if (channel.isMember && channel.role != 'owner')
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report channel'),
                onTap: () => Navigator.of(sheetContext).pop('report'),
              ),
            if (channel.isMember && channel.role != 'owner')
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: PrivioColors.danger),
                title: const Text(
                  'Leave channel',
                  style: TextStyle(color: PrivioColors.danger),
                ),
                onTap: () => Navigator.of(sheetContext).pop('leave'),
              ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'copy':
        await _copyLink();
      case 'qr':
        await _showQr();
      case 'leave':
        await _confirmLeave();
      default:
        // Invite settings, statistics and reporting live on the feed screen,
        // which is where their sheets already are. Popping back to it rather
        // than building a second copy of each is the whole point of not
        // starting a second channel system.
        if (mounted) Navigator.of(context).pop(action);
    }
  }

  Future<void> _copyLink() async {
    final link = ChannelService.shareLinkFor(_channel);
    if (link == null) {
      _say('This channel has no link to share.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    _say('Link copied.');
  }

  Future<void> _showQr() async {
    final link = ChannelService.shareLinkFor(_channel);
    if (link == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(PrivioSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(PrivioSpacing.md),
              ),
              child: QrImageView(data: link, size: 220),
            ),
            const SizedBox(height: PrivioSpacing.md),
            SelectableText(link, style: Theme.of(dialogContext).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Leave this channel?'),
        content: const Text(
          'You stop receiving its posts. The channel moves to a new key, so '
          'nothing published after this is readable to you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave', style: TextStyle(color: PrivioColors.danger)),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final controller = PrivioScope.of(context).channels;
    if (await controller.leave(_channel.id) && mounted) {
      // Two pops: this screen and the feed behind it. The channel is gone from
      // both.
      Navigator.of(context).pop('left');
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final controller = state.channels;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final channel = _channel;
        final link = ChannelService.shareLinkFor(channel);
        // Narrowed once here rather than with a `!` at the use site: the
        // analyzer cannot see that the outer `isNotEmpty` guard implies
        // non-null, and a bang is a promise nobody checks.
        final descriptionOrNull = channel.description?.trim();
        final description =
            (descriptionOrNull?.isNotEmpty ?? false) ? descriptionOrNull! : null;
        final posts = controller.postsIn(channel.id);

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            actions: [
              if (channel.permissions.canEditChannel)
                Padding(
                  padding: const EdgeInsets.only(right: PrivioSpacing.md),
                  child: TextButton(
                    onPressed: () => unawaited(_edit()),
                    style: TextButton.styleFrom(
                      backgroundColor: PrivioColors.surfaceRaised,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: PrivioSpacing.lg,
                        vertical: PrivioSpacing.sm,
                      ),
                    ),
                    child: const Text('Edit'),
                  ),
                ),
            ],
          ),
          body: RefreshIndicator(
            color: PrivioColors.accent,
            backgroundColor: PrivioColors.surface,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: PrivioSpacing.xl),
              children: [
                // --- Identity ---
                Center(
                  child: ChannelAvatar(
                    channel: channel,
                    imageBytes: controller.avatarFor(channel),
                    size: 96,
                  ),
                ),
                const SizedBox(height: PrivioSpacing.md),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                    child: Text(
                      channel.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.xs),
                Center(
                  child: Text(
                    channel.subscriberLabel,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: PrivioColors.textSecondary),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.lg),

                // --- The four actions ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                  child: Row(
                    children: [
                      _ActionButton(
                        icon: Icons.podcasts_rounded,
                        label: 'livestream',
                        // Dimmed rather than hidden where the server has no
                        // media server: a control that is simply absent teaches
                        // nobody anything, and this one has a reason worth
                        // reading.
                        dimmed: !(_live?.available ?? false),
                        highlighted: _live?.isRunning ?? false,
                        onTap: () => unawaited(_live_()),
                      ),
                      const SizedBox(width: PrivioSpacing.sm),
                      _ActionButton(
                        icon: channel.muted
                            ? Icons.notifications_off_rounded
                            : Icons.notifications_rounded,
                        label: channel.muted ? 'unmute' : 'mute',
                        highlighted: channel.muted,
                        onTap: () => unawaited(_toggleMute()),
                      ),
                      const SizedBox(width: PrivioSpacing.sm),
                      _ActionButton(
                        icon: Icons.search_rounded,
                        label: 'search',
                        onTap: () {
                          final search = widget.onSearch;
                          if (search == null) {
                            Navigator.of(context).pop('search');
                          } else {
                            Navigator.of(context).pop();
                            search();
                          }
                        },
                      ),
                      const SizedBox(width: PrivioSpacing.sm),
                      _ActionButton(
                        icon: Icons.more_horiz_rounded,
                        label: 'more',
                        onTap: () => unawaited(_more()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PrivioSpacing.lg),

                // --- Link and description ---
                if (link != null || description != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                    child: _Card(
                      children: [
                        if (link != null)
                          _LinkRow(
                            link: link,
                            onCopy: () => unawaited(_copyLink()),
                            onQr: () => unawaited(_showQr()),
                          ),
                        if (link != null && description != null)
                          const _Hairline(),
                        if (description != null)
                          Padding(
                            padding: const EdgeInsets.all(PrivioSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Description',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: PrivioColors.textSecondary),
                                ),
                                const SizedBox(height: PrivioSpacing.xs),
                                LinkedText(description),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: PrivioSpacing.lg),

                // --- Management ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                  child: _Card(
                    children: [
                      SettingsRow(
                        icon: Icons.shield_rounded,
                        iconTint: PrivioColors.accent,
                        label: 'Administrators',
                        value: '${controller.adminsOf(channel.id).length}',
                        onTap: () => unawaited(_openAdmins()),
                      ),
                      const _Hairline(),
                      SettingsRow(
                        icon: Icons.people_alt_rounded,
                        iconTint: const Color(0xFF2563EB),
                        label: 'Subscribers',
                        value: '${channel.memberCount}',
                        onTap: () => unawaited(_openSubscribers()),
                      ),
                      if (channel.permissions.canEditChannel) ...[
                        const _Hairline(),
                        SettingsRow(
                          icon: Icons.tune_rounded,
                          iconTint: const Color(0xFFD97706),
                          label: 'Channel settings',
                          onTap: () => unawaited(_edit()),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: PrivioSpacing.lg),

                // --- What the channel holds ---
                Center(
                  child: _Segmented(
                    tab: _tab,
                    onChanged: (tab) => setState(() => _tab = tab),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                  child: _tab == _Tab.media
                      ? _MediaGrid(channel: channel, posts: posts)
                      : _LinkList(posts: posts, onOpen: _jumpToPost),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _edit() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ChannelEditScreen(channel: _channel)),
    );
    if (mounted) await _load();
  }

  Future<void> _openAdmins() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ChannelAdminsScreen(channel: _channel)),
    );
  }

  Future<void> _openSubscribers() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ChannelSubscribersScreen(channel: _channel)),
    );
  }

  /// Back to the feed, at the post a link was found in.
  void _jumpToPost(ChannelPost post) => Navigator.of(context).pop('post:${post.id}');
}

/// One of the four round-cornered actions under the channel's name.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.dimmed = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The action exists but cannot do anything here — it still opens, and what
  /// it opens says why.
  final bool dimmed;

  /// Its state is on: muted, or a stream running.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colour = dimmed
        ? PrivioColors.textTertiary
        : highlighted
            ? PrivioColors.accentBright
            : PrivioColors.accent;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PrivioSpacing.md),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: PrivioColors.surfaceRaised,
            borderRadius: BorderRadius.circular(PrivioSpacing.md),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colour, size: 22),
              const SizedBox(height: PrivioSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colour, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dark rounded card every group on this screen sits in.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        // A Material rather than a decorated Container. A ListTile paints its
        // background and its ink splash on the nearest Material ancestor, so a
        // coloured DecoratedBox in between hides both — the row still works and
        // gives no feedback at all when it is tapped. Flutter asserts about it,
        // which is how this was found.
        color: PrivioColors.surfaceRaised,
        borderRadius: BorderRadius.circular(PrivioSpacing.md),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: PrivioSpacing.lg),
        child: Divider(height: 1, thickness: 1, color: PrivioColors.border),
      );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link, required this.onCopy, required this.onQr});

  final String link;
  final VoidCallback onCopy;
  final VoidCallback onQr;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(PrivioSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onCopy,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share link',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: PrivioColors.textSecondary),
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      link,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: PrivioColors.accent),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: onQr,
              icon: const Icon(Icons.qr_code_rounded, color: PrivioColors.accent),
              tooltip: 'QR code',
            ),
          ],
        ),
      );
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.tab, required this.onChanged});

  final _Tab tab;
  final ValueChanged<_Tab> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: PrivioColors.surfaceRaised,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in _Tab.values)
              GestureDetector(
                onTap: () => onChanged(option),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrivioSpacing.xl,
                    vertical: PrivioSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: option == tab ? PrivioColors.surfaceHigh : null,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    option == _Tab.media ? 'Media' : 'Links',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: option == tab
                              ? PrivioColors.textPrimary
                              : PrivioColors.textSecondary,
                        ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Pictures from the channel's posts, three across.
class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.channel, required this.posts});

  final ChannelInfo channel;
  final List<ChannelPost> posts;

  @override
  Widget build(BuildContext context) {
    final images = [
      for (final post in posts)
        if (post.attachment != null && (post.attachment!.mimeType).startsWith('image/'))
          post,
    ];
    if (images.isEmpty) {
      return const _Empty(
        icon: Icons.photo_library_outlined,
        message: 'No pictures yet',
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) =>
          _MediaTile(channelId: channel.id, post: images[index]),
    );
  }
}

/// One square in the grid.
///
/// A post carries its attachment's *size*, not its bytes — the file is sealed
/// on the server and has to be fetched and decrypted. So each tile opens its
/// own, once, and shows a placeholder until it has. A device with no key for
/// the post shows a padlock rather than an empty square, which is the same
/// thing the feed does.
class _MediaTile extends StatefulWidget {
  const _MediaTile({required this.channelId, required this.post});

  final String channelId;
  final ChannelPost post;

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  Uint8List? _opened;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  Future<void> _open() async {
    if (_tried || !widget.post.opened) return;
    _tried = true;
    final bytes =
        await PrivioScope.of(context).channels.openAttachment(widget.channelId, widget.post);
    if (mounted) setState(() => _opened = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _opened;
    if (bytes == null) {
      return Container(
        color: PrivioColors.surfaceRaised,
        child: Icon(
          widget.post.opened ? Icons.image_outlined : Icons.lock_outline_rounded,
          color: PrivioColors.textTertiary,
          size: 20,
        ),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _FullImage(bytes: bytes, name: widget.post.attachment?.name),
        ),
      ),
      child: Image.memory(bytes, fit: BoxFit.cover),
    );
  }
}

class _FullImage extends StatelessWidget {
  const _FullImage({required this.bytes, this.name});

  final Uint8List bytes;
  final String? name;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: const PrivioBackButton(),
          title: Text(name ?? 'Picture'),
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      );
}

/// Every link anybody posted, newest first, each one a way back to its post.
class _LinkList extends StatelessWidget {
  const _LinkList({required this.posts, required this.onOpen});

  final List<ChannelPost> posts;
  final void Function(ChannelPost) onOpen;

  /// Deliberately the same matcher the feed uses to make text tappable, so a
  /// link that is blue in a post is a link in this list too.
  static final RegExp _url = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final found = <({ChannelPost post, String url})>[];
    for (final post in posts) {
      if (!post.opened) continue;
      for (final match in _url.allMatches(post.body)) {
        found.add((post: post, url: match.group(0)!));
      }
    }
    if (found.isEmpty) {
      return const _Empty(icon: Icons.link_off_rounded, message: 'No links yet');
    }
    return _Card(
      children: [
        for (var i = 0; i < found.length; i++) ...[
          if (i > 0) const _Hairline(),
          ListTile(
            leading: const Icon(Icons.link_rounded, color: PrivioColors.accent),
            title: Text(
              found[i].url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PrivioColors.accent),
            ),
            subtitle: Text(
              found[i].post.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: () => onOpen(found[i].post),
          ),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.xxl),
        child: Column(
          children: [
            Icon(icon, size: 32, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: PrivioColors.textTertiary),
            ),
          ],
        ),
      );
}

/// How long to stay quiet for.
class _MuteSheet extends StatelessWidget {
  const _MuteSheet();

  static final Map<String, Duration?> options = {
    'For 1 hour': const Duration(hours: 1),
    'For 8 hours': const Duration(hours: 8),
    'For 2 days': const Duration(days: 2),
    'Until I turn it back on': null,
  };

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(PrivioSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mute this channel', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: PrivioSpacing.xs),
                  Text(
                    'It stays muted on every device you are signed in on — '
                    'muting it here is not "until I pick up my laptop".',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            for (final option in options.entries)
              ListTile(
                title: Text(option.key),
                onTap: () => Navigator.of(context).pop(
                  (
                    until: option.value == null ? null : DateTime.now().add(option.value!),
                    go: true,
                  ),
                ),
              ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      );
}
