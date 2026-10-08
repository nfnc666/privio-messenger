import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// The building blocks of the channel settings and the pages under them.
///
/// Built for a phone held by somebody who has turned the text size up, because
/// that is where the first version broke: a row laid its summary *beside* its
/// title, and at a large size the summary took the whole width and pressed the
/// title into a column one letter wide. Here the title always has the full line
/// and the summary sits under it, so nothing can be squeezed out by anything
/// else — however long the description, however large the type.
///
/// Colour carries meaning and nothing else: the account's accent marks what can
/// be opened or is switched on, red marks what cannot be undone, and grey is
/// everything at rest.

/// Whether a tile is ordinary or one of the few that cannot be undone.
enum ChannelTileTone { normal, danger }

/// A captioned card of [ChannelSettingsTile]s.
class ChannelSettingsGroup extends StatelessWidget {
  const ChannelSettingsGroup({
    required this.caption,
    required this.children,
    super.key,
    this.footnote,
    this.tone = ChannelTileTone.normal,
  });

  final String caption;
  final List<Widget> children;

  /// A sentence under the card: why something is the way it is. Not a row,
  /// so it never looks tappable.
  final String? footnote;
  final ChannelTileTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = tone == ChannelTileTone.danger;
    final visible = children;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.gutter,
        PrivioSpacing.xl,
        PrivioSpacing.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: PrivioSpacing.xs, bottom: PrivioSpacing.sm),
            child: Semantics(
              header: true,
              child: Text(
                caption,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: danger ? PrivioColors.danger : context.accents.bright,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (visible.isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                color: PrivioColors.surface,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                border: Border.all(
                  color: danger
                      ? PrivioColors.danger.withValues(alpha: 0.35)
                      : PrivioColors.border,
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                child: Column(
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i > 0)
                        // Indented to the text, so the line reads as a gap
                        // between two rows rather than a box around the icon.
                        const Divider(height: 1, thickness: 1, indent: 68),
                      visible[i],
                    ],
                  ],
                ),
              ),
            ),
          if (footnote != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.xs,
                PrivioSpacing.sm,
                PrivioSpacing.xs,
                0,
              ),
              child: Text(
                footnote!,
                style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

/// One setting: an icon in its own tile, a title, what it is set to, and the
/// way in.
class ChannelSettingsTile extends StatelessWidget {
  const ChannelSettingsTile({
    required this.icon,
    required this.title,
    super.key,
    this.summary,
    this.summaryLines = 2,
    this.status,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.tone = ChannelTileTone.normal,
  });

  final IconData icon;
  final String title;

  /// What it is set to now, under the title. Never beside it.
  final String? summary;
  final int summaryLines;

  /// On or off, drawn as a pill. For a row whose summary *is* a switch state.
  final bool? status;

  /// A switch, a button — anything that replaces the chevron.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Shown but not usable: a right this person lacks, said rather than hidden.
  final bool enabled;
  final ChannelTileTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accents = context.accents;
    final danger = tone == ChannelTileTone.danger;
    final active = enabled && (onTap != null || trailing != null);

    final ink = danger ? PrivioColors.danger : accents.bright;
    final iconColour = enabled ? ink : PrivioColors.textTertiary;
    final tileColour = !enabled
        ? PrivioColors.surfaceHigh
        : danger
            ? PrivioColors.danger.withValues(alpha: 0.14)
            : accents.surface;
    final titleColour = !enabled
        ? PrivioColors.textTertiary
        : danger
            ? PrivioColors.danger
            : PrivioColors.textPrimary;

    final tap = enabled ? onTap : null;

    return MergeSemantics(
      child: InkWell(
        onTap: tap,
        child: ConstrainedBox(
          // A comfortable target at any text size: the row grows with its
          // text, and never shrinks below what a thumb can hit.
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PrivioSpacing.lg,
              vertical: PrivioSpacing.md,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tileColour,
                      borderRadius: const BorderRadius.all(Radius.circular(11)),
                    ),
                    child: Icon(icon, size: 20, color: iconColour),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: titleColour,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (summary != null && summary!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          summary!,
                          maxLines: summaryLines,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: enabled
                                ? PrivioColors.textSecondary
                                : PrivioColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: PrivioSpacing.sm),
                  ChannelStatusPill(on: status!, muted: !enabled),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: PrivioSpacing.sm),
                  trailing!,
                ] else if (active) ...[
                  const SizedBox(width: PrivioSpacing.xs),
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: PrivioColors.textTertiary,
                    ),
                  ),
                ] else if (!enabled) ...[
                  const SizedBox(width: PrivioSpacing.xs),
                  // Why it does nothing, at a glance: it is locked, not broken.
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: PrivioColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "On" in the accent, "Off" in grey — the state of a switch somewhere deeper.
class ChannelStatusPill extends StatelessWidget {
  const ChannelStatusPill({required this.on, super.key, this.muted = false});

  final bool on;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final accents = context.accents;
    final lit = on && !muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: lit ? accents.surface : PrivioColors.surfaceHigh,
        borderRadius: const BorderRadius.all(PrivioRadius.pill),
        border: Border.all(color: lit ? accents.dim : PrivioColors.border),
      ),
      child: Text(
        on ? text.commonOn : text.commonOff,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: lit ? accents.bright : PrivioColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// A labelled text field for the channel pages.
///
/// The label sits above the box in the accent, not on its border: a label
/// floating on an outline cuts the line it sits on, and on black that reads as
/// a broken box. The counter underneath is quiet, because it is a hint rather
/// than content.
class ChannelTextField extends StatelessWidget {
  const ChannelTextField({
    required this.controller,
    super.key,
    this.label,
    this.hint,
    this.enabled = true,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;

  /// Omitted where the section caption already says what the field is.
  final String? label;
  final String? hint;
  final bool enabled;
  final int? maxLength;
  final int? minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accents = context.accents;
    const radius = BorderRadius.all(Radius.circular(14));
    final field = TextField(
      controller: controller,
      enabled: enabled,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: PrivioColors.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        counterStyle: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
        border: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: PrivioColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: PrivioColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: accents.accent, width: 1.6),
        ),
        disabledBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: PrivioColors.surfaceHigh),
        ),
      ),
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: PrivioSpacing.xs, bottom: 6),
          child: Text(
            label!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: enabled ? accents.bright : PrivioColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        field,
      ],
    );
  }
}
