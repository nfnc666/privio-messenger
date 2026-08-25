import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';
import '../widgets/privio_logo.dart';
import '../widgets/settings_row.dart';

/// Screen 22: about.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About Privio')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          const SizedBox(height: PrivioSpacing.xxl),
          const Center(child: PrivioWordmark(markSize: 72, glow: false)),
          const SizedBox(height: PrivioSpacing.sm),
          Center(
            child: Text('Version 0.1.0 (1)', style: theme.textTheme.bodySmall),
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
              SettingsRow(label: 'Website', onTap: () {}),
              SettingsRow(label: 'Support', onTap: () {}),
              SettingsRow(label: 'Terms of Service', onTap: () {}),
              SettingsRow(label: 'Privacy Policy', onTap: () {}),
              SettingsRow(label: 'Open Source Licenses', onTap: () {}),
            ],
          ),
        ],
      ),
    );
  }
}
