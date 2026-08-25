import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/privio_colors.dart';

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
            if (message.kind == MessageKind.voice)
              _VoiceNote(duration: message.voiceDuration ?? Duration.zero, mine: mine)
            else
              Text(message.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _formatTime(message.sentAt),
                  style: theme.textTheme.labelSmall,
                ),
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

/// Sent is a single grey tick, delivered two, read two in accent green.
class _DeliveryTicks extends StatelessWidget {
  const _DeliveryTicks({required this.state});

  final DeliveryState state;

  @override
  Widget build(BuildContext context) {
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

class _VoiceNote extends StatelessWidget {
  const _VoiceNote({required this.duration, required this.mine});

  final Duration duration;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final seconds = duration.inSeconds;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: PrivioColors.accent,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow_rounded, size: 20, color: PrivioColors.background),
        ),
        const SizedBox(width: PrivioSpacing.sm),
        const _Waveform(),
        const SizedBox(width: PrivioSpacing.sm),
        Text(
          '0:${seconds.toString().padLeft(2, '0')}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform();

  // A fixed silhouette: real amplitudes arrive with the decrypted audio.
  static const List<double> _bars = [
    6, 12, 9, 16, 22, 14, 8, 18, 24, 12, 7, 15, 20, 10, 6, 13,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final height in _bars)
          Container(
            width: 2.5,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: const BoxDecoration(
              color: PrivioColors.accentBright,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
      ],
    );
  }
}

/// The "messages are end-to-end encrypted" notice above the first message.
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
