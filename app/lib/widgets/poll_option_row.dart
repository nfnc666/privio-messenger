import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// One answer of a poll: a tick, the words, and — once results show — a bar
/// and a count.
///
/// Shared by channel polls and bot polls, so the two are answered the same way
/// and look like the same kind of thing. What differs between them is who can
/// read the question and who sees the tally, and each card says that itself.
class PollOptionRow extends StatelessWidget {
  const PollOptionRow({
    super.key,
    required this.label,
    required this.count,
    required this.share,
    required this.chosen,
    required this.showResults,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final int count;

  /// Against the busiest option, not the total: in a poll that takes several
  /// answers the totals add up to more than the people.
  final double share;
  final bool chosen;
  final bool showResults;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.xs),
      // Said, not only drawn: a screen reader hears which answer is picked and,
      // once results show, how many chose it — the tick and the bar are
      // otherwise the only places either is written down.
      child: Semantics(
        button: enabled,
        selected: chosen,
        label: showResults ? '$label, $count' : label,
        // The tap has to be here as well: excluding the children's semantics
        // takes the InkWell's action with it, and an answer a screen reader
        // can hear but not choose is not an answer.
        onTap: enabled ? onTap : null,
        excludeSemantics: true,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: const BorderRadius.all(PrivioRadius.card),
          child: Stack(
            children: [
              if (showResults)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: chosen
                            ? context.accents.surface
                            : PrivioColors.surfaceRaised,
                        borderRadius: const BorderRadius.all(PrivioRadius.card),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PrivioSpacing.md,
                  vertical: PrivioSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      chosen
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: chosen
                          ? context.accents.bright
                          : PrivioColors.textTertiary,
                    ),
                    const SizedBox(width: PrivioSpacing.sm),
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodyMedium),
                    ),
                    if (showResults) ...[
                      const SizedBox(width: PrivioSpacing.sm),
                      Text('$count', style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
