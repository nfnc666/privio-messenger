import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/models.dart';
import '../theme/privio_colors.dart';
import '../widgets/chat_list_row.dart';
import '../widgets/search_field.dart';
import 'chat_screen.dart';

/// Screen 5: the home list.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  static const List<String> _filters = ['All', 'Unread', 'Groups'];

  int _filter = 0;
  String _query = '';

  /// Filtering and search both run on already-decrypted local data.
  List<ChatSummary> get _visibleChats {
    final query = _query.trim().toLowerCase();
    return DemoData.chats.where((chat) {
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

  @override
  Widget build(BuildContext context) {
    final chats = _visibleChats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privio'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Scan invite code',
          ),
          IconButton(
            onPressed: () {},
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
                : ListView.builder(
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      return ChatListRow(
                        chat: chat,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChatScreen(chat: chat),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded, size: 40, color: PrivioColors.textTertiary),
          const SizedBox(height: PrivioSpacing.md),
          Text('No chats yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: PrivioSpacing.xs),
          Text(
            'Add a contact by username to start talking.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
