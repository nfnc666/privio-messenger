import 'package:flutter/material.dart';

import '../media/metadata_scrubber.dart';
import '../theme/privio_colors.dart';

/// Tells the user what was stripped out of the file they just sent.
///
/// Shown because "we protect your privacy" means nothing next to "we removed
/// the GPS coordinates, the camera model and the serial number" — and because
/// when a format cannot be cleaned, they need to know that too.
class ScrubNotice extends StatelessWidget {
  const ScrubNotice({required this.report, super.key});

  final ScrubReport report;

  static void show(BuildContext context, ScrubReport report) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PrivioColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: PrivioRadius.card),
      ),
      builder: (_) => ScrubNotice(report: report),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleaned = report.recognised;
    final removedAnything = report.changedAnything;

    return Padding(
      padding: const EdgeInsets.all(PrivioSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                cleaned ? Icons.cleaning_services_rounded : Icons.info_outline_rounded,
                size: 20,
                color: cleaned ? PrivioColors.accent : PrivioColors.warning,
              ),
              const SizedBox(width: PrivioSpacing.md),
              Expanded(
                child: Text(
                  cleaned
                      ? removedAnything
                          ? 'Metadata removed'
                          : 'Nothing to remove'
                      : 'Could not be cleaned',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.md),
          Text(
            cleaned
                ? removedAnything
                    ? 'This was stripped out before the file was encrypted and '
                        'sent. The recipient never receives it.'
                    : 'This file carried no identifying metadata to begin with.'
                : 'Privio has no cleaner for ${report.mediaType} yet, so the file '
                    'was sent as it is. It is still end-to-end encrypted, but any '
                    'metadata inside it reaches the recipient.',
            style: theme.textTheme.bodySmall,
          ),
          if (removedAnything) ...[
            const SizedBox(height: PrivioSpacing.lg),
            for (final item in report.removed)
              Padding(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.close_rounded, size: 15, color: PrivioColors.accent),
                    const SizedBox(width: PrivioSpacing.sm),
                    Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: PrivioSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
