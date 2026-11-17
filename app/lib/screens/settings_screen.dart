import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import 'about_screen.dart';
import 'proxy_screen.dart';
import '../network/proxy_controller.dart';
import 'appearance_screen.dart';
import 'backup_screen.dart';
import 'devices_screen.dart';
import 'disguise_screen.dart';
import 'language_screen.dart';
import 'license_screen.dart';
import 'notifications_screen.dart';
import 'privacy_screen.dart';
import 'stickers_screen.dart';
import 'storage_screen.dart';

/// Screen 11: the settings index.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final text = AppText.of(context);

    void open(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => screen),
        );

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsTitle),
      ),
      // Grouped by what somebody comes here to do, each group named, rather
      // than one list of twelve rows in the order they were built. Backup sits
      // with the account it protects; the proxy and the disguise with the
      // other things that decide who can see what.
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          SettingsSection(
            caption: text.settingsGroupSecurity,
            children: [
              // An "Account" row used to open here and do nothing. Settings is
              // reached *from* the Account tab, so a row leading back to it is
              // a circle with a dead button at the top of it.
              SettingsRow(
                icon: Icons.lock_outline_rounded,
                label: text.settingsPrivacy,
                onTap: () => open(const PrivacyScreen()),
              ),
              SettingsRow(
                icon: Icons.devices_outlined,
                label: text.settingsDevices,
                onTap: () => open(const DevicesScreen()),
              ),
              SettingsRow(
                icon: Icons.cloud_upload_outlined,
                label: text.settingsBackup,
                onTap: () => open(const BackupScreen()),
              ),
              if (ProxyController.supported)
                SettingsRow(
                  icon: Icons.lan_outlined,
                  label: text.proxyTitle,
                  onTap: () => open(const ProxyScreen()),
                ),
              // Not on iOS, where the app's name cannot be changed and the
              // disguise would name itself. A row leading to an explanation of
              // why there is nothing here is still a row about a feature this
              // phone does not have.
              if (state.disguiseSupported)
                SettingsRow(
                  icon: Icons.visibility_off_outlined,
                  label: text.settingsDisguise,
                  value: state.disguise?.label,
                  onTap: () => open(const DisguiseScreen()),
                ),
            ],
          ),
          SettingsSection(
            caption: text.settingsGroupChats,
            children: [
              SettingsRow(
                icon: Icons.notifications_none_rounded,
                label: text.settingsNotifications,
                onTap: () => open(const NotificationsScreen()),
              ),
              SettingsRow(
                icon: Icons.data_usage_rounded,
                label: text.settingsStorage,
                onTap: () => open(const StorageScreen()),
              ),
              SettingsRow(
                icon: Icons.emoji_emotions_outlined,
                label: text.settingsStickers,
                onTap: () => open(const StickersScreen()),
              ),
            ],
          ),
          SettingsSection(
            caption: text.settingsGroupLook,
            children: [
              SettingsRow(
                icon: Icons.palette_outlined,
                label: text.settingsAppearance,
                onTap: () => open(const AppearanceScreen()),
              ),
              SettingsRow(
                icon: Icons.translate_rounded,
                label: text.languageName,
                // The endonym, so the row says what it will switch to in the
                // word somebody would recognise.
                value: state.locale.language.endonym,
                onTap: () => open(const LanguageScreen()),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.xl),
          SettingsSection(
            children: [
              // Only where there is something to activate. A self-hosted
              // server says it requires no license, and this row goes away.
              if (state.license.isOffered)
                SettingsRow(
                  icon: Icons.key_outlined,
                  label: text.settingsLicense,
                  value: state.license.needsActivation ? text.settingsLicenseNotActive : null,
                  onTap: () => open(const LicenseScreen()),
                ),
              SettingsRow(
                icon: Icons.info_outline_rounded,
                label: text.settingsAbout,
                onTap: () => open(const AboutScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
