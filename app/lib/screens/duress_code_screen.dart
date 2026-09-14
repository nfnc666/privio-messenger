import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/passcode_text.dart';
import '../core/security_controller.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';

/// The duress code: a second password that destroys the account instead of
/// opening it, and that looks from the outside exactly like a typo.
///
/// The server has had this since the first migration. It went without a screen
/// for just as long, which meant the one feature written for someone being
/// forced to hand over a phone could only be armed with a curl command.
class DuressCodeScreen extends StatefulWidget {
  const DuressCodeScreen({super.key});

  @override
  State<DuressCodeScreen> createState() => _DuressCodeScreenState();
}

class _DuressCodeScreenState extends State<DuressCodeScreen> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  /// What is wrong with what was typed, as a case rather than a sentence.
  _DuressError? _localError;

  /// Whether what has been typed into the password field is too short to be an
  /// account password. Sign-up has required ten characters since before this
  /// screen existed, so anything shorter is far more likely to be the app-lock
  /// PIN — which is the mistake this screen invites by asking for "a password"
  /// on a device that is unlocked with four digits.
  bool get _looksLikeAPin => _password.text.isNotEmpty && _password.text.length < 10;

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

  /// Whether a code of this shape can also be entered at the lock screen.
  ///
  /// The lock screen only accepts what its own passcode looks like — four
  /// digits, six digits, or a passphrase — so a code of any other shape has
  /// nowhere to be typed there. Saying which one you have is better than
  /// letting someone believe a code is armed on a screen it can never reach.
  static bool _worksAtTheLockScreen(String code, AppState state) {
    final kind = state.passcodeKind;
    return state.screenLockSet && kind != null && kind.accepts(code);
  }

  String _lockScreenNote(AppText text, AppState state) {
    final kind = state.passcodeKind;
    if (!state.screenLockSet || kind == null) return text.duressNoLockNote;
    final shape = passcodeKindLabel(text, kind).toLowerCase();
    final code = _code.text;
    if (code.isEmpty) return text.duressShapeNote(shape);
    return _worksAtTheLockScreen(code, state)
        ? text.duressMatchesLock
        : text.duressDoesNotMatchLock(shape);
  }

  void _clearErrors(SecurityController security) {
    // Also redraws the note under the fields, which says whether a code of this
    // shape reaches the lock screen.
    setState(() => _localError = null);
    security.clearError();
  }

  Future<void> _save(SecurityController security) async {
    // Checked here rather than at the server, because a mistyped duress code is
    // one you find out about at the worst possible moment.
    if (_code.text.length < 4) {
      setState(() => _localError = _DuressError.tooShort);
      return;
    }
    if (_code.text != _confirm.text) {
      setState(() => _localError = _DuressError.codesDiffer);
      return;
    }
    setState(() => _localError = null);

    final state = PrivioScope.of(context);
    final code = _code.text;

    // The lock screen checks the duress code before the passcode, on purpose.
    // So a duress code equal to the unlock code makes every unlock a wipe — and
    // the wipe is silent by design, which leaves "my code stopped working" as
    // the only sign that an account has just been destroyed. Refused here, at
    // the one moment it can still be refused.
    if (state.screenLockSet && await state.isScreenLockPasscode(code)) {
      if (!mounted) return;
      setState(() => _localError = _DuressError.sameAsUnlock);
      return;
    }
    if (!mounted) return;

    final ok = await security.setDuressCode(
      currentPassword: _password.text,
      duressCode: code,
    );
    if (!ok || !mounted) return;

    // Only what the server has just accepted is kept here, and only so the lock
    // screen can recognise it with no network.
    await state.rememberDuressCode(code);
    if (!mounted) return;

    _password.clear();
    _code.clear();
    _confirm.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _worksAtTheLockScreen(code, state)
              ? AppText.of(context).duressSetBoth
              : AppText.of(context).duressSetSignInOnly,
        ),
      ),
    );
  }

  Future<void> _remove(SecurityController security) async {
    final password = await _askForPassword();
    if (password == null || !mounted) return;
    final state = PrivioScope.of(context);
    final ok = await security.setDuressCode(currentPassword: password, duressCode: null);
    if (!ok || !mounted) return;
    await state.rememberDuressCode(null);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppText.of(context).duressRemoved)),
    );
  }

  Future<String?> _askForPassword() {
    final text = AppText.of(context);
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.duressRemoveTitle),
        content: TextField(
          controller: field,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(hintText: text.accountYourPassword),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            child: Text(text.commonRemove),
          ),
        ],
      ),
    ).whenComplete(field.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final security = state.security;
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.privacyDuressCode),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([state, security]),
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
                      text.duressWarning,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PrivioSpacing.xl),
            if (security.duressCodeSet) ...[
              Text(text.duressIsSet, style: theme.textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                text.duressCannotShow,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: PrivioSpacing.lg),
              OutlinedButton(
                onPressed: security.busy ? null : () => _remove(security),
                style: OutlinedButton.styleFrom(foregroundColor: PrivioColors.danger),
                child: Text(text.duressRemoveIt),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              const Divider(height: 1, color: PrivioColors.border),
              const SizedBox(height: PrivioSpacing.xl),
            ],
            Text(
              security.duressCodeSet ? text.duressReplaceIt : text.duressSetOne,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: PrivioSpacing.lg),
            // Editing clears the last complaint. Leaving it up would also leave
            // the button moved down the screen, under wherever the finger that
            // pressed it last is expecting it.
            // "Your password" is ambiguous on a phone that unlocks with a
            // four-digit PIN, and the app-lock PIN is the wrong answer here.
            // Naming the account is what tells the two apart.
            TextField(
              controller: _password,
              obscureText: true,
              enabled: !security.busy,
              onChanged: (_) => _clearErrors(security),
              decoration: InputDecoration(hintText: text.duressAccountPassword),
            ),
            // Said before the request rather than after it. The server's answer
            // to a PIN typed here is "That password is not right", which is true
            // and unhelpful — and it costs one of ten attempts in five minutes,
            // so a few confused tries end in a rate limit on top.
            //
            // A note, not a block: sign-up has required ten characters for a
            // while, but an account made before that can have a shorter one and
            // must still be able to set a duress code.
            if (_looksLikeAPin) ...[
              const SizedBox(height: PrivioSpacing.xs),
              Text(
                text.duressLooksLikePin,
                style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
              ),
            ],
            const SizedBox(height: PrivioSpacing.md),
            TextField(
              controller: _code,
              obscureText: true,
              enabled: !security.busy,
              onChanged: (_) => _clearErrors(security),
              decoration: InputDecoration(hintText: text.duressCodeField),
            ),
            const SizedBox(height: PrivioSpacing.md),
            TextField(
              controller: _confirm,
              obscureText: true,
              enabled: !security.busy,
              onChanged: (_) => _clearErrors(security),
              onSubmitted: (_) => _save(security),
              decoration: InputDecoration(hintText: text.duressCodeAgain),
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
                      _localError == null
                          ? security.error!
                          : _duressErrorText(text, _localError!),
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
                  : Text(
                      security.duressCodeSet
                          ? text.duressReplaceCode
                          : text.duressSetCode,
                    ),
            ),
            const SizedBox(height: PrivioSpacing.xxl),
            const Divider(height: 1, color: PrivioColors.border),
            const SizedBox(height: PrivioSpacing.lg),
            Text(
              _lockScreenNote(text, state),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              text.duressWhatItDoesNotDo,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// What is wrong with a duress code somebody typed here.
enum _DuressError { tooShort, codesDiffer, sameAsUnlock }

String _duressErrorText(AppText text, _DuressError failure) => switch (failure) {
      _DuressError.tooShort => text.duressAtLeastFour,
      _DuressError.codesDiffer => text.duressCodesDiffer,
      _DuressError.sameAsUnlock => text.duressSameAsUnlock,
    };
