import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_state.dart';
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
  String? _error;

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
        _error = 'Could not reach Privio to check the backup.';
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
          const SnackBar(content: Text('Backed up. Privio cannot read it.')),
        );
      }
    } on Object {
      if (mounted) setState(() => _error = 'The backup could not be uploaded.');
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
                title: Text(option.label),
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
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const _EnterKeyDialog(),
    );
    if (entered == null || !mounted) return;

    final key = BackupService.parseScanned(entered);
    if (key == null) {
      setState(() => _error = 'That does not look like a recovery key.');
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
          content: Text(
            'Restored ${contents.conversations.length} conversation'
            '${contents.conversations.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'That key did not open the backup, or there is none to open.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: const Text('Backup'),
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
                    SettingsRow(label: 'Last backup', value: _formatLast()),
                    SettingsRow(
                      label: 'On the server',
                      value: _remote == null ? 'Nothing yet' : _remote!.readableSize,
                    ),
                    const SettingsRow(label: 'End-to-end encrypted', value: 'Always'),
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
                      _error!,
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
                        : const Text('Back up now'),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.lg),
                SettingsSection(
                  children: [
                    SettingsRow(
                      label: 'Automatic backup',
                      value: _interval.label,
                      onTap: _chooseInterval,
                    ),
                    SettingsRow(label: 'Recovery key', onTap: _showRecoveryKey),
                    SettingsRow(label: 'Restore from backup', onTap: _working ? null : _restore),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
                  child: Text(
                    'Backups are sealed on this device with your recovery key. Privio '
                    'cannot open them and cannot reset the key — if you lose it, the '
                    'backup is gone. Write it down somewhere safe.\n\n'
                    'A backup holds your conversations, not your keys: restoring on a '
                    'new device gives you your history, and that device sets up its '
                    'own identity for what comes next.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }

  String _formatLast() {
    final last = _lastBackup;
    if (last == null) return 'Never';
    final now = DateTime.now();
    final sameDay = last.year == now.year && last.month == now.month && last.day == now.day;
    final time = '${last.hour.toString().padLeft(2, '0')}:'
        '${last.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'Today, $time';
    return '${last.day.toString().padLeft(2, '0')}.'
        '${last.month.toString().padLeft(2, '0')}.${last.year}, $time';
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
      title: const Text('Recovery key'),
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
              'Write this down. It is the only thing that opens your backups, '
              'and nobody — including Privio — can produce it again for you.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: recoveryKey.formatted));
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Copy'),
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
      title: const Text('Restore from backup'),
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
            'This replaces whatever is on this device with what is in the backup.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_key.text),
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
