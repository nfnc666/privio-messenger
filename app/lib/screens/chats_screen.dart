import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../services/channel_service.dart';
import '../theme/privio_colors.dart';
import '../widgets/chat_list_row.dart';
import '../widgets/search_field.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'new_group_screen.dart';

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
                child: chats.isEmpty
                    ? const _EmptyChats()
                    : RefreshIndicator(
                        color: PrivioColors.accent,
                        backgroundColor: PrivioColors.surface,
                        onRefresh: state.conversations.drain,
                        child: ListView.builder(
                          itemCount: chats.length,
                          itemBuilder: (context, index) {
                            final chat = chats[index];
                            return ChatListRow(
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
                          },
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
