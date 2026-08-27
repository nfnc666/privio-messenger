import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/settings_row.dart';
import 'backup_screen.dart';
import 'invite_screen.dart';
import 'settings_screen.dart';

/// Screen 9: the account overview.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _uploading = false;

  /// Picks a picture, shrinks it, strips it and seals it under the profile key.
  ///
  /// The server ends up holding an image it cannot open — which is the whole
  /// point of doing this rather than posting a JPEG.
  Future<void> _pickAvatar() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        withData: true,
        type: FileType.image,
      ).timeout(const Duration(minutes: 2));
    } on Object catch (failure) {
      if (mounted) _showMessage('Could not open the picker: $failure');
      return;
    }

    final file = picked?.files.singleOrNull;
    if (file?.bytes == null || !mounted) return;

    setState(() => _uploading = true);
    final controller = PrivioScope.of(context).conversations;
    final ok = await controller.setOwnAvatar(file!.bytes!);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (!ok) _showMessage(controller.error ?? 'Could not set the picture');
  }

  Future<void> _removeAvatar() async {
    await PrivioScope.of(context).conversations.removeOwnAvatar();
    if (mounted) setState(() {});
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = PrivioScope.of(context).username ?? 'privio_user';
    final accountId = PrivioScope.of(context).accountId;
    final ownAvatar = PrivioScope.of(context).conversations.ownAvatar;

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
                GestureDetector(
                  onTap: _uploading ? null : _pickAvatar,
                  onLongPress: ownAvatar == null ? null : _removeAvatar,
                  child: Stack(
                    children: [
                      PrivioAvatar(
                        label: username,
                        size: 88,
                        seed: 3,
                        imageBytes: ownAvatar,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: PrivioColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: _uploading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: PrivioColors.background,
                                  ),
                                )
                              : const Icon(
                                  Icons.photo_camera_rounded,
                                  size: 14,
                                  color: PrivioColors.background,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PrivioSpacing.md),
                Text(username, style: theme.textTheme.titleLarge),
                Text('@$username', style: theme.textTheme.bodySmall),
                const SizedBox(height: PrivioSpacing.xs),
                Text(
                  ownAvatar == null
                      ? 'Tap to add a picture'
                      : 'Encrypted — only your contacts can see it',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ownAvatar == null
                        ? PrivioColors.textTertiary
                        : PrivioColors.accent,
                  ),
                ),
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
              SettingsRow(
                icon: Icons.fingerprint_rounded,
                label: 'Account ID',
                value: accountId == null ? '—' : '${accountId.substring(0, 8)}…',
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          SettingsSection(
            children: [
              // Two rows that used to show invented numbers — "1.2 GB / 5 GB"
              // and "Security Level: High" — are gone rather than kept as
              // decoration. A figure nobody measured is worse than no figure,
              // and this one sat on a screen about trust.
              SettingsRow(
                icon: Icons.backup_outlined,
                label: 'Backup',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
                ),
              ),
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
