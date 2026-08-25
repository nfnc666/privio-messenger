import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/settings_row.dart';
import 'invite_screen.dart';
import 'settings_screen.dart';

/// Screen 9: the account overview.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = PrivioScope.of(context).username ?? 'privio_user';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
          const SizedBox(width: PrivioSpacing.xs),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: PrivioSpacing.lg),
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    PrivioAvatar(label: username, size: 88, seed: 3),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: PrivioColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera_rounded,
                          size: 14,
                          color: PrivioColors.background,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.md),
                Text('John Doe', style: theme.textTheme.titleLarge),
                Text('@$username', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: PrivioSpacing.xxl),
          SettingsSection(
            children: [
              SettingsRow(icon: Icons.alternate_email_rounded, label: 'Username', value: username),
              const SettingsRow(
                icon: Icons.mood_rounded,
                label: 'Status',
                value: 'Hey there! I am using Privio.',
              ),
              const SettingsRow(icon: Icons.badge_outlined, label: 'Account Type', value: 'Standard'),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          SettingsSection(
            children: [
              const SettingsRow(icon: Icons.sd_storage_outlined, label: 'Storage', value: '1.2 GB / 5 GB'),
              const SettingsRow(icon: Icons.shield_outlined, label: 'Security Level', value: 'High'),
              SettingsRow(
                icon: Icons.qr_code_rounded,
                label: 'Invite link / QR code',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const InviteScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          SettingsSection(
            children: [
              SettingsRow(
                label: 'Log Out',
                destructive: true,
                onTap: () => _confirmSignOut(context),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.xxxl),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Log out?'),
        content: const Text(
          'Your messages stay encrypted on this device until you delete them. '
          'You will need your password to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              PrivioScope.of(context).signOut();
            },
            style: TextButton.styleFrom(foregroundColor: PrivioColors.danger),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
