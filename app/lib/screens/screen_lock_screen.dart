import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/passcode_text.dart';
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
  /// What is wrong with what was typed — a case, not a sentence.
  _LockError? _error;

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
    final text = AppText.of(context);
    final complaint = _kind.complaintAbout(_passcode.text);
    if (complaint != null) {
      setState(() => _error = _LockError.passcode(complaint));
      return;
    }
    if (_passcode.text != _confirm.text) {
      setState(() => _error = const _LockError.mismatch());
      return;
    }
    setState(() => _error = null);
    await state.setScreenLock(_passcode.text, _kind);
    if (!mounted) return;
    _passcode.clear();
    _confirm.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.lockOnToast)),
    );
  }

  Future<void> _remove(AppState state) async {
    final text = AppText.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.lockTurnOffTitle),
        content: Text(text.lockTurnOffBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.twoFactorTurnOff),
          ),
        ],
      ),
    );
    if (!(yes ?? false) || !mounted) return;
    await state.clearScreenLock();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.lockOffToast)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.privacyScreenLock),
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
              state.screenLockSet ? text.commonOn : text.commonOff,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              text.lockWhatItIsNote,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              text.lockNoBiometricsNote,
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            if (state.screenLockSet) ...[
              const SizedBox(height: PrivioSpacing.lg),
              OutlinedButton(
                onPressed: () => _remove(state),
                style: OutlinedButton.styleFrom(foregroundColor: PrivioColors.danger),
                child: Text(text.lockTurnOffRow),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              const Divider(height: 1, color: PrivioColors.border),
              const SizedBox(height: PrivioSpacing.xl),
            ],
            Text(
              state.screenLockSet ? text.lockChangePasscode : text.lockChoosePasscode,
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
                      title: Text(
                        passcodeKindLabel(text, kind),
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        passcodeKindNote(text, kind),
                        style: theme.textTheme.labelSmall,
                      ),
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
              decoration: InputDecoration(
                hintText: passcodeKindLabel(text, _kind),
                counterText: '',
              ),
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
              decoration: InputDecoration(hintText: text.lockAgain, counterText: ''),
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
                      _error!.words(text),
                      style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: PrivioSpacing.xl),
            FilledButton(
              onPressed: () => _save(state),
              child: Text(state.screenLockSet ? text.lockChangeIt : text.lockTurnItOn),
            ),
            const SizedBox(height: PrivioSpacing.xxl),
            const Divider(height: 1, color: PrivioColors.border),
            const SizedBox(height: PrivioSpacing.lg),
            Text(
              text.lockForgettingNote,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// What is wrong with the entry, as a case the screen turns into words.
///
/// Two shapes: the passcode itself is the wrong kind, or the two fields do not
/// match. Both used to be stored as an English sentence.
class _LockError {
  const _LockError.passcode(this.complaint);
  const _LockError.mismatch() : complaint = null;

  final PasscodeComplaint? complaint;

  String words(AppText text) {
    final complaint = this.complaint;
    return complaint == null
        ? text.lockEntriesDiffer
        : passcodeComplaintText(text, complaint);
  }
}
