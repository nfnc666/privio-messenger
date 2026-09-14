import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/channel_text.dart';
import '../data/recovery_key.dart';
import '../services/backup_service.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// End-to-end encrypted backup.
///
/// Everything on this screen is real: the times, the sizes and the key are read
/// from the device and the server rather than written into the layout. A backup
/// screen that shows a comforting "Last backup: today" it did not measure is
/// worse than one that admits there is no backup.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  DateTime? _lastBackup;
  RemoteBackup? _remote;
  BackupInterval _interval = BackupInterval.weekly;
  bool _loading = true;
  bool _working = false;
  /// What went wrong, as a case rather than a sentence — the sentence is built
  /// where it is drawn, in the reader's language.
  _BackupError? _error;

  BackupService get _backup => PrivioScope.of(context).services.backup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final last = await _backup.lastBackupAt();
      final interval = await _backup.interval();
      final remote = await _backup.remote();
      if (!mounted) return;
      setState(() {
        _lastBackup = last;
        _interval = interval;
        _remote = remote;
        _loading = false;
        _error = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _BackupError.couldNotReach;
      });
    }
  }

  Future<void> _backUpNow() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _backup.backUpNow();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppText.of(context).backupDone)),
        );
      }
    } on Object {
      if (mounted) setState(() => _error = _BackupError.uploadFailed);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _chooseInterval() async {
    final chosen = await showModalBottomSheet<BackupInterval>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in BackupInterval.values)
              ListTile(
                title: Text(_intervalLabel(AppText.of(sheetContext), option)),
                trailing: option == _interval
                    ? const Icon(Icons.check_rounded, color: PrivioColors.accent)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await _backup.setInterval(chosen);
    if (mounted) setState(() => _interval = chosen);
  }

  Future<void> _showRecoveryKey() async {
    final key = await _backup.recoveryKey();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _RecoveryKeyDialog(recoveryKey: key),
    );
  }

  Future<void> _restore() async {
    final text = AppText.of(context);
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const _EnterKeyDialog(),
    );
    if (entered == null || !mounted) return;

    final key = BackupService.parseScanned(entered);
    if (key == null) {
      setState(() => _error = _BackupError.badKey);
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final contents = await _backup.restoreFromServer(key);
      if (!mounted) return;
      await PrivioScope.of(context).conversations.adoptRestored();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text.backupRestored(contents.conversations.length)),
        ),
      );
    } on Object {
      if (mounted) {
        setState(
          () => _error = _BackupError.keyDidNotOpen,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsBackup),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
              children: [
                const SizedBox(height: PrivioSpacing.xl),
                Center(
                  child: Icon(
                    _remote == null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                    size: 64,
                    color: _remote == null ? PrivioColors.textTertiary : PrivioColors.accent,
                  ),
                ),
                const SizedBox(height: PrivioSpacing.xl),
                SettingsSection(
                  children: [
                    SettingsRow(label: text.backupLast, value: _formatLast(text)),
                    SettingsRow(
                      label: text.backupOnServer,
                      value: _remote == null ? text.backupNothingYet : _remote!.readableSize,
                    ),
                    SettingsRow(label: text.chatEncrypted, value: text.backupAlways),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PrivioSpacing.gutter,
                      PrivioSpacing.md,
                      PrivioSpacing.gutter,
                      0,
                    ),
                    child: Text(
                      _errorText(text, _error!),
                      style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                    ),
                  ),
                const SizedBox(height: PrivioSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                  child: FilledButton(
                    onPressed: _working ? null : _backUpNow,
                    child: _working
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(text.backupNow),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.lg),
                SettingsSection(
                  children: [
                    SettingsRow(
                      label: text.backupAutomatic,
                      value: _intervalLabel(text, _interval),
                      onTap: _chooseInterval,
                    ),
                    SettingsRow(label: text.backupRecoveryKey, onTap: _showRecoveryKey),
                    SettingsRow(
                      label: text.backupRestoreRow,
                      onTap: _working ? null : _restore,
                    ),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
                  child: Text(
                    text.backupSealedNote,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }

  String _formatLast(AppText text) {
    final last = _lastBackup;
    if (last == null) return text.backupNever;
    final now = DateTime.now();
    final sameDay = last.year == now.year && last.month == now.month && last.day == now.day;
    final time = '${last.hour.toString().padLeft(2, '0')}:'
        '${last.minute.toString().padLeft(2, '0')}';
    if (sameDay) return text.backupToday(time);
    return '${formatDate(text, last)}, $time';
  }
}

/// Shows the key once, as text and as a QR code.
///
/// The QR is how a second device gets it without anyone typing 52 characters
/// on a phone keyboard — and it is generated here, on the device, from a key
/// that has never been anywhere else.
class _RecoveryKeyDialog extends StatelessWidget {
  const _RecoveryKeyDialog({required this.recoveryKey});

  final RecoveryKey recoveryKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: Text(AppText.of(context).backupRecoveryKey),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(PrivioSpacing.md),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(PrivioRadius.card),
                ),
                child: QrImageView(
                  data: BackupService.qrPayload(recoveryKey),
                  size: 160,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: PrivioSpacing.lg),
            SelectableText(
              recoveryKey.formatted,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              AppText.of(context).backupWriteItDown,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppText.of(context).commonClose),
        ),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: recoveryKey.formatted));
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(AppText.of(context).commonCopy),
        ),
      ],
    );
  }
}

class _EnterKeyDialog extends StatefulWidget {
  const _EnterKeyDialog();

  @override
  State<_EnterKeyDialog> createState() => _EnterKeyDialogState();
}

class _EnterKeyDialogState extends State<_EnterKeyDialog> {
  final TextEditingController _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: Text(AppText.of(context).backupRestoreRow),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _key,
            autofocus: true,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX-…'),
          ),
          const SizedBox(height: PrivioSpacing.md),
          Text(
            AppText.of(context).backupRestoreReplacesNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppText.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_key.text),
          child: Text(AppText.of(context).backupRestore),
        ),
      ],
    );
  }
}

/// What can go wrong on this screen. Four cases, and none of them is a
/// sentence until the screen draws it.
enum _BackupError { couldNotReach, uploadFailed, badKey, keyDidNotOpen }

String _errorText(AppText text, _BackupError failure) => switch (failure) {
      _BackupError.couldNotReach => text.backupCouldNotReach,
      _BackupError.uploadFailed => text.backupUploadFailed,
      _BackupError.badKey => text.backupBadKey,
      _BackupError.keyDidNotOpen => text.backupKeyDidNotOpen,
    };

/// How often, in the reader's language.
String _intervalLabel(AppText text, BackupInterval interval) => switch (interval) {
      BackupInterval.off => text.commonOff,
      BackupInterval.daily => text.backupIntervalDaily,
      BackupInterval.weekly => text.backupIntervalWeekly,
    };
