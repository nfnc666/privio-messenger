import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../theme/privio_colors.dart';
import 'voice_bubble.dart';

/// One message in a conversation.
///
/// Incoming bubbles sit on `surfaceRaised`, outgoing on `accentDim`, both with a
/// squared corner on the tail side — the shape from the mockups.
class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, super.key});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.isMine;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.76,
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.gutter,
          vertical: PrivioSpacing.xs,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.md,
          vertical: PrivioSpacing.sm + 1,
        ),
        decoration: BoxDecoration(
          color: mine ? PrivioColors.bubbleOutgoing : PrivioColors.surfaceRaised,
          borderRadius: BorderRadius.only(
            topLeft: PrivioRadius.bubble,
            topRight: PrivioRadius.bubble,
            bottomLeft: mine ? PrivioRadius.bubble : const Radius.circular(4),
            bottomRight: mine ? const Radius.circular(4) : PrivioRadius.bubble,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.senderName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderName!,
                  style: theme.textTheme.labelMedium?.copyWith(color: PrivioColors.accentBright),
                ),
              ),
            if (message.isVoice)
              // A voice message renders itself: the waveform and the duration
              // come out of the sealed payload, so it is complete before the
              // audio has been fetched.
              VoiceBubble(message: message, mine: mine)
            else ...[
              if (message.attachment != null) ...[
                _AttachmentView(attachment: message.attachment!),
                if (message.body.isNotEmpty) const SizedBox(height: PrivioSpacing.sm),
              ],
              if (message.body.isNotEmpty)
                Text(message.body, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _formatTime(message.sentAt),
                  style: theme.textTheme.labelSmall,
                ),
                if (message.expiresAt != null) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.timer_outlined,
                    size: 12,
                    color: PrivioColors.textTertiary,
                  ),
                ],
                if (mine) ...[
                  const SizedBox(width: 4),
                  _DeliveryTicks(state: message.state),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Renders an attachment: images inline once decrypted, everything else as a
/// file row. Nothing is fetched until the bubble is on screen, and nothing is
/// ever written to disk in the clear.
class _AttachmentView extends StatelessWidget {
  const _AttachmentView({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final controller = PrivioScope.of(context).conversations;

    return FutureBuilder<Uint8List?>(
      future: controller.attachmentBytes(attachment),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AttachmentPlaceholder(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return _FileRow(attachment: attachment, failed: true);
        }
        if (!attachment.isImage) {
          return _FileRow(attachment: attachment);
        }
        return ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            // A file that claims to be an image but is not must not take the
            // bubble down with it.
            errorBuilder: (_, __, ___) => _FileRow(attachment: attachment, failed: true),
          ),
        );
      },
    );
  }
}

class _AttachmentPlaceholder extends StatelessWidget {
  const _AttachmentPlaceholder({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: 180,
        height: 120,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: PrivioColors.surfaceHigh,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: child,
      );
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.attachment, this.failed = false});

  final Attachment attachment;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: PrivioColors.surfaceHigh,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: Icon(
            failed
                ? Icons.error_outline_rounded
                : attachment.isVideo
                    ? Icons.videocam_outlined
                    : Icons.insert_drive_file_outlined,
            size: 20,
            color: failed ? PrivioColors.danger : PrivioColors.textSecondary,
          ),
        ),
        const SizedBox(width: PrivioSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                attachment.fileName ?? 'File',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                failed ? 'Could not open' : attachment.readableSize,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: failed ? PrivioColors.danger : PrivioColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sent is a single grey tick, delivered two, read two in accent green.
class _DeliveryTicks extends StatelessWidget {
  const _DeliveryTicks({required this.state});

  final DeliveryState state;

  @override
  Widget build(BuildContext context) {
    // Queued and failed are their own marks. A message waiting for a network
    // must not look like one that is on its way, and one that gave up must not
    // look like either.
    if (state == DeliveryState.queued) {
      return const Icon(Icons.cloud_off_rounded, size: 13, color: PrivioColors.textTertiary);
    }
    if (state == DeliveryState.failed) {
      return const Icon(Icons.error_outline_rounded, size: 14, color: PrivioColors.danger);
    }
    if (state == DeliveryState.sending) {
      return const Icon(Icons.schedule_rounded, size: 13, color: PrivioColors.textTertiary);
    }
    final read = state == DeliveryState.read;
    return Icon(
      state == DeliveryState.sent ? Icons.check_rounded : Icons.done_all_rounded,
      size: 15,
      color: read ? PrivioColors.accentBright : PrivioColors.textTertiary,
    );
  }
}

class EncryptionNotice extends StatelessWidget {
  const EncryptionNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(PrivioSpacing.lg),
      padding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.md,
        vertical: PrivioSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: PrivioColors.accentSurface,
        borderRadius: BorderRadius.all(PrivioRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_rounded, size: 15, color: PrivioColors.accent),
          const SizedBox(width: PrivioSpacing.sm),
          Expanded(
            child: Text(
              'Messages and calls are end-to-end encrypted. No one outside this '
              'chat can read or listen to them, not even Privio.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
