import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'backup_screen.dart';
import 'devices_screen.dart';
import 'disguise_screen.dart';
import 'language_screen.dart';
import 'license_screen.dart';
import 'notifications_screen.dart';
import 'privacy_screen.dart';
import 'storage_screen.dart';

/// Screen 11: the settings index.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);

    void open(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => screen),
        );

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          const SizedBox(height: PrivioSpacing.sm),
          SettingsSection(
            children: [
              // An "Account" row used to open here and do nothing. Settings is
              // reached *from* the Account tab, so a row leading back to it is
              // a circle with a dead button at the top of it.
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
              SettingsRow(
                icon: Icons.data_usage_rounded,
                label: 'Data and Storage',
                onTap: () => open(const StorageScreen()),
              ),
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
                icon: Icons.translate_rounded,
                label: AppText.of(context).languageName,
                // The endonym, so the row says what it will switch to in the
                // word somebody would recognise.
                value: state.locale.language.endonym,
                onTap: () => open(const LanguageScreen()),
              ),
              SettingsRow(
                icon: Icons.cloud_upload_outlined,
                label: 'Backup',
                onTap: () => open(const BackupScreen()),
              ),
              // Not on iOS, where the app's name cannot be changed and the
              // disguise would name itself. A row leading to an explanation of
              // why there is nothing here is still a row about a feature this
              // phone does not have.
              if (state.disguiseSupported)
                SettingsRow(
                  icon: Icons.visibility_off_outlined,
                  label: 'Disguise mode',
                  value: state.disguise?.label,
                  onTap: () => open(const DisguiseScreen()),
                ),
              // There was a Language row here, reading "English", that opened
              // nothing. Privio is English-only; a row saying so as though it
              // were a choice is a choice the app does not offer.
              // Only where there is something to activate. A self-hosted
              // server says it requires no license, and this row goes away.
              if (state.license.isOffered)
                SettingsRow(
                  icon: Icons.key_outlined,
                  label: 'Privio License',
                  value: state.license.needsActivation ? 'Not active' : null,
                  onTap: () => open(const LicenseScreen()),
                ),
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

