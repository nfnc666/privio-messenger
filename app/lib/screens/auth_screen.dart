import 'dart:async';

import 'package:flutter/material.dart';

import '../core/failure.dart';
import '../core/app_state.dart';
import '../core/display_name.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import 'backup_screen.dart';
import '../widgets/phone_field.dart';
import '../widgets/phone_verify_sheet.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/privio_logo.dart';

enum AuthMode { signUp, signIn }

/// Creating an account, or signing back into one.
///
/// The only things asked for are a username and a password — there is no phone
/// number field because there is nothing to verify and nothing to correlate.
class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.mode, super.key, this.restoring = false});

  final AuthMode mode;

  /// True when this sign-in is the first step of restoring a backup, which
  /// changes what the screen says and where it goes afterwards.
  final bool restoring;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _totp = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late AuthMode _mode = widget.mode;
  bool _obscure = true;
  bool _needsTotp = false;

  /// What the server said about the typed username: true free, false taken,
  /// null not asked or not answered.
  ///
  /// Asked before the password is chosen, because a username cannot be
  /// changed afterwards — finding out it was taken *after* filling in the
  /// rest of the form is finding out too late to matter.
  bool? _usernameFree;
  String? _checked;
  bool _checking = false;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _phone.dispose();
    _totp.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == AuthMode.signUp;

  /// The optional number typed during sign-up.
  ///
  /// It is **not** part of registration: the account is created without it, and
  /// only then is a code offered. An empty field, a cancelled verification and
  /// a server that cannot send texts all end the same way — a finished account
  /// with no number, which is a finished account.
  final TextEditingController _phone = TextEditingController();
  final GlobalKey<PhoneFieldState> _phoneField = GlobalKey<PhoneFieldState>();

  /// Sends a code for the typed number and opens the sheet, if there is one.
  ///
  /// Every branch here ends without blocking: nothing typed, nothing that
  /// normalises, a server with no SMS provider, a code that never arrives, a
  /// cancelled sheet. A phone number is a convenience for being found; it is
  /// not a step in making an account, and the flow is arranged so that is true
  /// rather than merely claimed.
  Future<void> _offerPhoneVerification(AppState state) async {
    if (_phoneField.currentState?.isEmpty ?? true) return;
    final number = _phoneField.currentState?.value;
    if (number == null) return;

    final account = state.accountId;
    if (account == null) return;
    final controller = state.phone;
    await controller.load(account);
    if (!controller.link.canVerify) return;
    if (!await controller.requestCode(number.e164)) return;
    if (!mounted) return;

    await showPhoneVerifySheet(context, controller);
  }

  /// Asks the server about the typed username, once, when the field is left.
  ///
  /// Not per keystroke: every letter would be a request against a budget
  /// shared with password attempts, and half a username is not a question
  /// worth asking. Answered only for a name that is well formed, because the
  /// format rule is already on screen for one that is not.
  Future<void> _checkUsername() async {
    final username = _username.text.trim().toLowerCase();
    if (!_isSignUp || username == _checked) return;
    if (!RegExp(r'^[a-z0-9_.]{3,32}$').hasMatch(username)) {
      setState(() {
        _checked = null;
        _usernameFree = null;
      });
      return;
    }

    setState(() {
      _checking = true;
      _usernameFree = null;
    });
    final free = await PrivioScope.of(context).usernameAvailable(username);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checked = username;
      _usernameFree = free;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final state = PrivioScope.of(context);

    final ok = _isSignUp
        ? await state.register(
            username: _username.text.trim().toLowerCase(),
            password: _password.text,
            displayName: cleanDisplayName(_displayName.text),
          )
        : await state.signIn(
            username: _username.text.trim().toLowerCase(),
            password: _password.text,
            totpCode: _totp.text.isEmpty ? null : _totp.text,
          );

    if (!mounted) return;
    if (ok) {
      // Offered *after* the account exists, never as a condition of it. If any
      // of this fails or is waved away, the account is already made and the
      // person is already signed in.
      if (_isSignUp) await _offerPhoneVerification(state);
      if (!mounted) return;
      Navigator.of(context).pop();
      // A backup holds history, not an identity — so restoring happens after
      // the device has one, and this hands the user straight to the key.
      if (widget.restoring && mounted) {
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
          ),
        );
      }
      return;
    }
    // The server asks for a second factor only once it knows the password was
    // right, so the field appears at exactly that point.
    if (state.authFailure?.kind == FailureKind.totpRequired) {
      setState(() => _needsTotp = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = PrivioScope.of(context);
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(leading: const PrivioBackButton()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: PrivioSpacing.lg),
                const Center(child: PrivioMark(size: 56)),
                const SizedBox(height: PrivioSpacing.xl),
                Text(
                  _isSignUp ? text.authCreateTitle : text.authWelcomeBack,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: PrivioSpacing.sm),
                Text(
                  _isSignUp ? text.authCreateNote : text.authSignInNote,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: PrivioSpacing.xxl),
                Focus(
                  // The check runs when the field is left, which is also when
                  // somebody has finished typing the name they want.
                  onFocusChange: (has) {
                    if (!has) unawaited(_checkUsername());
                  },
                  child: TextFormField(
                    controller: _username,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: text.contactsUsernameHint,
                      prefixText: '@ ',
                      suffixIcon: !_isSignUp || (!_checking && _usernameFree == null)
                          ? null
                          : _checking
                              ? const Padding(
                                  padding: EdgeInsets.all(PrivioSpacing.md),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : Icon(
                                  _usernameFree!
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.error_outline_rounded,
                                  size: 18,
                                  color: _usernameFree!
                                      ? context.accents.accent
                                      : PrivioColors.danger,
                                ),
                    ),
                    validator: (value) {
                      final username = (value ?? '').trim().toLowerCase();
                      if (!RegExp(r'^[a-z0-9_.]{3,32}$').hasMatch(username)) {
                        return text.authUsernameRule;
                      }
                      // Only a name the server has already said no to. A name
                      // it has not answered about is not refused here — the
                      // registration itself is the authority, and an offline
                      // check must not stop somebody signing up.
                      if (_isSignUp && username == _checked && _usernameFree == false) {
                        return text.authUsernameTakenHint(username);
                      }
                      return null;
                    },
                  ),
                ),
                if (_isSignUp) ...[
                  const SizedBox(height: PrivioSpacing.sm),
                  // Said before the password is chosen and before the button
                  // is pressed, because this is the one decision on this
                  // screen that cannot be revisited.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 14, color: context.accents.accent),
                      const SizedBox(width: PrivioSpacing.xs),
                      Expanded(
                        child: Text(
                          _checking
                              ? text.authUsernameChecking
                              : _usernameFree == true && _checked != null
                                  ? text.authUsernameFree(_checked!)
                                  : text.authUsernamePermanent,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _usernameFree == true
                                ? context.accents.accent
                                : PrivioColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PrivioSpacing.md),
                  // The other name: free text, changeable, and not required.
                  TextFormField(
                    controller: _displayName,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(hintText: text.authDisplayNameHint),
                    validator: (value) =>
                        displayNameProblem(value ?? '') == DisplayNameProblem.tooLong
                            ? text.failureDisplayNameTooLong
                            : null,
                  ),
                  const SizedBox(height: PrivioSpacing.sm),
                  Text(
                    text.authDisplayNamePurpose,
                    style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
                  ),
                ],
                const SizedBox(height: PrivioSpacing.md),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'password',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 20,
                        color: PrivioColors.textTertiary,
                      ),
                    ),
                  ),
                  validator: (value) {
                    // Only enforced on sign-up: an existing shorter password
                    // must still be able to get in and change itself.
                    if (_isSignUp && (value ?? '').length < 10) {
                      return text.authPasswordRule;
                    }
                    if ((value ?? '').isEmpty) return text.authPasswordRequired;
                    return null;
                  },
                ),
                if (_isSignUp) ...[
                  const SizedBox(height: PrivioSpacing.md),
                  // No validator, deliberately. An empty field is a complete
                  // answer and must not stop the form, so there is nothing here
                  // that can refuse it.
                  PhoneField(key: _phoneField, controller: _phone),
                  const SizedBox(height: PrivioSpacing.sm),
                  Text(
                    text.phoneFieldExplain,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: PrivioColors.textTertiary),
                  ),
                ],
                if (_needsTotp) ...[
                  const SizedBox(height: PrivioSpacing.md),
                  TextFormField(
                    controller: _totp,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(hintText: text.authTotpHint),
                  ),
                ],
                if (state.authFailure != null) ...[
                  const SizedBox(height: PrivioSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: PrivioColors.danger),
                      const SizedBox(width: PrivioSpacing.sm),
                      Expanded(
                        child: Text(
                          state.authFailure!.words(text),
                          style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: PrivioSpacing.xl),
                FilledButton(
                  onPressed: state.busy ? null : _submit,
                  child: state.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PrivioColors.background,
                          ),
                        )
                      : Text(_isSignUp ? text.authCreateAccount : text.authSignIn),
                ),
                const SizedBox(height: PrivioSpacing.sm),
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () => setState(() {
                            _mode = _isSignUp ? AuthMode.signIn : AuthMode.signUp;
                            _needsTotp = false;
                          }),
                  child: Text(
                    _isSignUp ? text.welcomeHaveAccount : text.authCreateNew,
                  ),
                ),
                if (_isSignUp) ...[
                  const SizedBox(height: PrivioSpacing.lg),
                  Text(
                    text.authPasswordOnlyWay,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
                const SizedBox(height: PrivioSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
