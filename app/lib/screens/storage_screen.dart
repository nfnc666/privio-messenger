import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../crypto/crypto_storage.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// What this device is keeping, and what can be got rid of.
///
/// There was a "Data and Storage" row in Settings that opened nothing, and it
/// was removed rather than left as a dead end. This is what it needed: real
/// numbers, read from the things that hold them, and the one deletion Privio
/// can actually perform without destroying the account with it.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  ({int sealedBytes, int messages, int conversations})? _history;
  int? _keyBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_measure()));
  }

  Future<void> _measure() async {
    final state = PrivioScope.of(context);
    final history = await state.conversations.historySize();
    final keys = await state.services.crypto.store.storage.sizeInBytes();
    if (!mounted) return;
    setState(() {
      _history = history;
      _keyBytes = keys;
      _loading = false;
    });
  }

  Future<void> _confirmClear() async {
    final state = PrivioScope.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Delete the history on this device?'),
        content: const Text(
          'Every message on this phone goes, in every chat. Your account, your '
          'keys and your conversations stay: people can still write to you, and '
          'what you send after this still arrives.\n\n'
          'It cannot reach their copy, and it cannot reach a backup already on '
          'the server. Delete that from the Backup screen if you want it gone '
          'too.',
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
    if (!(yes ?? false) || !mounted) return;

    await state.conversations.clearHistory();
    await _measure();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The history on this device is gone.')),
    );
  }

  /// Bytes as somebody reads them.
  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _count(int n, String one, String many) =>
      n == 1 ? '1 $one' : '$n $many';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = _history;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: const Text('Data and Storage'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PrivioColors.accent))
          : ListView(
              padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
              children: [
                SettingsSection(
                  caption: 'On this device',
                  children: [
                    SettingsRow(
                      label: 'Conversation history',
                      value: _size(history?.sealedBytes ?? 0),
                    ),
                    SettingsRow(
                      label: 'In it',
                      value: '${_count(history?.conversations ?? 0, 'chat', 'chats')}, '
                          '${_count(history?.messages ?? 0, 'message', 'messages')}',
                    ),
                    SettingsRow(
                      label: 'Keys and sessions',
                      value: _size(_keyBytes ?? 0),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PrivioSpacing.lg,
                    PrivioSpacing.md,
                    PrivioSpacing.lg,
                    0,
                  ),
                  child: Text(
                    'Both sit in the platform keystore — the Keychain on iOS, '
                    'Keystore-backed storage on Android — and the history is '
                    'sealed with AES-256-GCM before it gets there. Neither is '
                    'readable by another app, and neither is readable by anyone '
                    'holding the phone without unlocking it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SettingsSection(
                  caption: 'Not kept',
                  children: [
                    SettingsRow(label: 'Files you opened', value: 'Memory only'),
                    SettingsRow(label: 'Voice recordings', value: 'Shredded when sent'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PrivioSpacing.lg,
                    PrivioSpacing.md,
                    PrivioSpacing.lg,
                    0,
                  ),
                  child: Text(
                    'A photo or file you open is decrypted into memory and goes '
                    'when the app closes; nothing writes it to disk. A voice '
                    'message is recorded to a temporary file, because the '
                    'microphone has to write somewhere, and that file is '
                    'overwritten with random bytes and deleted the moment the '
                    'recording ends — a deleted file on flash storage is not a '
                    'gone file.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                SettingsSection(
                  caption: 'Delete',
                  children: [
                    SettingsRow(
                      label: 'Delete history on this device',
                      destructive: true,
                      onTap: () => unawaited(_confirmClear()),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PrivioSpacing.lg,
                    PrivioSpacing.md,
                    PrivioSpacing.lg,
                    0,
                  ),
                  child: Text(
                    'This is the only deletion that happens here. What the '
                    'server holds — a backup, an attachment still inside its '
                    'thirty days — is on the Backup screen, and what the person '
                    'you wrote to has is theirs.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}
