import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/verified_badge.dart';
import '../widgets/channel_avatar.dart';
import '../widgets/search_field.dart';
import 'channel_feed_screen.dart';
import 'new_channel_screen.dart';

/// The Channels tab: what you follow, and what there is to find.
///
/// Discovery searches public channels on the server, which is the one place in
/// Privio where a query leaves the device — it has to, because the server holds
/// the only index of public channels. Everything on the "Following" tab is
/// filtered locally.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PrivioScope.of(context).channels.refresh();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(ChannelInfo channel) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChannelFeedScreen(channel: channel)),
    );
    if (mounted) await PrivioScope.of(context).channels.refresh();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<ChannelInfo>(
      MaterialPageRoute<ChannelInfo>(builder: (_) => const NewChannelScreen()),
    );
    if (created != null && mounted) await _open(created);
  }

  /// A link is the only way into a private channel. It carries no key — that
  /// arrives afterwards from a member who already has one.
  ///
  /// Opening one shows the channel; it does not join it. Tapping a link out of
  /// curiosity should not put somebody's name in a stranger's member list.
  Future<void> _joinByLink() async {
    final controller = PrivioScope.of(context).channels;
    final link = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinByLinkDialog(),
    );
    if (link == null || link.isEmpty || !mounted) return;

    final channel = await controller.openInvite(link);
    if (!mounted) return;
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            controller.failure?.words(AppText.of(context)) ?? AppText.of(context).channelsCouldNotOpenLink,
          ),
        ),
      );
      return;
    }
    await _open(channel);
  }

  List<ChannelInfo> _filterMine(List<ChannelInfo> channels) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return channels;
    return [
      for (final channel in channels)
        if (channel.title.toLowerCase().contains(query) ||
            (channel.handle ?? '').toLowerCase().contains(query))
          channel,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final controller = state.channels;
    final text = AppText.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(text.navChannels),
            actions: [
              IconButton(
                onPressed: _joinByLink,
                icon: const Icon(Icons.link_rounded),
                tooltip: text.channelsJoinWithLink,
              ),
              IconButton(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                tooltip: text.channelsNewChannel,
              ),
              const SizedBox(width: PrivioSpacing.xs),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: text.channelsTabFollowing),
                Tab(text: text.channelsTabDiscover),
              ],
            ),
          ),
          body: Column(
            children: [
              PrivioSearchField(
                controller: _search,
                hintText: _tabs.index == 0
                    ? text.channelsSearchMine
                    : text.channelsSearchPublic,
                onChanged: (value) {
                  setState(() => _query = value);
                  if (_tabs.index == 1) controller.search(query: value);
                },
              ),
              if (controller.failure != null) _ErrorBanner(message: controller.failure!.words(text)),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _ChannelList(
                      channels: _filterMine(controller.mine),
                      onRefresh: controller.refresh,
                      onTap: _open,
                      pictureOf: controller.avatarFor,
                      empty: _Empty(
                        icon: Icons.campaign_outlined,
                        title: text.channelsEmptyTitle,
                        body: text.channelsEmptyBody,
                      ),
                    ),
                    _ChannelList(
                      channels: controller.discovered,
                      onRefresh: () => controller.search(query: _query),
                      onTap: _open,
                      pictureOf: controller.avatarFor,
                      empty: _Empty(
                        icon: Icons.search_rounded,
                        title: text.channelsNothingFound,
                        body: text.channelsDiscoverEmptyBody,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChannelList extends StatelessWidget {
  const _ChannelList({
    required this.channels,
    required this.onRefresh,
    required this.onTap,
    required this.empty,
    required this.pictureOf,
  });

  final List<ChannelInfo> channels;
  final Future<void> Function() onRefresh;
  final void Function(ChannelInfo) onTap;
  final Widget empty;

  /// Looked up per row rather than passed in as a map, so a picture that
  /// arrives after the list is built shows up on the next notify without the
  /// list having to be rebuilt from the controller's side.
  final Uint8List? Function(ChannelInfo) pictureOf;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return empty;
    return RefreshIndicator(
      color: context.accents.accent,
      backgroundColor: PrivioColors.surface,
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: channels.length,
        itemBuilder: (context, index) => ChannelListRow(
          channel: channels[index],
          imageBytes: pictureOf(channels[index]),
          onTap: () => onTap(channels[index]),
        ),
      ),
    );
  }
}

/// One channel in a list: what it is, how many are in it, and whether this
/// device can actually read it.
class ChannelListRow extends StatelessWidget {
  const ChannelListRow({
    required this.channel,
    required this.onTap,
    super.key,
    this.imageBytes,
  });

  final ChannelInfo channel;
  final VoidCallback onTap;

  /// The channel's picture, once it has been fetched. Null draws the mark.
  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final members = text.channelMembers(channel.memberCount);
    final subtitle = channel.handle != null
        ? text.channelsHandleAndMembers(channel.handle!, members)
        : members;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.gutter,
        vertical: PrivioSpacing.xs,
      ),
      leading: ChannelAvatar(channel: channel, imageBytes: imageBytes),
      title: Row(
        children: [
          Flexible(
            child: ChannelName(
              name: channel.title,
              verified: channel.verified,
              style: theme.textTheme.titleSmall,
              badgeSize: 15,
            ),
          ),
          if (!channel.hasKey) ...[
            const SizedBox(width: PrivioSpacing.sm),
            const Icon(Icons.key_off_rounded, size: 14, color: PrivioColors.warning),
          ],
          if (channel.muted) ...[
            const SizedBox(width: PrivioSpacing.xs),
            const Icon(
              Icons.notifications_off_rounded,
              size: 13,
              color: PrivioColors.textTertiary,
            ),
          ],
        ],
      ),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: !channel.isMember
          ? Icon(Icons.add_circle_outline_rounded, color: context.accents.accent, size: 20)
          // A muted channel still counts what it has, and still shows it — it
          // just does not buzz. The badge goes grey rather than away: "there is
          // something here" and "tell me about it" are different questions.
          : channel.hasUnread
              ? _UnreadBadge(label: channel.unreadLabel, muted: channel.muted)
              : null,
    );
  }
}

class _JoinByLinkDialog extends StatefulWidget {
  const _JoinByLinkDialog();

  @override
  State<_JoinByLinkDialog> createState() => _JoinByLinkDialogState();
}

class _JoinByLinkDialogState extends State<_JoinByLinkDialog> {
  final TextEditingController _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: Text(AppText.of(context).channelsJoinTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _link,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'https://${ChannelService.channelLinkHost}/…',
            ),
          ),
          const SizedBox(height: PrivioSpacing.md),
          Text(
            AppText.of(context).channelsJoinNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppText.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_link.text),
          child: Text(AppText.of(context).chatsJoin),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
      padding: const EdgeInsets.all(PrivioSpacing.md),
      decoration: BoxDecoration(
        color: PrivioColors.danger.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(PrivioRadius.card),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

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
            const SizedBox(height: PrivioSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.xs),
            Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// How many posts have arrived since this account last read the channel.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.label, required this.muted});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: muted ? PrivioColors.surfaceHigh : context.accents.accent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: muted ? PrivioColors.textSecondary : Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
