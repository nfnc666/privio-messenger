import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';
import '../widgets/settings_row.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'backup_screen.dart';
import 'devices_screen.dart';
import 'notifications_screen.dart';
import 'privacy_screen.dart';

/// Screen 11: the settings index.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => screen),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          const SizedBox(height: PrivioSpacing.sm),
          SettingsSection(
            children: [
              SettingsRow(icon: Icons.person_outline_rounded, label: 'Account', onTap: () {}),
              SettingsRow(
                icon: Icons.lock_outline_rounded,
                label: 'Privacy & Security',
                onTap: () => open(const PrivacyScreen()),
              ),
              SettingsRow(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                onTap: () => open(const NotificationsScreen()),
              ),
              SettingsRow(icon: Icons.data_usage_rounded, label: 'Data and Storage', onTap: () {}),
              SettingsRow(
                icon: Icons.devices_outlined,
                label: 'Devices',
                onTap: () => open(const DevicesScreen()),
              ),
              SettingsRow(
                icon: Icons.palette_outlined,
                label: 'Appearance',
                onTap: () => open(const AppearanceScreen()),
              ),
              SettingsRow(
                icon: Icons.cloud_upload_outlined,
                label: 'Backup',
                onTap: () => open(const BackupScreen()),
              ),
              SettingsRow(
                icon: Icons.visibility_off_outlined,
                label: 'Disguise Mode',
                value: 'V2',
                onTap: () {},
              ),
              SettingsRow(icon: Icons.language_rounded, label: 'Language', value: 'English', onTap: () {}),
              SettingsRow(
                icon: Icons.info_outline_rounded,
                label: 'About Privio',
                onTap: () => open(const AboutScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
