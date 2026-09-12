import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
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
        listenable: state,
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
                text.appearanceTextSizeNote,
                style: theme.textTheme.bodySmall,
              ),
            ),
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
