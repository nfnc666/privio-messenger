import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/locale_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Picking the language the interface is in.
///
/// Every language is listed under the name its own speakers use, never
/// translated into the current one: somebody who opened this screen because the
/// app is in a language they cannot read is looking for the word *they* would
/// write, and a list that says "German" is a list only an English speaker can
/// use. That is also why the rows are not localised — they are the same five
/// words whatever the app is currently set to.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final text = AppText.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.languagePickerTitle),
      ),
      body: ListenableBuilder(
        listenable: state.locale,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
          children: [
            const SizedBox(height: PrivioSpacing.sm),
            SettingsSection(
              children: [
                for (final language in AppLanguage.values)
                  SettingsRow(
                    key: ValueKey('language-${language.code}'),
                    label: language.endonym,
                    // Explicit on every row, ticked or not: the default
                    // trailing is a chevron, and a chevron here would promise a
                    // screen underneath a row that only makes a choice.
                    trailing: SizedBox(
                      width: 20,
                      child: state.locale.language == language
                          ? const Icon(
                              Icons.check_rounded,
                              color: PrivioColors.accent,
                              size: 20,
                            )
                          : null,
                    ),
                    onTap: () => state.locale.choose(language),
                  ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
              child: Text(
                text.languagePickerNote,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
