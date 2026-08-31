import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/edition.dart';
import '../core/license_controller.dart';
import '../core/license_key.dart';
import '../theme/privio_colors.dart';

/// Activation: where a Privio License Key is turned into a licensed account.
///
/// Only the Libre and direct-APK builds show a key field. The store builds are
/// paid for in the store, and this screen says so rather than offering a field
/// that could never work for them.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key, this.firstRun = false});

  /// True when this is the launch screen rather than a settings page.
  ///
  /// There is no account yet at that point, so the key cannot be redeemed —
  /// it is held in the keystore and spent the moment an account exists. The
  /// screen also stops being a dead end: someone who has not bought a key yet,
  /// or who is about to join a server that needs none, can walk past it.
  final bool firstRun;

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _key = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.firstRun) return;
    // The status may be stale — the key could have been redeemed on another
    // device since the app started.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PrivioScope.of(context).license.refresh();
    });
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _activate(LicenseController license) async {
    if (widget.firstRun) {
      // Nothing to bind a key to yet. Keep it, and move on to making the
      // account that will own it.
      if (!await license.hold(_key.text)) return;
      if (!mounted) return;
      PrivioScope.of(context).continuePastActivation();
      return;
    }

    final ok = await license.redeem(_key.text);
    if (!mounted) return;
    if (!ok) return;

    _key.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Activated. This license now belongs to your account.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final license = PrivioScope.of(context).license;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privio License'),
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: ListenableBuilder(
        listenable: license,
        builder: (context, _) => _Body(
          license: license,
          field: _key,
          onActivate: _activate,
          firstRun: widget.firstRun,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.license,
    required this.field,
    required this.onActivate,
    this.firstRun = false,
  });

  final LicenseController license;
  final TextEditingController field;
  final Future<void> Function(LicenseController) onActivate;
  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = license.state;
    final edition = PrivioEdition.current;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.xxl,
        PrivioSpacing.xl,
        PrivioSpacing.xxl,
        PrivioSpacing.xxxl,
      ),
      children: [
        if (firstRun)
          _Activation(license: license, field: field, onActivate: onActivate, firstRun: true)
        else if (state == null)
          const _Note(
            icon: Icons.cloud_off_rounded,
            title: 'Not checked yet',
            body: 'Privio has not been able to ask the server about this account yet. '
                'Pull the app back online and reopen this screen.',
          )
        else if (state.licensed)
          _Licensed(state: state)
        else if (!state.enforced)
          const _Note(
            icon: Icons.home_work_outlined,
            title: 'No license needed here',
            body: 'This server does not require one. Licensing is for the hosted Privio '
                'service — a license for infrastructure you already run would mean nothing.',
          )
        else if (!edition.usesLicenseKey)
          _Note(
            icon: Icons.storefront_outlined,
            title: 'Handled by the store',
            body: 'This build was paid for through the app store it came from, so there is '
                'no key to enter. If it is not active, restore your purchase in '
                '${edition.distribution == PrivioDistribution.play ? 'Google Play' : 'the App Store'}.',
          )
        else
          _Activation(license: license, field: field, onActivate: onActivate),
        const SizedBox(height: PrivioSpacing.xxl),
        const Divider(height: 1, color: PrivioColors.border),
        const SizedBox(height: PrivioSpacing.lg),
        Text(
          'One purchase, one key, one account, for good. A redeemed key is bound to the '
          'account that redeemed it and cannot be moved or used again.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.md),
        Text(
          '${edition.name} is free software under ${PrivioEdition.licenseSpdxId}. The key does '
          'not unlock the app — you already have all of it, and can build it yourself. It pays '
          'for the hosted service that relays your messages.',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _Activation extends StatelessWidget {
  const _Activation({
    required this.license,
    required this.field,
    required this.onActivate,
    this.firstRun = false,
  });

  final LicenseController license;
  final TextEditingController field;
  final Future<void> Function(LicenseController) onActivate;
  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter your license key', style: theme.textTheme.titleMedium),
        const SizedBox(height: PrivioSpacing.sm),
        Text(
          firstRun
              ? 'Buy a key at privio.com/license, then type it here. It is kept on this '
                  'device and activated as soon as your account exists — a key belongs to '
                  'an account, and there is not one yet.'
              : 'Buy a key at privio.com/license, then type it here. Until it is activated '
                  'this account can sign in and read what has already arrived, but not send.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.xl),
        TextField(
          controller: field,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          enabled: !license.busy,
          inputFormatters: const [_LicenseKeyFormatter()],
          onChanged: (_) => license.clearError(),
          onSubmitted: (_) => onActivate(license),
          decoration: const InputDecoration(hintText: licenseKeyFormat),
        ),
        if (license.error != null) ...[
          const SizedBox(height: PrivioSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: PrivioColors.danger),
              const SizedBox(width: PrivioSpacing.sm),
              Expanded(
                child: Text(
                  license.error!,
                  style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: PrivioSpacing.xl),
        FilledButton(
          onPressed: license.busy ? null : () => onActivate(license),
          child: license.busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PrivioColors.background,
                  ),
                )
              : Text(firstRun ? 'Continue' : 'Activate'),
        ),
        if (firstRun) ...[
          const SizedBox(height: PrivioSpacing.sm),
          TextButton(
            onPressed: license.busy
                ? null
                : () => PrivioScope.of(context).continuePastActivation(),
            child: const Text('I do not have a key yet'),
          ),
          const SizedBox(height: PrivioSpacing.md),
          Text(
            'Without a key you can still create an account, sign in and read what arrives. '
            'Sending is what the server holds back until a key is activated.',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}

class _Licensed extends StatelessWidget {
  const _Licensed({required this.state});

  final LicenseState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = state.redeemedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(PrivioSpacing.lg),
          decoration: const BoxDecoration(
            color: PrivioColors.accentSurface,
            borderRadius: BorderRadius.all(PrivioRadius.card),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_rounded, color: PrivioColors.accent),
              const SizedBox(width: PrivioSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Activated', style: theme.textTheme.titleMedium),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      _describe(state),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (at != null) ...[
          const SizedBox(height: PrivioSpacing.md),
          Text(
            'Redeemed on ${at.toLocal().toString().split(' ').first}.',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }

  static String _describe(LicenseState state) => switch (state.source) {
        'apple' => 'Bought through the App Store.',
        'google' => 'Bought through Google Play.',
        _ => 'Activated with a license key. Lifetime access, no renewals.',
      };
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(PrivioSpacing.lg),
      decoration: const BoxDecoration(
        color: PrivioColors.surfaceRaised,
        borderRadius: BorderRadius.all(PrivioRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: PrivioColors.textSecondary),
          const SizedBox(width: PrivioSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: PrivioSpacing.xs),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats the field as `PRIVIO-XXXX-XXXX-XXXX-XXXX` while it is being typed,
/// folding Crockford aliases on the way in so an O typed for a zero is simply
/// shown as a zero rather than rejected later.
class _LicenseKeyFormatter extends TextInputFormatter {
  const _LicenseKeyFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final body = normaliseLicenseKey(newValue.text);
    final capped =
        body.length > licenseKeyBodyLength ? body.substring(0, licenseKeyBodyLength) : body;
    final text = formatLicenseKey(capped);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
