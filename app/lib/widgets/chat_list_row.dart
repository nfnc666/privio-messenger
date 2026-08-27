import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/privio_colors.dart';
import 'avatar.dart';

/// A row in the Chats list: avatar, name, preview, timestamp, unread pill.
class ChatListRow extends StatelessWidget {
  const ChatListRow({required this.chat, super.key, this.onTap});

  final ChatSummary chat;
  final VoidCallback? onTap;

  static const Map<MessageKind, IconData> _previewIcons = {
    MessageKind.voice: Icons.mic_rounded,
    MessageKind.photo: Icons.photo_outlined,
    MessageKind.video: Icons.videocam_outlined,
    MessageKind.file: Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _previewIcons[chat.previewKind];
    final hasUnread = chat.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.gutter,
          vertical: PrivioSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PrivioAvatar(
              label: chat.title,
              seed: chat.avatarSeed,
              presence: chat.presence,
              isGroup: chat.isGroup,
              imageBytes: chat.avatarBytes,
            ),
            const SizedBox(width: PrivioSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (chat.pinned) ...[
                        const Icon(Icons.push_pin_rounded, size: 13, color: PrivioColors.textTertiary),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (icon != null && !chat.typing) ...[
                        Icon(icon, size: 14, color: PrivioColors.textSecondary),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          chat.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: chat.typing
                              ? theme.textTheme.bodySmall?.copyWith(
                                  color: PrivioColors.accent,
                                )
                              : theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  chat.timestamp,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hasUnread ? PrivioColors.accent : PrivioColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 6),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: const BoxDecoration(
                      color: PrivioColors.accent,
                      borderRadius: BorderRadius.all(PrivioRadius.pill),
                    ),
                    child: Text(
                      '${chat.unreadCount}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: PrivioColors.background,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 17),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
