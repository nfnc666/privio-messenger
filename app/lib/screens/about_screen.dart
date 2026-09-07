import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/edition.dart';
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

    Future<void> copy(String label, String value) async {
      await Clipboard.setData(ClipboardData(text: value));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: const Text('About Privio'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          const SizedBox(height: PrivioSpacing.xxl),
          const Center(child: PrivioWordmark(markSize: 72, glow: false)),
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
              'Built with privacy in mind.\nNo tracking. No ads. Just you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: PrivioSpacing.xxl),
          SettingsSection(
            children: [
              SettingsRow(label: 'Website', onTap: () => copy('Website', 'https://getprivio.com')),
              SettingsRow(label: 'Support', onTap: () => copy('Address', 'support@getprivio.com')),
              // "Terms of Service" and "Privacy Policy" sat here and opened
              // nothing, because neither document exists. Both have to before
              // this reaches a store; a row that names one and produces
              // nothing is worse than a screen that does not claim to have it.
              // What is real about how Privio treats data is in the repository
              // linked below, in docs/security-model.md.
            ],
          ),
          SettingsSection(
            caption: 'Open source',
            children: [
              SettingsRow(
                label: 'Edition',
                value: edition.containsOnlyFreeSoftware ? '${edition.name} · free software' : edition.name,
              ),
              const SettingsRow(label: 'License', value: PrivioEdition.licenseSpdxId),
              SettingsRow(
                label: 'Source code',
                value: 'Copy link',
                onTap: () => copy('Source link', PrivioEdition.sourceUrl),
              ),
              SettingsRow(
                label: 'Third-party licenses',
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
          ? 'This build contains no proprietary code and can be reproduced from '
              'the source above. Nothing here has to be taken on trust — build it '
              'yourself and compare.'
          : 'This build came from an app store and links that store\'s services. '
              'The Libre build, at the source above, contains none of them.',
      style: theme.textTheme.labelSmall,
    );
  }
}
