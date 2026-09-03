import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/passcode.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';

/// The app lock: a passcode on this device, in one of three shapes.
///
/// There is no face or fingerprint option, and that is deliberate. Biometrics
/// are the one credential a person can be made to present while unwilling or
/// unconscious, and in several jurisdictions compelled by an order that could
/// not compel a passcode. For an app whose duress code exists for exactly that
/// situation, offering one would undo the other.
class ScreenLockScreen extends StatefulWidget {
  const ScreenLockScreen({super.key});

  @override
  State<ScreenLockScreen> createState() => _ScreenLockScreenState();
}

class _ScreenLockScreenState extends State<ScreenLockScreen> {
  final _passcode = TextEditingController();
  final _confirm = TextEditingController();
  PasscodeKind _kind = PasscodeKind.digits4;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = PrivioScope.of(context).passcodeKind;
      if (current != null) setState(() => _kind = current);
    });
  }

  @override
  void dispose() {
    _passcode.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _chooseKind(PasscodeKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _error = null;
      // What was typed cannot be the new shape, and silently keeping it would
      // let someone press the button on a passcode they thought they cleared.
      _passcode.clear();
      _confirm.clear();
    });
  }

  Future<void> _save(AppState state) async {
    final complaint = _kind.complaintAbout(_passcode.text);
    if (complaint != null) {
      setState(() => _error = complaint);
      return;
    }
    if (_passcode.text != _confirm.text) {
      setState(() => _error = 'The two entries are not the same.');
      return;
    }
    setState(() => _error = null);
    await state.setScreenLock(_passcode.text, _kind);
    if (!mounted) return;
    _passcode.clear();
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('App lock off.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: const Text('Screen Lock'),
      ),
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
              'A passcode on this device, asked for whenever Privio comes back to '
              'the foreground. It is not your account password and it never leaves '
              'the phone — it guards the history already encrypted on it.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              'There is no face or fingerprint option. Those are the one credential '
              'someone can hold a phone up to your face to use, or press your finger '
              'onto while you are asleep — and in several places a court can order '
              'them where it cannot order a passcode.',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: PrivioSpacing.xl),
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
              state.screenLockSet ? 'Change the passcode' : 'Choose a passcode',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: PrivioSpacing.lg),
            RadioGroup<PasscodeKind>(
              groupValue: _kind,
              onChanged: (chosen) => _chooseKind(chosen ?? _kind),
              child: Column(
                children: [
                  for (final kind in PasscodeKind.values)
                    RadioListTile<PasscodeKind>(
                      value: kind,
                      activeColor: PrivioColors.accent,
                      contentPadding: EdgeInsets.zero,
                      title: Text(kind.label, style: theme.textTheme.bodyMedium),
                      subtitle: Text(kind.description, style: theme.textTheme.labelSmall),
                    ),
                ],
              ),
            ),
            const SizedBox(height: PrivioSpacing.lg),
            TextField(
              controller: _passcode,
              obscureText: true,
              keyboardType: _kind.isNumeric ? TextInputType.number : TextInputType.text,
              maxLength: _kind.length,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters:
                  _kind.isNumeric ? [FilteringTextInputFormatter.digitsOnly] : const [],
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(hintText: _kind.label, counterText: ''),
            ),
            const SizedBox(height: PrivioSpacing.md),
            TextField(
              controller: _confirm,
              obscureText: true,
              keyboardType: _kind.isNumeric ? TextInputType.number : TextInputType.text,
              maxLength: _kind.length,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters:
                  _kind.isNumeric ? [FilteringTextInputFormatter.digitsOnly] : const [],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(state),
              decoration: const InputDecoration(hintText: 'Again', counterText: ''),
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
              'Forgetting it means signing in again, which is a new device to '
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
