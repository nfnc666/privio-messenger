import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../core/edition.dart';
import '../core/license_controller.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/license_key_field.dart';
import '../widgets/privio_back_button.dart';

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
      SnackBar(content: Text(AppText.of(context).licenseActivatedToast)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final license = PrivioScope.of(context).license;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(AppText.of(context).settingsLicense),
      ),
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
    final text = AppText.of(context);
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
          _Note(
            icon: Icons.cloud_off_rounded,
            title: text.licenseNotCheckedTitle,
            body: text.licenseNotCheckedBody,
          )
        else if (state.licensed)
          _Licensed(state: state)
        else if (!state.enforced)
          _Note(
            icon: Icons.home_work_outlined,
            title: text.licenseNotNeededTitle,
            body: text.licenseNotNeededBody,
          )
        else if (!edition.usesLicenseKey)
          _Note(
            icon: Icons.storefront_outlined,
            title: text.licenseStoreTitle,
            body: text.licenseStoreBody(
              edition.distribution == PrivioDistribution.play
                  ? 'Google Play'
                  : 'the App Store',
            ),
          )
        else
          _Activation(license: license, field: field, onActivate: onActivate),
        const SizedBox(height: PrivioSpacing.xxl),
        const Divider(height: 1, color: PrivioColors.border),
        const SizedBox(height: PrivioSpacing.lg),
        Text(
          text.licenseOnePurchaseNote,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.md),
        Text(
          text.activationFreeSoftwareNote(
            edition.name,
            PrivioEdition.licenseSpdxId,
          ),
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
        Text(AppText.of(context).licenseEnterTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: PrivioSpacing.sm),
        Text(
          AppText.of(context).licenseEnterBody,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: PrivioSpacing.xl),
        LicenseKeyField(
          controller: field,
          enabled: !license.busy,
          onChanged: license.clearError,
          onSubmitted: () => onActivate(license),
        ),
        if (license.failure != null) ...[
          const SizedBox(height: PrivioSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: PrivioColors.danger),
              const SizedBox(width: PrivioSpacing.sm),
              Expanded(
                child: Text(
                  license.failure!.words(AppText.of(context)),
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
              : Text(AppText.of(context).activationActivate),
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
          decoration: BoxDecoration(
            color: context.accents.surface,
            borderRadius: BorderRadius.all(PrivioRadius.card),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_rounded, color: context.accents.accent),
              const SizedBox(width: PrivioSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppText.of(context).licenseActivated,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: PrivioSpacing.xs),
                    Text(
                      _describe(AppText.of(context), state),
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
            AppText.of(context).licenseRedeemedOn(
              at.toLocal().toString().split(' ').first,
            ),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }

  static String _describe(AppText text, LicenseState state) => switch (state.source) {
        'apple' => text.licenseFromAppStore,
        'google' => text.licenseFromPlay,
        _ => text.licenseFromKey,
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
