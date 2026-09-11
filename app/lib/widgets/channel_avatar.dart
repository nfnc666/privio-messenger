import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../theme/privio_colors.dart';

/// A channel's picture, or the mark that stands in for one.
///
/// The fallback is not a monogram like a person's. A channel is recognised by
/// whether it is open or closed as much as by its name, so the placeholder is
/// the same megaphone-or-padlock the lists have always drawn — a channel with
/// no picture looks exactly as it did, rather than looking like a contact.
///
/// The rounded square is deliberate too, and it is the one thing here that is
/// not cosmetic: a circle is a person in this app. A channel that drew one
/// would read as somebody messaging you.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({
    required this.channel,
    super.key,
    this.imageBytes,
    this.size = 48,
  });

  final ChannelInfo channel;

  /// The opened picture. Null while it is being fetched, when the channel has
  /// none, and — for a private channel whose metadata this device cannot open
  /// yet — when there is one it has no way to.
  final Uint8List? imageBytes;

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size >= 64
        ? BorderRadius.circular(size * 0.28)
        : const BorderRadius.all(PrivioRadius.card);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PrivioColors.accentSurface,
        borderRadius: radius,
      ),
      child: imageBytes == null
          ? _Mark(channel: channel, size: size)
          : Image.memory(
              imageBytes!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // A picture that will not decode falls back to the mark rather
              // than a broken box — the same rule a contact's picture follows.
              errorBuilder: (_, __, ___) => _Mark(channel: channel, size: size),
            ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.channel, required this.size});

  final ChannelInfo channel;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(
        channel.isPublic ? Icons.campaign_rounded : Icons.lock_rounded,
        color: PrivioColors.accentBright,
        size: size * 0.46,
      );
}
