import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'backup_screen.dart';
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
  final _password = TextEditingController();
  final _totp = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late AuthMode _mode = widget.mode;
  bool _obscure = true;
  bool _needsTotp = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _totp.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == AuthMode.signUp;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final state = PrivioScope.of(context);

    final ok = _isSignUp
        ? await state.register(
            username: _username.text.trim().toLowerCase(),
            password: _password.text,
          )
        : await state.signIn(
            username: _username.text.trim().toLowerCase(),
            password: _password.text,
            totpCode: _totp.text.isEmpty ? null : _totp.text,
          );

    if (!mounted) return;
    if (ok) {
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
    if (state.authError == 'Enter your two-factor code.') {
      setState(() => _needsTotp = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = PrivioScope.of(context);

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
                  _isSignUp ? 'Create your account' : 'Welcome back',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: PrivioSpacing.sm),
                Text(
                  _isSignUp
                      ? 'Pick a username. No phone number, no email — nothing to '
                          'link this account to anything else.'
                      : 'Sign in with your username and password.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: PrivioSpacing.xxl),
                TextFormField(
                  controller: _username,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'username', prefixText: '@ '),
                  validator: (value) {
                    final username = (value ?? '').trim().toLowerCase();
                    if (!RegExp(r'^[a-z0-9_.]{3,32}$').hasMatch(username)) {
                      return '3–32 characters: a–z, 0–9, dot or underscore';
                    }
                    return null;
                  },
                ),
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
                      return 'At least 10 characters — this one protects everything';
                    }
                    if ((value ?? '').isEmpty) return 'Enter your password';
                    return null;
                  },
                ),
                if (_needsTotp) ...[
                  const SizedBox(height: PrivioSpacing.md),
                  TextFormField(
                    controller: _totp,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'two-factor code'),
                  ),
                ],
                if (state.authError != null) ...[
                  const SizedBox(height: PrivioSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: PrivioColors.danger),
                      const SizedBox(width: PrivioSpacing.sm),
                      Expanded(
                        child: Text(
                          state.authError!,
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
                      : Text(_isSignUp ? 'Create account' : 'Sign in'),
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
                    _isSignUp ? 'I already have an account' : 'Create a new account',
                  ),
                ),
                if (_isSignUp) ...[
                  const SizedBox(height: PrivioSpacing.lg),
                  Text(
                    'Your password is the only way into this account. Privio '
                    'cannot reset it, because Privio cannot read anything it '
                    'would unlock.',
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
