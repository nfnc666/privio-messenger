import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';
import '../widgets/settings_row.dart';

/// Screen 21: appearance.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  int _theme = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.gutter,
              PrivioSpacing.lg,
              PrivioSpacing.gutter,
              PrivioSpacing.sm,
            ),
            child: Text('Theme', style: theme.textTheme.labelMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
            child: Row(
              children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 0 ? PrivioSpacing.md : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _theme = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.md),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _theme == i ? PrivioColors.surfaceHigh : PrivioColors.surface,
                            borderRadius: const BorderRadius.all(PrivioRadius.card),
                            border: Border.all(
                              color: _theme == i ? PrivioColors.accent : Colors.transparent,
                            ),
                          ),
                          child: Text(i == 0 ? 'Dark' : 'Light'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: PrivioSpacing.lg),
          SettingsSection(
            children: [
              SettingsRow(label: 'Chat Wallpaper', onTap: () {}),
              SettingsRow(
                label: 'Accent Color',
                onTap: () {},
                trailing: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: PrivioColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              SettingsRow(label: 'App Icon', value: 'Default', onTap: () {}),
              SettingsRow(label: 'Font Size', value: 'Medium', onTap: () {}),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
            child: Text(
              'Privio is designed dark-first. The light theme lands with V2.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
