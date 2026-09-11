import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';

/// The chooser for a chat's disappearing-message timer.
///
/// One widget for both a person and a group, because it is the same agreement
/// in both: the number rides inside each sealed payload, the other side adopts
/// it, and every device deletes on its own clock. Two copies of this sheet
/// would be two chances for the wording — which is the only place a user learns
/// what the feature actually promises — to drift apart.
abstract final class DisappearingTimerSheet {
  /// What the sheet offers. Ordered shortest first, with `Off` at the top
  /// because turning it off is the one choice someone may be in a hurry to make.
  static const Map<String, Duration?> options = <String, Duration?>{
    'Off': null,
    '30 seconds': Duration(seconds: 30),
    '1 minute': Duration(minutes: 1),
    '5 minutes': Duration(minutes: 5),
    '1 hour': Duration(hours: 1),
    '24 hours': Duration(hours: 24),
    '7 days': Duration(days: 7),
  };

  /// The short form the composer's button wears beside its icon.
  ///
  /// Not the same strings as [options]: a button has room for "30s", not for
  /// "30 seconds", and a label that wraps or elides is worse than a shorter one.
  static String badge(Duration timer) {
    if (timer.inDays >= 1) return '${timer.inDays}d';
    if (timer.inHours >= 1) return '${timer.inHours}h';
    if (timer.inMinutes >= 1) return '${timer.inMinutes}m';
    return '${timer.inSeconds}s';
  }

  /// Asks for a new timer. Returns null when the sheet was dismissed, which is
  /// not the same as choosing `Off` — hence the wrapper.
  static Future<({Duration? value})?> choose(
    BuildContext context, {
    required Duration? current,
    required bool isGroup,
  }) =>
      showModalBottomSheet<({Duration? value})>(
        context: context,
        backgroundColor: PrivioColors.surface,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(PrivioSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Disappearing messages',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      'New messages are deleted automatically after this long. '
                      'The timer starts when the message is sent.',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      isGroup
                          ? 'It covers text, photos, files and voice messages, '
                              'and applies to this group only. Messages already '
                              'sent are not affected, everyone is told when it '
                              'changes, and only an admin can change it.'
                          : 'It covers text, photos, files and voice messages, '
                              'and applies to this chat only. Messages already '
                              'sent are not affected, and both of you are told '
                              'when it changes.',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PrivioSpacing.sm),
                    // Said here rather than discovered later: this deletes the
                    // app's own copies and nothing else. Anyone who promises
                    // more than that is promising something they cannot keep.
                    Text(
                      'It cannot undo a screenshot, a photo already saved, or '
                      'anything written down elsewhere.',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: PrivioColors.textTertiary),
                    ),
                  ],
                ),
              ),
              for (final option in options.entries)
                ListTile(
                  title: Text(option.key),
                  trailing: option.value == current
                      ? const Icon(Icons.check_rounded, color: PrivioColors.accent)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop((value: option.value)),
                ),
              const SizedBox(height: PrivioSpacing.sm),
            ],
          ),
        ),
      );
}
