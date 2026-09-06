import 'dart:async';
import 'dart:typed_data';

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
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.image,
      ).timeout(const Duration(minutes: 2));
    } on Object catch (failure) {
      if (mounted) _showMessage('Could not open the picker: $failure');
      return;
    }
    if (picked == null || !mounted) return;

    // The bytes are read here rather than by the picker, which is the shape the
    // package moved to. Reading can fail on its own — a file the picker listed
    // and the app then cannot open — so it gets its own message.
    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object catch (failure) {
      if (mounted) _showMessage('Could not read ${picked.name}: $failure');
      return;
    }
    if (!mounted) return;

    setState(() => _uploading = true);
    final controller = PrivioScope.of(context).conversations;
    final ok = await controller.setOwnAvatar(bytes);
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
              // The server has been able to do this since the first migration
              // and nothing in the app could ask for it. An account you cannot
              // end is not an account you own.
              SettingsRow(
                label: 'Delete account',
                destructive: true,
                onTap: () => unawaited(_confirmDelete(context)),
              ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.xxxl),
        ],
      ),
    );
  }

  /// Asks for the password, because the server does, and says what goes.
  Future<void> _confirmDelete(BuildContext context) async {
    final state = PrivioScope.of(context);
    final password = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Delete this account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your devices, your keys, the messages still waiting to be '
              'delivered, your contacts, your group memberships and your '
              'backup are all deleted on the server. Everything on this phone '
              'goes with them.\n\n'
              'It cannot reach what other people have already received, and '
              'your username becomes free for somebody else to take.\n\n'
              'There is no undo and no recovery — not with the recovery key, '
              'not by writing to anybody.',
            ),
            const SizedBox(height: PrivioSpacing.lg),
            TextField(
              controller: password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Your password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete it'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;

    final failure = await state.deleteAccount(password.text);
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
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
