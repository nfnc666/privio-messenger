import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';
import '../widgets/settings_row.dart';

/// Screen 12: end-to-end encrypted backup.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _includeVideos = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          const SizedBox(height: PrivioSpacing.xl),
          const Center(
            child: Icon(Icons.cloud_done_outlined, size: 64, color: PrivioColors.accent),
          ),
          const SizedBox(height: PrivioSpacing.xl),
          const SettingsSection(
            children: [
              SettingsRow(label: 'Last Backup', value: 'Today, 10:45'),
              SettingsRow(label: 'Total Size', value: '1.2 GB'),
              SettingsRow(label: 'End-to-end Encrypted', value: 'On'),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
            child: FilledButton(onPressed: () {}, child: const Text('Back Up Now')),
          ),
          const SizedBox(height: PrivioSpacing.lg),
          SettingsSection(
            children: [
              SettingsRow(label: 'Auto Backup', value: 'Weekly', onTap: () {}),
              SettingsRow(
                label: 'Include Videos',
                trailing: Switch(
                  value: _includeVideos,
                  onChanged: (value) => setState(() => _includeVideos = value),
                ),
              ),
              SettingsRow(label: 'Recovery Key', onTap: () {}),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
            child: Text(
              'Backups are sealed on this device with your recovery key. Privio '
              'cannot open them and cannot reset the key — if you lose it, the '
              'backup is gone. Write it down somewhere safe.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
