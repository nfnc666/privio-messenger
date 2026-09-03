import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Screen 21: appearance.
///
/// It had four rows that did nothing — chat wallpaper, accent colour, app icon,
/// font size — and a theme switch whose Light half was equally inert. Text size
/// is real now and the rest is gone: a setting that does not settle anything is
/// worse than an absent one, because it is a promise the app then breaks
/// quietly.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: const Text('Appearance'),
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
          children: [
            SettingsSection(
              caption: 'Text size',
              children: [
                for (final entry in AppState.textScales.entries)
                  SettingsRow(
                    label: entry.key,
                    // An explicit trailing on every row, ticked or not: the
                    // default is a chevron, and a chevron on a row that picks
                    // something here would promise a screen that does not exist.
                    trailing: SizedBox(
                      width: 20,
                      child: state.textScaleLabel == entry.key
                          ? const Icon(Icons.check_rounded, color: PrivioColors.accent, size: 20)
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
                'This is Privio\'s own setting and it applies everywhere in the app. '
                'It does not override the size your phone is set to for everything '
                'else — that one still applies underneath.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: PrivioSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
              child: Text(
                'Privio is dark-only. The design is built for it, true black costs '
                'nothing on the OLED panels most phones ship with, and a light theme '
                'that only half exists is not worth a switch that pretends otherwise.',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
