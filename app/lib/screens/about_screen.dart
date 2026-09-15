import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/edition.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/privio_logo.dart';
import '../widgets/settings_row.dart';

/// Screen 22: about.
///
/// Also where this build says what it is. Which edition, under which licence,
/// built from which source — the three things someone needs to check that the
/// app on their phone is the app this repository describes.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _version = '0.1.0 (1)';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final edition = PrivioEdition.current;
    final text = AppText.of(context);

    Future<void> copy(String what, String value) async {
      await Clipboard.setData(ClipboardData(text: value));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.aboutCopied(what))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsAbout),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          const SizedBox(height: PrivioSpacing.xxl),
          const Center(child: PrivioWordmark(markSize: 52, glow: false)),
          const SizedBox(height: PrivioSpacing.sm),
          Center(
            child: Text(
              '${edition.name} $_version',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: PrivioSpacing.md),
          Center(
            child: Text(
              text.aboutTagline,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: PrivioSpacing.xxl),
          SettingsSection(
            children: [
              SettingsRow(
                label: text.aboutWebsite,
                onTap: () => copy(text.aboutWebsite, 'https://getprivio.com'),
              ),
              SettingsRow(
                label: text.aboutSupport,
                onTap: () => copy(text.aboutAddress, 'support@getprivio.com'),
              ),
              // "Terms of Service" and "Privacy Policy" sat here and opened
              // nothing, because neither document exists. Both have to before
              // this reaches a store; a row that names one and produces
              // nothing is worse than a screen that does not claim to have it.
              // What is real about how Privio treats data is in the repository
              // linked below, in docs/security-model.md.
            ],
          ),
          SettingsSection(
            caption: text.aboutOpenSource,
            children: [
              SettingsRow(
                label: text.aboutEdition,
                value: edition.containsOnlyFreeSoftware
                    ? text.aboutFreeSoftware(edition.name)
                    : edition.name,
              ),
              SettingsRow(label: text.aboutLicense, value: PrivioEdition.licenseSpdxId),
              SettingsRow(
                label: text.aboutSourceCode,
                value: text.aboutCopyLink,
                onTap: () => copy(text.aboutSourceLink, PrivioEdition.sourceUrl),
              ),
              SettingsRow(
                label: text.aboutThirdParty,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: edition.name,
                  applicationVersion: _version,
                  applicationLegalese: '© 2026 Privio · ${PrivioEdition.licenseName}',
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              PrivioSpacing.gutter + PrivioSpacing.xs,
              PrivioSpacing.md,
              PrivioSpacing.gutter + PrivioSpacing.xs,
              0,
            ),
            child: _SourceNote(),
          ),
        ],
      ),
    );
  }
}

class _SourceNote extends StatelessWidget {
  const _SourceNote();

  @override
  Widget build(BuildContext context) {
    final edition = PrivioEdition.current;
    final theme = Theme.of(context);

    return Text(
      edition.containsOnlyFreeSoftware
          ? AppText.of(context).aboutFreeBuildNote
          : AppText.of(context).aboutStoreBuildNote,
      style: theme.textTheme.labelSmall,
    );
  }
}
