import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../core/app_icon.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import 'privio_logo.dart';

/// The eight accents, as a grid of swatches inside the settings card.
///
/// A grid rather than a list of rows: a colour is recognised by looking at it,
/// and eight rows of one dot each would be a screen of mostly empty space. The
/// name sits under every swatch all the same — a dot alone is unusable to
/// anybody who cannot tell two of these apart, and "the green one" is not a
/// thing a screen reader can say.
class AccentPicker extends StatelessWidget {
  const AccentPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final AppAccent selected;
  final ValueChanged<AppAccent> onSelected;

  /// What each accent is called, in the reader's language.
  ///
  /// The colour names are translated — they are the app's words, not anybody's
  /// content. "PRIVIO" in the default badge is not.
  static String nameOf(AppText text, AppAccent accent) => switch (accent) {
        AppAccent.green => text.accentGreen,
        AppAccent.blue => text.accentBlue,
        AppAccent.teal => text.accentTeal,
        AppAccent.purple => text.accentPurple,
        AppAccent.pink => text.accentPink,
        AppAccent.red => text.accentRed,
        AppAccent.orange => text.accentOrange,
        AppAccent.yellow => text.accentYellow,
      };

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Padding(
      padding: const EdgeInsets.all(PrivioSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Four across on an ordinary phone, two when the text is large
          // enough that four names would not fit. Measured rather than
          // guessed at a breakpoint, so it also holds on a small display.
          final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
          final minTile = 68.0 * scale;
          final columns = (constraints.maxWidth / minTile).floor().clamp(2, 4);

          return Wrap(
            spacing: PrivioSpacing.sm,
            runSpacing: PrivioSpacing.lg,
            children: [
              for (final accent in AppAccent.values)
                SizedBox(
                  width: (constraints.maxWidth - PrivioSpacing.sm * (columns - 1)) / columns,
                  child: _Swatch(
                    accent: accent,
                    name: nameOf(text, accent),
                    isDefault: accent == AppAccent.fallback,
                    selected: accent == selected,
                    onTap: () => onSelected(accent),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.accent,
    required this.name,
    required this.isDefault,
    required this.selected,
    required this.onTap,
  });

  final AppAccent accent;
  final String name;
  final bool isDefault;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final colours = PrivioAccents.of(accent);

    return Semantics(
      button: true,
      selected: selected,
      // The state as a word as well as a ring: "selected" is what a screen
      // reader can convey, and a ring is not.
      label: selected ? text.accentSelected(name) : name,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The ring sits outside the dot rather than around it, so the
              // dot is the same size whether it is chosen or not and the row
              // does not jump when the choice moves.
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colours.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colours.accent,
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          // On the dot, so it follows the same readability
                          // rule every label on an accent does.
                          color: colours.onAccent,
                          size: 20,
                          key: ValueKey('accent-check-${accent.code}'),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                name,
                key: ValueKey('accent-name-${accent.code}'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? PrivioColors.textPrimary : PrivioColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (isDefault)
                Text(
                  text.accentPrivioDefault,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A button, a switch and a message bubble in the accent being previewed.
///
/// Live rather than a picture: these are the real widgets, so what the card
/// shows is what the app will look like — including the label colour flipping
/// on the lighter accents, which is the part worth seeing before committing.
class AccentPreview extends StatelessWidget {
  const AccentPreview({required this.accent, super.key});

  final AppAccent accent;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);
    final colours = PrivioAccents.of(accent);

    return Padding(
      padding: const EdgeInsets.all(PrivioSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(
                horizontal: PrivioSpacing.md,
                vertical: PrivioSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colours.bubbleOutgoing,
                borderRadius: const BorderRadius.only(
                  topLeft: PrivioRadius.bubble,
                  topRight: PrivioRadius.bubble,
                  bottomLeft: PrivioRadius.bubble,
                ),
              ),
              child: Text(
                text.appearancePreviewMessage,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: PrivioSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  text.appearancePreviewSetting,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              // Not wired to anything: it is a preview, and a switch here that
              // changed a setting would be a trap.
              IgnorePointer(
                child: Switch(
                  value: true,
                  onChanged: (_) {},
                  thumbColor: const WidgetStatePropertyAll(PrivioColors.textPrimary),
                  trackColor: WidgetStatePropertyAll(colours.accent),
                  trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                ),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.md),
          IgnorePointer(
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: colours.accent,
                foregroundColor: colours.onAccent,
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(text.appearancePreviewSend),
            ),
          ),
        ],
      ),
    );
  }
}

/// The eight home-screen icons, as a grid of previews.
///
/// The preview is the delivered mark tinted at draw time rather than eight more
/// bundled pictures: same file, same glyph, same padding, so what the row shows
/// cannot drift from what the launcher will show. The bundled variants are the
/// ones the platform actually installs; these are only the picture of them.
class AppIconPicker extends StatelessWidget {
  const AppIconPicker({
    required this.selected,
    required this.onSelected,
    required this.enabled,
    super.key,
  });

  final AppIconColour selected;
  final ValueChanged<AppIconColour> onSelected;

  /// False while a change is in flight, or on a platform that cannot.
  final bool enabled;

  static String nameOf(AppText text, AppIconColour colour) =>
      AccentPicker.nameOf(text, colour.accent);

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Padding(
      padding: const EdgeInsets.all(PrivioSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
          final minTile = 76.0 * scale;
          final columns = (constraints.maxWidth / minTile).floor().clamp(2, 4);

          return Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Wrap(
              spacing: PrivioSpacing.sm,
              runSpacing: PrivioSpacing.lg,
              children: [
                for (final colour in AppIconColour.values)
                  SizedBox(
                    width: (constraints.maxWidth - PrivioSpacing.sm * (columns - 1)) / columns,
                    child: _IconSwatch(
                      colour: colour,
                      name: nameOf(text, colour),
                      isDefault: colour == AppIconColour.fallback,
                      selected: colour == selected,
                      onTap: enabled ? () => onSelected(colour) : null,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _IconSwatch extends StatelessWidget {
  const _IconSwatch({
    required this.colour,
    required this.name,
    required this.isDefault,
    required this.selected,
    required this.onTap,
  });

  final AppIconColour colour;
  final String name;
  final bool isDefault;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final accent = PrivioAccents.of(colour.accent);

    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: selected ? text.appIconSelected(name) : text.appIconChoose(name),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      // The icon's own black, not the card's — this is a
                      // picture of a home-screen icon, and that is what it
                      // sits on.
                      color: PrivioColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? accent.accent : PrivioColors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        PrivioLogoAsset.mark,
                        // Tinted rather than eight more files. The mark is one
                        // glyph on transparency, so srcIn recolours exactly
                        // what the bundled variant recolours.
                        color: colour == AppIconColour.green ? null : accent.accent,
                        colorBlendMode: colour == AppIconColour.green ? null : BlendMode.srcIn,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  if (selected)
                    Container(
                      key: ValueKey('app-icon-check-${colour.code}'),
                      decoration: BoxDecoration(
                        color: accent.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: PrivioColors.surface, width: 2),
                      ),
                      child: Icon(Icons.check_rounded, size: 14, color: accent.onAccent),
                    ),
                ],
              ),
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                name,
                key: ValueKey('app-icon-name-${colour.code}'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? PrivioColors.textPrimary : PrivioColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (isDefault)
                Text(
                  text.appearanceAppIconOriginal,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
