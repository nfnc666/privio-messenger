import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/status_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/settings_row.dart';
import '../widgets/status_sheet.dart';
import 'backup_screen.dart';
import 'account_phone_screen.dart';
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
    final text = AppText.of(context);
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.image,
      ).timeout(const Duration(minutes: 2));
    } on Object catch (failure) {
      if (mounted) _showMessage(text.accountPickerFailed('$failure'));
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
      if (mounted) _showMessage(text.accountCouldNotReadFile(picked.name, '$failure'));
      return;
    }
    if (!mounted) return;

    setState(() => _uploading = true);
    final controller = PrivioScope.of(context).conversations;
    final ok = await controller.setOwnAvatar(bytes);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (!ok) _showMessage(controller.failure?.words(text) ?? text.accountCouldNotSetPicture);
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
    final text = AppText.of(context);
    final username = PrivioScope.of(context).username ?? 'privio_user';
    final accountId = PrivioScope.of(context).accountId;
    final ownAvatar = PrivioScope.of(context).conversations.ownAvatar;

    return Scaffold(
      appBar: AppBar(
        title: Text(text.navAccount),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
            tooltip: text.settingsTitle,
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
                          decoration: BoxDecoration(
                            color: context.accents.accent,
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
                      ? text.accountTapToAddPicture
                      : text.accountPictureEncrypted,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ownAvatar == null
                        ? PrivioColors.textTertiary
                        : context.accents.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PrivioSpacing.xxl),
          SettingsSection(
            children: [
              SettingsRow(
                icon: Icons.alternate_email_rounded,
                label: text.accountUsername,
                value: username,
              ),
              // The row used to show `accountStatusDefault` — one hardcoded
              // English sentence, the same for every user, stored nowhere and
              // settable by nobody. It is a real value now, and it opens the
              // sheet that sets it.
              ListenableBuilder(
                listenable: PrivioScope.of(context).profileStatus,
                builder: (context, _) {
                  final controller = PrivioScope.of(context).profileStatus;
                  return SettingsRow(
                    icon: Icons.mood_rounded,
                    label: text.accountStatus,
                    // Nothing at all until the server has answered. A row that
                    // said "Not set" before the read came back would say it to
                    // somebody who has one.
                    value: controller.loaded ? _statusValue(text, controller.status) : null,
                    subtitle: _statusExpiry(context, controller.status),
                    onTap: () => showStatusSheet(context, controller),
                  );
                },
              ),
              SettingsRow(
                icon: Icons.fingerprint_rounded,
                label: text.accountId,
                // `substring(0, 8)` on anything shorter than eight characters
                // throws, and it took the whole screen down with it. Real ids
                // are 36-character UUIDs so it never fired in a release — but a
                // screen that crashes on a short id is a screen that crashes on
                // whatever the server sends next.
                value: accountId == null ? '—' : _shortId(accountId),
              ),
              SettingsRow(
                icon: Icons.phone_outlined,
                label: text.phoneFieldLabel,
                subtitle: text.accountPhoneNote,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountPhoneScreen())),
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
                label: text.settingsBackup,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
                ),
              ),
              SettingsRow(
                icon: Icons.qr_code_rounded,
                label: text.accountInviteRow,
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
                label: text.accountLogOut,
                destructive: true,
                onTap: () => _confirmSignOut(context),
              ),
              // The server has been able to do this since the first migration
              // and nothing in the app could ask for it. An account you cannot
              // end is not an account you own.
              SettingsRow(
                label: text.accountDelete,
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
    final text = AppText.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.accountDeleteTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text.accountDeleteBody),
            const SizedBox(height: PrivioSpacing.lg),
            TextField(
              controller: password,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(labelText: text.accountYourPassword),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.accountDeleteIt),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;

    final failure = await state.deleteAccount(password.text);
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failure.words(AppText.of(context)))),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(AppText.of(dialogContext).accountLogOutQuestion),
        content: Text(AppText.of(dialogContext).accountLogOutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppText.of(dialogContext).commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              PrivioScope.of(context).signOut();
            },
            style: TextButton.styleFrom(foregroundColor: PrivioColors.danger),
            child: Text(AppText.of(dialogContext).accountLogOut),
          ),
        ],
      ),
    );
  }
}

/// The first few characters of an account id, for a row that only has to be
/// recognisable rather than complete.
String _shortId(String accountId) =>
    accountId.length <= 8 ? accountId : '${accountId.substring(0, 8)}…';

/// The row's value: the emoji and the line, or the words for having neither.
String _statusValue(AppText text, ProfileStatus status) {
  if (!status.isSet) return text.accountStatusNone;
  final line = status.text;
  final emoji = status.emoji;
  if (emoji == null) return line ?? text.accountStatusNone;
  return line == null || line.isEmpty ? emoji : '$emoji  $line';
}

/// When it clears, or null when it does not.
///
/// Read against the clock each build, so a sheet closed at 16:59 with "1 hour"
/// on it stops showing the line at 17:59 without anything having to be told.
String? _statusExpiry(BuildContext context, ProfileStatus status) {
  final at = status.expiresAt;
  if (!status.isSet || at == null) return null;
  return AppText.of(context).accountStatusUntil(TimeOfDay.fromDateTime(at).format(context));
}
