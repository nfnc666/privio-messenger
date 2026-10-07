import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';
import 'channel_avatar.dart';
import 'verified_badge.dart';

/// Who this channel is, in one left-aligned row.
///
/// Shared by the settings screen and the detail pages under it so the four of
/// them open the same way — which is the point of it: a person moving between
/// them should never have to find their place again.
///
/// Deliberately *not* the big centred lock-up it replaces. That spent the first
/// third of a phone on a 96pt circle, a centred name and an audience count
/// before the first thing anybody came to do, and it is the single most
/// recognisable piece of the layout this redesign is getting away from.
class ChannelHeader extends StatelessWidget {
  const ChannelHeader({
    required this.channel,
    super.key,
    this.imageBytes,
    this.trailing,
    this.showDescription = true,
  });

  final ChannelInfo channel;
  final Uint8List? imageBytes;

  /// An action at the end of the row — the one thing this header does besides
  /// say who the channel is.
  final Widget? trailing;

  /// Whether the second line may be the description.
  ///
  /// False where the screen already shows it in full further down — the profile
  /// has a description card, and a header that repeated it would print the same
  /// sentence twice on one screen. A widget test caught exactly that.
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final description = showDescription ? channel.description?.trim() : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.lg,
        PrivioSpacing.md,
        PrivioSpacing.lg,
        PrivioSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ChannelAvatar(channel: channel, imageBytes: imageBytes, size: 56),
          const SizedBox(width: PrivioSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        channel.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (channel.verified) const VerifiedBadge(size: 16),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  // The description when there is one, the audience when there
                  // is not: one line either way, so the header is the same
                  // height on every channel and nothing below it moves.
                  (description?.isNotEmpty ?? false)
                      ? description!
                      : channel.subscriberLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: PrivioColors.textSecondary),
                ),
                // One second line, never two. The audience had a third line
                // here and it collided with the Team section's own summary —
                // the same count twice on one screen, which a test caught.
                // Whoever wants the number has a row that is about it.
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: PrivioSpacing.sm),
            trailing!,
          ] else if (channel.isPublic && (channel.handle?.isNotEmpty ?? false)) ...[
            const SizedBox(width: PrivioSpacing.sm),
            Semantics(
              label: text.channelPublic,
              child: const Icon(
                Icons.public_rounded,
                size: 18,
                color: PrivioColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
