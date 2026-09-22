import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// One of the square actions across the top of a profile.
///
/// It lived as a private widget inside `channel_profile_screen.dart` and is
/// shared now that a person has a profile screen too. Same widget rather than
/// a second copy of the same forty lines: the two screens are meant to look
/// like the same app, and the way that stops being true is one of them being
/// adjusted and the other not.
class ProfileActionButton extends StatelessWidget {
  const ProfileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
    this.dimmed = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The action exists but cannot do anything here — it still opens, and what
  /// it opens says why.
  final bool dimmed;

  /// Its state is on: muted, blocked, a stream running.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colour = dimmed
        ? PrivioColors.textTertiary
        : highlighted
            ? context.accents.bright
            : context.accents.accent;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PrivioSpacing.md),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: PrivioColors.surfaceRaised,
            borderRadius: BorderRadius.circular(PrivioSpacing.md),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colour, size: 22),
              const SizedBox(height: PrivioSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colour, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
