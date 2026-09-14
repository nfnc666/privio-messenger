import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../crypto/crypto_storage.dart';
import '../l10n/app_localizations.dart';
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
    final text = AppText.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.storageConfirmTitle),
        content: Text(text.storageConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.storageDeleteIt),
          ),
        ],
      ),
    );
    if (!(yes ?? false) || !mounted) return;

    await state.conversations.clearHistory();
    await _measure();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.storageDeleted)),
    );
  }

  /// Bytes as somebody reads them.
  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final history = _history;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsStorage),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PrivioColors.accent))
          : ListView(
              padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
              children: [
                SettingsSection(
                  caption: text.storageOnThisDevice,
                  children: [
                    SettingsRow(
                      label: text.storageHistory,
                      value: _size(history?.sealedBytes ?? 0),
                    ),
                    SettingsRow(
                      label: text.storageInIt,
                      value: text.storageChatsAndMessages(
                        history?.conversations ?? 0,
                        history?.messages ?? 0,
                      ),
                    ),
                    SettingsRow(
                      label: text.storageKeys,
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
                    text.storageKeystoreNote,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                SettingsSection(
                  caption: text.storageNotKept,
                  children: [
                    SettingsRow(
                      label: text.storageFilesOpened,
                      value: text.storageMemoryOnly,
                    ),
                    SettingsRow(
                      label: text.storageVoiceRecordings,
                      value: text.storageShredded,
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
                    text.storageEphemeralNote,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                SettingsSection(
                  caption: text.storageDelete,
                  children: [
                    SettingsRow(
                      label: text.storageDeleteHistory,
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
                    text.storageDeleteNote,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}
