import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/models.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/message_bubble.dart';

/// Screen 6: one conversation.
class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.chat, super.key});

  final ChatSummary chat;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late List<Message> _messages = DemoData.conversation(widget.chat.id);

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Appends locally and optimistically. The real send seals one copy per
  /// recipient device and only then flips the state to `sent`.
  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages = [
        ..._messages,
        Message(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          body: text,
          sentAt: DateTime.now(),
          isMine: true,
          state: DeliveryState.sending,
        ),
      ];
      _composer.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            PrivioAvatar(
              label: widget.chat.title,
              size: 34,
              seed: widget.chat.avatarSeed,
              isGroup: widget.chat.isGroup,
            ),
            const SizedBox(width: PrivioSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.chat.title, style: theme.textTheme.titleMedium),
                Text(
                  widget.chat.presence == Presence.online ? 'Online' : 'Last seen recently',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: widget.chat.presence == Presence.online
                        ? PrivioColors.accent
                        : PrivioColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.call_outlined), tooltip: 'Voice call'),
          IconButton(onPressed: () {}, icon: const Icon(Icons.videocam_outlined), tooltip: 'Video call'),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert_rounded), tooltip: 'Chat options'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: PrivioSpacing.md),
              itemCount: _messages.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return const EncryptionNotice();
                return MessageBubble(message: _messages[index - 1]);
              },
            ),
          ),
          _Composer(controller: _composer, onSend: _send),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.md,
          PrivioSpacing.sm,
          PrivioSpacing.md,
          PrivioSpacing.sm,
        ),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PrivioColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded, color: PrivioColors.textSecondary),
              tooltip: 'Attach',
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return IconButton.filled(
                  onPressed: hasText ? onSend : () {},
                  style: IconButton.styleFrom(
                    backgroundColor: hasText ? PrivioColors.accent : PrivioColors.surfaceRaised,
                    foregroundColor: hasText ? PrivioColors.background : PrivioColors.textSecondary,
                  ),
                  icon: Icon(hasText ? Icons.send_rounded : Icons.mic_rounded, size: 20),
                  tooltip: hasText ? 'Send' : 'Hold to record',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
