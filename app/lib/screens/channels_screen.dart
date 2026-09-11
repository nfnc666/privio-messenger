import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../theme/privio_colors.dart';
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
        SnackBar(content: Text(controller.error ?? 'Could not open that link')),
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

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Channels'),
            actions: [
              IconButton(
                onPressed: _joinByLink,
                icon: const Icon(Icons.link_rounded),
                tooltip: 'Join with a link',
              ),
              IconButton(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                tooltip: 'New channel',
              ),
              const SizedBox(width: PrivioSpacing.xs),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabs: const [Tab(text: 'Following'), Tab(text: 'Discover')],
            ),
          ),
          body: Column(
            children: [
              PrivioSearchField(
                controller: _search,
                hintText: _tabs.index == 0 ? 'Search your channels' : 'Search public channels',
                onChanged: (value) {
                  setState(() => _query = value);
                  if (_tabs.index == 1) controller.search(query: value);
                },
              ),
              if (controller.error != null) _ErrorBanner(message: controller.error!),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _ChannelList(
                      channels: _filterMine(controller.mine),
                      onRefresh: controller.refresh,
                      onTap: _open,
                      empty: const _Empty(
                        icon: Icons.campaign_outlined,
                        title: 'No channels yet',
                        body: 'Create one, or find a public channel under Discover.',
                      ),
                    ),
                    _ChannelList(
                      channels: controller.discovered,
                      onRefresh: () => controller.search(query: _query),
                      onTap: _open,
                      empty: const _Empty(
                        icon: Icons.search_rounded,
                        title: 'Nothing found',
                        body: 'Search public channels by name, handle or description. '
                            'Private channels never appear here.',
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
  });

  final List<ChannelInfo> channels;
  final Future<void> Function() onRefresh;
  final void Function(ChannelInfo) onTap;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return empty;
    return RefreshIndicator(
      color: PrivioColors.accent,
      backgroundColor: PrivioColors.surface,
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: channels.length,
        itemBuilder: (context, index) => ChannelListRow(
          channel: channels[index],
          onTap: () => onTap(channels[index]),
        ),
      ),
    );
  }
}

/// One channel in a list: what it is, how many are in it, and whether this
/// device can actually read it.
class ChannelListRow extends StatelessWidget {
  const ChannelListRow({required this.channel, required this.onTap, super.key});

  final ChannelInfo channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = channel.handle != null
        ? '@${channel.handle}  ·  ${channel.memberLabel}'
        : channel.memberLabel;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.gutter,
        vertical: PrivioSpacing.xs,
      ),
      leading: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: PrivioColors.accentSurface,
          borderRadius: BorderRadius.all(PrivioRadius.card),
        ),
        child: Icon(
          channel.isPublic ? Icons.campaign_rounded : Icons.lock_rounded,
          color: PrivioColors.accentBright,
          size: 22,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              channel.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (!channel.hasKey) ...[
            const SizedBox(width: PrivioSpacing.sm),
            const Icon(Icons.key_off_rounded, size: 14, color: PrivioColors.warning),
          ],
        ],
      ),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: channel.isMember
          ? null
          : const Icon(Icons.add_circle_outline_rounded, color: PrivioColors.accent, size: 20),
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
      title: const Text('Join a channel'),
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
            'Paste a channel link. It shows you the channel; joining is a '
            'button there. Joining does not hand you the key either — a member '
            'who has it sends it to your device, encrypted, right after.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_link.text),
          child: const Text('Join'),
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
