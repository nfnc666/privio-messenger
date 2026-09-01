import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/edition.dart';
import '../core/license_controller.dart';
import '../theme/privio_colors.dart';
import '../widgets/license_key_field.dart';

/// Activation: where a Privio License Key is turned into a licensed account.
///
/// Only the Libre and direct-APK builds show a key field. The store builds are
/// paid for in the store, and this screen says so rather than offering a field
/// that could never work for them.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _key = TextEditingController();

  @override
  void initState() {
    super.initState();
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
      appBar: AppBar(title: const Text('Privio License')),
      body: ListenableBuilder(
        listenable: license,
        builder: (context, _) => _Body(license: license, field: _key, onActivate: _activate),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.license, required this.field, required this.onActivate});

  final LicenseController license;
  final TextEditingController field;
  final Future<void> Function(LicenseController) onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = license.state;
    // From the app rather than the constant, so this screen and the activation
    // step at first start always describe the same build.
    final edition = PrivioScope.of(context).edition;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.xxl,
        PrivioSpacing.xl,
        PrivioSpacing.xxl,
        PrivioSpacing.xxxl,
      ),
      children: [
        if (state == null)
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
  const _Activation({required this.license, required this.field, required this.onActivate});

  final LicenseController license;
  final TextEditingController field;
  final Future<void> Function(LicenseController) onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter your license key', style: theme.textTheme.titleMedium),
        const SizedBox(height: PrivioSpacing.sm),
        Text(
          'Buy a key at getprivio.com/license, then type it here. Until it is activated '
          'this account can sign in and read what has already arrived, but not send.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.xl),
        LicenseKeyField(
          controller: field,
          enabled: !license.busy,
          onChanged: license.clearError,
          onSubmitted: () => onActivate(license),
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
              : const Text('Activate'),
        ),
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
