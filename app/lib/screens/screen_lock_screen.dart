import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../theme/privio_colors.dart';
import '../widgets/settings_row.dart';

/// The app lock: a PIN on this device, and biometrics as the shortcut.
///
/// `AppStage.locked` and the PIN pad have existed since the first screens were
/// built, and nothing ever called `setPin`, so the lock could never come on.
/// This is where it does.
class ScreenLockScreen extends StatefulWidget {
  const ScreenLockScreen({super.key});

  static const int pinLength = 4;

  @override
  State<ScreenLockScreen> createState() => _ScreenLockScreenState();
}

class _ScreenLockScreenState extends State<ScreenLockScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _biometrics = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final enabled = await PrivioScope.of(context).screenLockUsesBiometrics();
      if (mounted) setState(() => _biometrics = enabled);
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save(AppState state) async {
    if (_pin.text.length != ScreenLockScreen.pinLength) {
      setState(() => _error = 'The PIN is ${ScreenLockScreen.pinLength} digits.');
      return;
    }
    if (_pin.text != _confirm.text) {
      setState(() => _error = 'The two PINs are not the same.');
      return;
    }
    setState(() => _error = null);
    await state.setScreenLock(_pin.text);
    if (!mounted) return;
    _pin.clear();
    _confirm.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('App lock on. Privio asks for it when it comes back.')),
    );
  }

  Future<void> _remove(AppState state) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Turn off the app lock?'),
        content: const Text(
          'Anyone holding an unlocked phone reaches your messages. A duress code '
          'set for the lock screen is removed with it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (!(yes ?? false) || !mounted) return;
    await state.clearScreenLock();
    if (!mounted) return;
    setState(() => _biometrics = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('App lock off.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Screen Lock')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.xxl,
            PrivioSpacing.xl,
            PrivioSpacing.xxl,
            PrivioSpacing.xxxl,
          ),
          children: [
            Text(
              state.screenLockSet ? 'On' : 'Off',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              'A PIN on this device, asked for whenever Privio comes back to the '
              'foreground. It is not your account password and it never leaves the '
              'phone — it guards the history already encrypted on it.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            if (state.screenLockSet && state.biometricsAvailable)
              SettingsRow(
                label: 'Unlock with biometrics',
                trailing: Switch(
                  value: _biometrics,
                  onChanged: (value) async {
                    setState(() => _biometrics = value);
                    await state.setScreenLockBiometrics(value);
                  },
                ),
              ),
            if (state.screenLockSet) ...[
              const SizedBox(height: PrivioSpacing.lg),
              OutlinedButton(
                onPressed: () => _remove(state),
                style: OutlinedButton.styleFrom(foregroundColor: PrivioColors.danger),
                child: const Text('Turn off the app lock'),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              const Divider(height: 1, color: PrivioColors.border),
              const SizedBox(height: PrivioSpacing.xl),
            ],
            Text(
              state.screenLockSet ? 'Change the PIN' : 'Set a PIN',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: PrivioSpacing.lg),
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: ScreenLockScreen.pinLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(hintText: 'PIN', counterText: ''),
            ),
            const SizedBox(height: PrivioSpacing.md),
            TextField(
              controller: _confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: ScreenLockScreen.pinLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(state),
              decoration: const InputDecoration(hintText: 'PIN again', counterText: ''),
            ),
            if (_error != null) ...[
              const SizedBox(height: PrivioSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: PrivioColors.danger),
                  const SizedBox(width: PrivioSpacing.sm),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: PrivioSpacing.xl),
            FilledButton(
              onPressed: () => _save(state),
              child: Text(state.screenLockSet ? 'Change it' : 'Turn it on'),
            ),
            const SizedBox(height: PrivioSpacing.xxl),
            const Divider(height: 1, color: PrivioColors.border),
            const SizedBox(height: PrivioSpacing.lg),
            Text(
              'Forgetting this PIN means signing in again, which is a new device to '
              'the server: what was already delivered here is gone unless it is in a '
              'backup. There is no reset, because a reset anyone could ask for would '
              'not be a lock.',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
