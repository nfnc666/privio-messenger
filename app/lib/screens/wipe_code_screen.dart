import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/security_controller.dart';
import '../theme/privio_colors.dart';

/// The duress code: a second password that destroys the account instead of
/// opening it, and that looks from the outside exactly like a typo.
///
/// The server has had this since the first migration. It has never had a screen,
/// which meant the one feature written for someone being forced to hand over a
/// phone could only be armed with a curl command.
class WipeCodeScreen extends StatefulWidget {
  const WipeCodeScreen({super.key});

  @override
  State<WipeCodeScreen> createState() => _WipeCodeScreenState();
}

class _WipeCodeScreenState extends State<WipeCodeScreen> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  String? _localError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PrivioScope.of(context).security.load();
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _clearErrors(SecurityController security) {
    if (_localError != null) setState(() => _localError = null);
    security.clearError();
  }

  Future<void> _save(SecurityController security) async {
    // Checked here rather than at the server, because a mistyped duress code is
    // one you find out about at the worst possible moment.
    if (_code.text.length < 4) {
      setState(() => _localError = 'Use at least four characters.');
      return;
    }
    if (_code.text != _confirm.text) {
      setState(() => _localError = 'The two codes are not the same.');
      return;
    }
    setState(() => _localError = null);

    final ok = await security.setWipeCode(
      currentPassword: _password.text,
      wipeCode: _code.text,
    );
    if (!ok || !mounted) return;
    _password.clear();
    _code.clear();
    _confirm.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wipe code set. Typing it at sign-in destroys the account.')),
    );
  }

  Future<void> _remove(SecurityController security) async {
    final password = await _askForPassword();
    if (password == null || !mounted) return;
    final ok = await security.setWipeCode(currentPassword: password, wipeCode: null);
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wipe code removed.')),
    );
  }

  Future<String?> _askForPassword() {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Remove the wipe code'),
        content: TextField(
          controller: field,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Your password'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            child: const Text('Remove'),
          ),
        ],
      ),
    ).whenComplete(field.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final security = PrivioScope.of(context).security;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Wipe Code')),
      body: ListenableBuilder(
        listenable: security,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.xxl,
            PrivioSpacing.xl,
            PrivioSpacing.xxl,
            PrivioSpacing.xxxl,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(PrivioSpacing.lg),
              decoration: BoxDecoration(
                color: PrivioColors.surfaceRaised,
                borderRadius: const BorderRadius.all(PrivioRadius.card),
                border: Border.all(color: PrivioColors.danger.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: PrivioColors.danger),
                  const SizedBox(width: PrivioSpacing.md),
                  Expanded(
                    child: Text(
                      'Typing this code instead of your password at sign-in destroys the '
                      'account: every device, every message still waiting, your contacts, '
                      'your group memberships, your backup. There is no undo, and no '
                      'confirmation — that is the point.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PrivioSpacing.xl),
            if (security.wipeCodeSet) ...[
              Text('A wipe code is set', style: theme.textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                'Privio cannot show it to you — it is stored the way a password is. '
                'Setting a new one below replaces it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: PrivioSpacing.lg),
              OutlinedButton(
                onPressed: security.busy ? null : () => _remove(security),
                style: OutlinedButton.styleFrom(foregroundColor: PrivioColors.danger),
                child: const Text('Remove it'),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              const Divider(height: 1, color: PrivioColors.border),
              const SizedBox(height: PrivioSpacing.xl),
            ],
            Text(
              security.wipeCodeSet ? 'Replace it' : 'Set a wipe code',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: PrivioSpacing.lg),
            // Editing clears the last complaint. Leaving it up would also leave
            // the button moved down the screen, under wherever the finger that
            // pressed it last is expecting it.
            TextField(
              controller: _password,
              obscureText: true,
              enabled: !security.busy,
              onChanged: (_) => _clearErrors(security),
              decoration: const InputDecoration(hintText: 'Your password'),
            ),
            const SizedBox(height: PrivioSpacing.md),
            TextField(
              controller: _code,
              obscureText: true,
              enabled: !security.busy,
              onChanged: (_) => _clearErrors(security),
              decoration: const InputDecoration(hintText: 'Wipe code'),
            ),
            const SizedBox(height: PrivioSpacing.md),
            TextField(
              controller: _confirm,
              obscureText: true,
              enabled: !security.busy,
              onChanged: (_) => _clearErrors(security),
              onSubmitted: (_) => _save(security),
              decoration: const InputDecoration(hintText: 'Wipe code again'),
            ),
            if (_localError != null || security.error != null) ...[
              const SizedBox(height: PrivioSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: PrivioColors.danger),
                  const SizedBox(width: PrivioSpacing.sm),
                  Expanded(
                    child: Text(
                      _localError ?? security.error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: PrivioSpacing.xl),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
              onPressed: security.busy ? null : () => _save(security),
              child: security.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: PrivioColors.textPrimary,
                      ),
                    )
                  : Text(security.wipeCodeSet ? 'Replace the code' : 'Set the code'),
            ),
            const SizedBox(height: PrivioSpacing.xxl),
            const Divider(height: 1, color: PrivioColors.border),
            const SizedBox(height: PrivioSpacing.lg),
            Text(
              'What it does not do: the account name stays taken, so nobody can claim '
              'it afterwards, and it cannot reach a device that is already signed in '
              'somewhere else — the wipe happens when the code is used to sign in. '
              'Anyone watching sees the sign-in refused exactly as a mistyped password '
              'is refused.',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
