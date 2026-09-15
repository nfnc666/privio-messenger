import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// The blue mark beside the official Privio channel's name.
///
/// Blue rather than the accent colour, and that is not an oversight: the accent
/// is the *user's* choice and changes per account, so a badge drawn in it would
/// be a different colour on every phone and would mean nothing consistent. This
/// mark says something the user did not decide, so it does not take a colour
/// they did.
///
/// It is drawn only where [ChannelInfo.verified] is true, which the server sets
/// by comparing channel ids. Nothing on this side can turn it on.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16});

  final double size;

  /// The one blue. Kept here rather than in the theme because it must not be
  /// themeable: a verification mark whose colour a deployment could change is a
  /// verification mark somebody can make look like something else.
  static const Color blue = Color(0xFF3B9EFF);

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: size * 0.25),
        child: Tooltip(
          message: AppText.of(context).channelVerifiedTooltip,
          child: Icon(Icons.verified_rounded, size: size, color: blue),
        ),
      );
}

/// A channel's name with the badge after it, when it has one.
///
/// A widget rather than four copies of the same `Row`, because "the badge goes
/// directly after the name" has to be true in the list, the header, the profile
/// and search results alike — and four copies is four places for it to end up
/// somewhere else.
class ChannelName extends StatelessWidget {
  const ChannelName({
    required this.name,
    required this.verified,
    super.key,
    this.style,
    this.badgeSize = 16,
    this.maxLines = 1,
  });

  final String name;
  final bool verified;
  final TextStyle? style;
  final double badgeSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
    if (!verified) return text;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible, so a long name shortens and the badge stays visible. A
        // badge pushed off the edge by a name is a badge that is not there.
        Flexible(child: text),
        VerifiedBadge(size: badgeSize),
      ],
    );
  }
}
