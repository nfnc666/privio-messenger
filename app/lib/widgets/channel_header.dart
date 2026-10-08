import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/channel.dart';
import '../theme/accent.dart';
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
    this.card = false,
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

  /// Drawn on its own raised card, for the settings screen where it heads a
  /// page of cards. Elsewhere it sits on the background.
  final bool card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final description = showDescription ? channel.description?.trim() : null;

    final row = Row(
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                //
                // The audience through the translations. It was the model's
                // own English "1 subscriber", which a German phone showed as
                // exactly that.
                (description?.isNotEmpty ?? false)
                    ? description!
                    : text.channelSubscribers(channel.memberCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textSecondary),
              ),
              // One second line, never two. The audience had a third line
              // here and it collided with the Team section's own summary —
              // the same count twice on one screen, which a test caught.
              // Whoever wants the number has a row that is about it.
              const SizedBox(height: PrivioSpacing.sm),
              trailing == null ? _VisibilityPill(public: channel.isPublic) : trailing!,
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: card
          ? const EdgeInsets.fromLTRB(
              PrivioSpacing.gutter,
              PrivioSpacing.sm,
              PrivioSpacing.gutter,
              0,
            )
          : const EdgeInsets.fromLTRB(
              PrivioSpacing.lg,
              PrivioSpacing.md,
              PrivioSpacing.lg,
              PrivioSpacing.lg,
            ),
      child: card
          ? Container(
              padding: const EdgeInsets.all(PrivioSpacing.lg),
              decoration: BoxDecoration(
                color: PrivioColors.surface,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                border: Border.all(color: PrivioColors.border),
              ),
              child: row,
            )
          : row,
    );
  }
}

/// Public or private, said in words with an icon — not a grey globe that only
/// meant something to whoever already knew what it meant.
class _VisibilityPill extends StatelessWidget {
  const _VisibilityPill({required this.public});

  final bool public;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final accents = context.accents;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accents.surface,
        borderRadius: const BorderRadius.all(PrivioRadius.pill),
        border: Border.all(color: accents.dim),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            public ? Icons.public_rounded : Icons.lock_outline_rounded,
            size: 14,
            color: accents.bright,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              public ? text.channelPublic : text.channelPrivate,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: accents.bright,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
