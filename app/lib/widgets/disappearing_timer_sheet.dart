import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/notice_text.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// The chooser for a chat's disappearing-message timer.
///
/// One widget for both a person and a group, because it is the same agreement
/// in both: the number rides inside each sealed payload, the other side adopts
/// it, and every device deletes on its own clock. Two copies of this sheet
/// would be two chances for the wording — which is the only place a user learns
/// what the feature actually promises — to drift apart.
abstract final class DisappearingTimerSheet {
  /// What the sheet offers. Ordered shortest first, with "off" at the top
  /// because turning it off is the one choice someone may be in a hurry to make.
  ///
  /// Durations, not labels. It was a map keyed by "30 seconds", which made the
  /// English wording part of the data — and the wording is the one thing here
  /// that differs per reader. [label] turns each into a word.
  static const List<Duration?> options = <Duration?>[
    null,
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(hours: 1),
    Duration(hours: 24),
    Duration(days: 7),
  ];

  /// The row's wording for one of [options].
  static String label(AppText text, Duration? timer) => switch (timer) {
        null => text.disappearingOff,
        Duration(inSeconds: 30) => text.disappearing30Seconds,
        Duration(inSeconds: 60) => text.disappearing1Minute,
        Duration(inSeconds: 300) => text.disappearing5Minutes,
        Duration(inSeconds: 3600) => text.disappearing1Hour,
        Duration(inSeconds: 86400) => text.disappearing24Hours,
        Duration(inSeconds: 604800) => text.disappearing7Days,
        // Not reachable from [options], and still answered rather than thrown:
        // a timer set by another device is whatever that device offered.
        _ => describeDuration(text, timer),
      };

  /// The short form the composer's button wears beside its icon.
  ///
  /// Not the same strings as [label]: a button has room for "30s", not for
  /// "30 seconds", and a label that wraps or elides is worse than a shorter one.
  static String badge(AppText text, Duration timer) {
    if (timer.inDays >= 1) return text.timerBadgeDays(timer.inDays);
    if (timer.inHours >= 1) return text.timerBadgeHours(timer.inHours);
    if (timer.inMinutes >= 1) return text.timerBadgeMinutes(timer.inMinutes);
    return text.timerBadgeSeconds(timer.inSeconds);
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
                      AppText.of(sheetContext).disappearingTitle,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      AppText.of(sheetContext).disappearingExplainer,
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      isGroup
                          ? AppText.of(sheetContext).disappearingCoversGroup
                          : AppText.of(sheetContext).disappearingCoversChat,
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: PrivioSpacing.sm),
                    // Said here rather than discovered later: this deletes the
                    // app's own copies and nothing else. Anyone who promises
                    // more than that is promising something they cannot keep.
                    Text(
                      AppText.of(sheetContext).disappearingScreenshotCaveat,
                      style: Theme.of(sheetContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: PrivioColors.textTertiary),
                    ),
                  ],
                ),
              ),
              for (final option in options)
                ListTile(
                  title: Text(label(AppText.of(sheetContext), option)),
                  trailing: option == current
                      ? Icon(Icons.check_rounded, color: context.accents.accent)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop((value: option)),
                ),
              const SizedBox(height: PrivioSpacing.sm),
            ],
          ),
        ),
      );
}
