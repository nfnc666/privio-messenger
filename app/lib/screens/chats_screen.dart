import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/message_search.dart';
import '../models/models.dart';
import '../services/channel_service.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/chat_list_row.dart';
import '../widgets/search_field.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'new_group_screen.dart';

/// What a search turns the list into: the chats whose name or last line
/// matched, and then everything that was ever said matching it.
///
/// The search field used to filter the list of chats and nothing else, which
/// made it a search that could not find a message — the one thing anybody
/// opens a search box in a messenger to do.
class _Results extends StatelessWidget {
  const _Results({
    required this.chats,
    required this.hits,
    required this.rowBuilder,
    required this.onOpenHit,
  });

  final List<ChatSummary> chats;
  final List<SearchHit> hits;
  final Widget Function(ChatSummary) rowBuilder;
  final void Function(SearchHit) onOpenHit;

  @override
  Widget build(BuildContext context) {
    if (chats.isEmpty && hits.isEmpty) return const _NoResults();

    return ListView.builder(
      itemCount: (chats.isEmpty ? 0 : chats.length + 1) +
          (hits.isEmpty ? 0 : hits.length + 1),
      itemBuilder: (context, index) {
        var at = index;
        if (chats.isNotEmpty) {
          if (at == 0) return const _SectionHeader('Chats');
          at -= 1;
          if (at < chats.length) return rowBuilder(chats[at]);
          at -= chats.length;
        }
        if (at == 0) return const _SectionHeader('Messages');
        final hit = hits[at - 1];
        return _HitRow(hit: hit, onTap: () => onOpenHit(hit));
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.gutter,
          PrivioSpacing.md,
          PrivioSpacing.gutter,
          PrivioSpacing.sm,
        ),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PrivioColors.textTertiary,
                letterSpacing: 1.1,
              ),
        ),
      );
}

/// One matching message: who and when, and the part of it that matched.
class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snippet = MessageSearch.snippet(hit);
    final body = theme.textTheme.bodySmall ?? const TextStyle();

    return ListTile(
      onTap: onTap,
      leading: PrivioAvatar(
        label: hit.title,
        seed: hit.conversationId.hashCode.abs(),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              hit.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Text(
            _when(hit.message.sentAt),
            style: theme.textTheme.labelSmall?.copyWith(color: PrivioColors.textTertiary),
          ),
        ],
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            if (hit.message.isMine)
              TextSpan(
                text: 'You: ',
                style: body.copyWith(color: PrivioColors.textTertiary),
              ),
            TextSpan(text: snippet.text.substring(0, snippet.start), style: body),
            // The match itself, so the eye lands on the word that was typed
            // rather than on the middle of a paragraph.
            TextSpan(
              text: snippet.text.substring(snippet.start, snippet.end),
              style: body.copyWith(
                color: PrivioColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: snippet.text.substring(snippet.end), style: body),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static String _when(DateTime at) {
    final now = DateTime.now();
    if (at.year == now.year && at.month == now.month && at.day == now.day) {
      return '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
    }
    return '${at.day.toString().padLeft(2, '0')}.'
        '${at.month.toString().padLeft(2, '0')}.${at.year}';
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(PrivioSpacing.xxl),
          child: Text(
            'Nothing here matches. Only this device was asked — the server '
            'holds messages it cannot read, so it could not have answered.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: PrivioColors.textTertiary),
          ),
        ),
      );
}

/// The home list, built from the conversations this device has decrypted.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  static const List<String> _filters = ['All', 'Unread', 'Groups'];

  int _filter = 0;
  String _query = '';

  /// Filtering and search both run on already-decrypted local data — no query
  /// ever reaches the server.
  List<ChatSummary> _visible(List<ChatSummary> chats) {
    final query = _query.trim().toLowerCase();
    return chats.where((chat) {
      final matchesFilter = switch (_filter) {
        1 => chat.unreadCount > 0,
        2 => chat.isGroup,
        _ => true,
      };
      final matchesQuery = query.isEmpty ||
          chat.title.toLowerCase().contains(query) ||
          chat.preview.toLowerCase().contains(query);
      return matchesFilter && matchesQuery;
    }).toList();
  }

  Widget _row(BuildContext context, AppState state, ChatSummary chat) => ChatListRow(
        chat: chat,
        onTap: () {
          state.conversations.markRead(chat.id);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatScreen(
                accountId: chat.id,
                title: chat.title,
                isGroup: chat.isGroup,
              ),
            ),
          );
        },
      );

  void _openHit(BuildContext context, AppState state, SearchHit hit) {
    state.conversations.markRead(hit.conversationId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          accountId: hit.conversationId,
          title: hit.title,
          isGroup: hit.isGroup,
          jumpTo: hit.message.clientId,
        ),
      ),
    );
  }

  /// Creating a group drops straight into it, which is what someone who just
  /// named a group and picked its members expects to happen.
  Future<void> _startGroup(BuildContext context, AppState state) async {
    final groupId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const NewGroupScreen()),
    );
    if (groupId == null || !context.mounted) return;

    final title = state.conversations.groupInfo(groupId)?.name ?? 'Group';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(accountId: groupId, title: title, isGroup: true),
      ),
    );
  }

  /// Opens a group join link. The link carries no key; the group's name stays
  /// sealed until a member's device sends the key over.
  Future<void> _joinByLink(BuildContext context, AppState state) async {
    final link = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinGroupDialog(),
    );
    if (link == null || link.isEmpty || !context.mounted) return;

    final groupId = await state.conversations.joinGroupByLink(link);
    if (!context.mounted) return;
    if (groupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.conversations.error ?? 'Could not open that link')),
      );
      return;
    }
    final title = state.conversations.groupInfo(groupId)?.name ?? 'Group';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(accountId: groupId, title: title, isGroup: true),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PrivioScope.of(context).conversations.refreshGroups(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final chats = _visible(state.conversations.chats);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Privio'),
            actions: [
              IconButton(
                onPressed: () => state.conversations.drain(),
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Check for messages',
              ),
              IconButton(
                onPressed: () => _joinByLink(context, state),
                icon: const Icon(Icons.link_rounded),
                tooltip: 'Join a group with a link',
              ),
              IconButton(
                onPressed: () => _startGroup(context, state),
                icon: const Icon(Icons.group_add_outlined),
                tooltip: 'New group',
              ),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ContactsScreen()),
                ),
                icon: const Icon(Icons.edit_square),
                tooltip: 'New chat',
              ),
              const SizedBox(width: PrivioSpacing.xs),
            ],
          ),
          body: Column(
            children: [
              PrivioSearchField(
                hintText: 'Search',
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: PrivioSpacing.xs),
              FilterChips(
                labels: _filters,
                selectedIndex: _filter,
                onSelected: (index) => setState(() => _filter = index),
              ),
              const SizedBox(height: PrivioSpacing.sm),
              Expanded(
                child: _query.trim().isEmpty
                    ? (chats.isEmpty
                        ? const _EmptyChats()
                        : RefreshIndicator(
                            color: PrivioColors.accent,
                            backgroundColor: PrivioColors.surface,
                            onRefresh: state.conversations.drain,
                            child: ListView.builder(
                              itemCount: chats.length,
                              itemBuilder: (context, index) =>
                                  _row(context, state, chats[index]),
                            ),
                          ))
                    : _Results(
                        chats: chats,
                        hits: state.conversations.searchMessages(_query),
                        rowBuilder: (chat) => _row(context, state, chat),
                        onOpenHit: (hit) => _openHit(context, state, hit),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text('No chats yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.xs),
            Text(
              'Add someone by their exact username to start talking.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ContactsScreen()),
              ),
              child: const Text('Add a contact'),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinGroupDialog extends StatefulWidget {
  const _JoinGroupDialog();

  @override
  State<_JoinGroupDialog> createState() => _JoinGroupDialogState();
}

class _JoinGroupDialogState extends State<_JoinGroupDialog> {
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
      title: const Text('Join a group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _link,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'https://${ChannelService.groupLinkHost}/g/…',
            ),
          ),
          const SizedBox(height: PrivioSpacing.md),
          Text(
            'The link gets you in. The key to the group name is sent to your '
            'device afterwards, encrypted, by someone already in the group.',
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
