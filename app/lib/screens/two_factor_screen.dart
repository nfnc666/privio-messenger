import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../core/security_controller.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Two-factor authentication: turning it on, and turning it off.
///
/// The server has enforced this at login all along, and the login screen has
/// always asked for the code — but there was no way to switch it on from the
/// app, so the Privacy screen simply claimed it was already on. This is that
/// screen.
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PrivioScope.of(context).security.load();
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm(SecurityController security) async {
    final ok = await security.confirmTotp(_code.text);
    if (!ok || !mounted) return;
    _code.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppText.of(context).twoFactorOnToast)),
    );
  }

  Future<void> _disable(SecurityController security) async {
    final password = await _askForPassword();
    if (password == null || !mounted) return;
    final ok = await security.disableTotp(password);
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppText.of(context).twoFactorOffToast)),
    );
  }

  /// Removing the factor asks for the password, because an unlocked phone
  /// should not be enough to take it off.
  Future<String?> _askForPassword() {
    final text = AppText.of(context);
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.twoFactorTurnOffTitle),
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
            child: Text(text.twoFactorTurnOff),
          ),
        ],
      ),
    ).whenComplete(field.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final security = PrivioScope.of(context).security;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(AppText.of(context).privacyTwoFactor),
      ),
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
            switch ((security.twoFactorEnabled, security.setUpSecret)) {
              (null, _) => const _Waiting(),
              (true, _) => _On(onDisable: () => _disable(security)),
              (false, final String secret) => _Setup(
                  security: security,
                  secret: secret,
                  field: _code,
                  onConfirm: () => _confirm(security),
                ),
              (false, null) => _Off(
                  busy: security.busy,
                  onStart: security.beginTotpSetup,
                ),
            },
            if (security.failure != null) ...[
              const SizedBox(height: PrivioSpacing.lg),
              _Failure(message: security.failure!.words(AppText.of(context))),
            ],
            const SizedBox(height: PrivioSpacing.xxl),
            const Divider(height: 1, color: PrivioColors.border),
            const SizedBox(height: PrivioSpacing.lg),
            Text(
              AppText.of(context).twoFactorServerNote,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: PrivioSpacing.xxxl),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
}

class _Off extends StatelessWidget {
  const _Off({required this.busy, required this.onStart});

  final bool busy;
  final Future<bool> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppText.of(context).commonOff, style: theme.textTheme.titleLarge),
        const SizedBox(height: PrivioSpacing.sm),
        Text(
          AppText.of(context).twoFactorOffBody,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.xl),
        FilledButton(
          onPressed: busy ? null : () => onStart(),
          child: Text(AppText.of(context).twoFactorSetUp),
        ),
      ],
    );
  }
}

class _Setup extends StatelessWidget {
  const _Setup({
    required this.security,
    required this.secret,
    required this.field,
    required this.onConfirm,
  });

  final SecurityController security;
  final String secret;
  final TextEditingController field;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = security.setUpUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppText.of(context).twoFactorScanThis, style: theme.textTheme.titleLarge),
        const SizedBox(height: PrivioSpacing.sm),
        Text(
          AppText.of(context).twoFactorScanNote,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.xl),
        if (url != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(PrivioSpacing.lg),
              decoration: const BoxDecoration(
                color: PrivioColors.textPrimary,
                borderRadius: BorderRadius.all(PrivioRadius.card),
              ),
              // Rendered on this device. The secret is not sent anywhere to be
              // turned into a picture.
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: PrivioColors.textPrimary,
              ),
            ),
          ),
        const SizedBox(height: PrivioSpacing.lg),
        SettingsRow(
          label: AppText.of(context).twoFactorTypeKey,
          value: _grouped(secret),
          onTap: () {
            Clipboard.setData(ClipboardData(text: secret));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppText.of(context).twoFactorKeyCopied)),
            );
          },
        ),
        const SizedBox(height: PrivioSpacing.lg),
        TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          enabled: !security.busy,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => security.clearError(),
          onSubmitted: (_) => onConfirm(),
          decoration: const InputDecoration(hintText: '123456', counterText: ''),
        ),
        const SizedBox(height: PrivioSpacing.lg),
        FilledButton(
          onPressed: security.busy ? null : onConfirm,
          child: security.busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PrivioColors.background,
                  ),
                )
              : Text(AppText.of(context).twoFactorTurnOn),
        ),
        TextButton(
          onPressed: security.busy ? null : security.cancelTotpSetup,
          child: Text(AppText.of(context).commonCancel),
        ),
      ],
    );
  }

  /// Four characters at a time, so a key typed by hand can be checked against
  /// the screen without losing your place.
  static String _grouped(String secret) {
    final groups = <String>[];
    for (var i = 0; i < secret.length; i += 4) {
      groups.add(secret.substring(i, i + 4 > secret.length ? secret.length : i + 4));
    }
    return groups.join(' ');
  }
}

class _On extends StatelessWidget {
  const _On({required this.onDisable});

  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(PrivioSpacing.lg),
          decoration: BoxDecoration(
            color: context.accents.surface,
            borderRadius: const BorderRadius.all(PrivioRadius.card),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_user_rounded, color: context.accents.accent),
              const SizedBox(width: PrivioSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppText.of(context).commonOn, style: theme.textTheme.titleMedium),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      AppText.of(context).twoFactorOnBody,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PrivioSpacing.xl),
        OutlinedButton(
          onPressed: onDisable,
          style: OutlinedButton.styleFrom(foregroundColor: PrivioColors.danger),
          child: Text(AppText.of(context).twoFactorTurnOff),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, size: 16, color: PrivioColors.danger),
        const SizedBox(width: PrivioSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
          ),
        ),
      ],
    );
  }
}
