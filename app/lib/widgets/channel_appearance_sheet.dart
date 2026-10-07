import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';

/// The channel's own colours, with the result drawn rather than described.
///
/// Lifted out of the settings screen it used to live inside, unchanged: the
/// screen was replaced, this was not. A channel's accent is the one colour in
/// Privio that is *not* the reader's own choice — somebody else's channel is
/// somebody else's, and a reader repainting it would make their setting change
/// what a channel looks like.
class ChannelAppearanceSheet extends StatefulWidget {
  const ChannelAppearanceSheet({super.key, this.accent, this.background});

  final String? accent;
  final String? background;

  @override
  State<ChannelAppearanceSheet> createState() => _ChannelAppearanceSheetState();
}

class _ChannelAppearanceSheetState extends State<ChannelAppearanceSheet> {
  late String? _accent = widget.accent;
  late String? _background = widget.background;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(PrivioSpacing.gutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppText.of(context).editChannelAppearance,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: PrivioSpacing.xs),
                Text(
                  AppText.of(context).appearanceNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: PrivioSpacing.lg),

                // The preview, which is the point of the sheet.
                Container(
                  height: 96,
                  decoration: BoxDecoration(
                    color: ChannelPalette.backgroundFor(_background),
                    borderRadius: BorderRadius.circular(PrivioSpacing.md),
                    border: Border.all(color: PrivioColors.border),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppText.of(context).appearancePreviewPost,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: PrivioSpacing.xs),
                        Text(
                          AppText.of(context).appearancePreviewLink,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: ChannelPalette.accentFor(_accent),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.lg),

                Text(
                  AppText.of(context).appearanceAccent,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: PrivioSpacing.sm),
                Wrap(
                  spacing: PrivioSpacing.sm,
                  children: [
                    for (final entry in ChannelPalette.accents.entries)
                      GestureDetector(
                        onTap: () => setState(() => _accent = entry.key),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: entry.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _accent == entry.key
                                  ? PrivioColors.textPrimary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.lg),

                Text(
                  AppText.of(context).appearanceBackground,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: PrivioSpacing.sm),
                Wrap(
                  spacing: PrivioSpacing.sm,
                  children: [
                    for (final entry in ChannelPalette.backgrounds.entries)
                      GestureDetector(
                        onTap: () => setState(() => _background = entry.key),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: entry.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _background == entry.key
                                  ? PrivioColors.textPrimary
                                  : PrivioColors.border,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.lg),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _accent = null;
                        _background = null;
                      }),
                      child: Text(AppText.of(context).appearanceUseDefault),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(context)
                          .pop((accent: _accent, background: _background)),
                      child: Text(AppText.of(context).commonDone),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
