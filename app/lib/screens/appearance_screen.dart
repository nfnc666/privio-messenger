import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_icon.dart';
import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/accent_picker.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Screen 21: appearance.
///
/// It had four rows that did nothing — chat wallpaper, accent colour, app icon,
/// font size — and a theme switch whose Light half was equally inert. Text size
/// is real now and the rest is gone: a setting that does not settle anything is
/// worse than an absent one, because it is a promise the app then breaks
/// quietly.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  @override
  void initState() {
    super.initState();
    // What the launcher is actually showing, not what was stored. The two can
    // part company — a change that failed, a restored backup — and a tick
    // under a colour the home screen is not wearing is the one mistake this
    // setting cannot afford.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(PrivioScope.of(context).appIcon.reconcile()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);
    final text = AppText.of(context);

    // The word for each size, by id. One place, so a new size cannot be added
    // to the map and reach the screen as its own id.
    final sizeNames = {
      'small': text.textSizeSmall,
      'medium': text.textSizeMedium,
      'large': text.textSizeLarge,
      'larger': text.textSizeLarger,
    };

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsAppearance),
      ),
      body: ListenableBuilder(
        // Both, because the accent lives on its own controller and picking one
        // has to redraw this screen as well as the app around it.
        listenable: Listenable.merge([state, state.accent, state.appIcon]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
          children: [
            SettingsSection(
              caption: text.appearanceTextSize,
              children: [
                for (final entry in AppState.textScales.entries)
                  SettingsRow(
                    label: sizeNames[entry.key] ?? entry.key,
                    // An explicit trailing on every row, ticked or not: the
                    // default is a chevron, and a chevron on a row that picks
                    // something here would promise a screen that does not exist.
                    trailing: SizedBox(
                      width: 20,
                      child: state.textScaleId == entry.key
                          ? Icon(Icons.check_rounded, color: context.accents.accent, size: 20)
                          : null,
                    ),
                    onTap: () => state.setTextScale(entry.value),
                  ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
              child: Text(
                text.appearanceTextSizeNote,
                style: theme.textTheme.bodySmall,
              ),
            ),
            SettingsSection(
              caption: text.appearanceAccentColour,
              children: [
                AccentPicker(
                  selected: state.accent.accent,
                  // Awaited nowhere: the repaint is immediate and the write to
                  // the keystore follows it. Making the tap wait for storage
                  // would put a disk round-trip between a finger and a colour.
                  onSelected: (accent) => unawaited(state.accent.choose(accent)),
                ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.xl),
            SettingsSection(
              caption: text.appearanceAccentPreview,
              children: [AccentPreview(accent: state.accent.accent)],
            ),
            if (state.accent.accent != AppAccent.fallback) ...[
              const SizedBox(height: PrivioSpacing.lg),
              SettingsSection(
                children: [
                  SettingsRow(
                    key: const ValueKey('accent-reset'),
                    label: text.appearanceAccentReset,
                    trailing: const SizedBox(width: 20),
                    onTap: () => unawaited(state.accent.reset()),
                  ),
                ],
              ),
            ],
            const SizedBox(height: PrivioSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
              child: Text(
                text.appearanceAccentNote,
                style: theme.textTheme.bodySmall,
              ),
            ),
            _AppIconSection(state: state),
            const SizedBox(height: PrivioSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
              child: Text(
                text.appearanceDarkOnly,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The home-screen icon, under the accent it borrows its colours from.
///
/// Hidden rather than shown-and-disabled where the platform cannot change it:
/// a row that explains why it will not work is better than eight swatches that
/// do nothing, and better still is the one line that says so.
class _AppIconSection extends StatelessWidget {
  const _AppIconSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);
    final icon = state.appIcon;

    if (!icon.supported) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.xxl,
          PrivioSpacing.xl,
          PrivioSpacing.xxl,
          0,
        ),
        child: Text(
          text.appearanceAppIconUnavailable,
          key: const ValueKey('app-icon-unavailable'),
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final disguised = state.disguise != null;
    final failure = icon.failure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          caption: text.appearanceAppIcon,
          children: [
            AppIconPicker(
              selected: icon.colour,
              enabled: !icon.busy,
              onSelected: (colour) =>
                  unawaited(icon.choose(colour, disguised: disguised)),
            ),
          ],
        ),
        const SizedBox(height: PrivioSpacing.lg),
        SettingsSection(
          children: [
            SettingsRow(
              key: const ValueKey('app-icon-match-accent'),
              label: text.appearanceAppIconMatchAccent,
              enabled: !icon.busy,
              trailing: const SizedBox(width: 20),
              onTap: () => unawaited(
                icon.matchAccent(state.accent.accent, disguised: disguised),
              ),
            ),
            if (icon.colour != AppIconColour.fallback)
              SettingsRow(
                key: const ValueKey('app-icon-reset'),
                label: text.appearanceAppIconReset,
                enabled: !icon.busy,
                trailing: const SizedBox(width: 20),
                onTap: () => unawaited(icon.reset(disguised: disguised)),
              ),
          ],
        ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.xxl,
              PrivioSpacing.md,
              PrivioSpacing.xxl,
              0,
            ),
            child: Text(
              failure.words(text),
              key: const ValueKey('app-icon-failure'),
              style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.xxl,
            PrivioSpacing.md,
            PrivioSpacing.xxl,
            0,
          ),
          child: Text(text.appearanceAppIconNote, style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: PrivioSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
          child: Text(text.appearanceAppIconSlow, style: theme.textTheme.labelSmall),
        ),
      ],
    );
  }
}
