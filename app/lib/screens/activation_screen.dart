import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/edition.dart';
import '../theme/privio_colors.dart';
import '../widgets/license_key_field.dart';
import '../widgets/privio_logo.dart';

/// The activation step, shown once after an account is created on a server
/// that sells access.
///
/// It is a step, not a wall. The server lets an unlicensed account sign in and
/// read what has already arrived — only sending is gated — so a screen that
/// refused to let anyone past would be claiming a restriction the server does
/// not actually apply. "Not now" is therefore a real answer, and the question
/// is not asked again after it.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _activate(AppState state) async {
    final ok = await state.license.redeem(_key.text);
    if (!ok || !mounted) return;
    _key.clear();
    // Nothing to record: the server now answers "licensed", so the question
    // will not come back on the next launch by itself.
    await state.leaveActivation(asked: false);
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);
    final edition = PrivioEdition.current;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state.license,
          builder: (context, _) {
            final license = state.license;

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.xxl,
                PrivioSpacing.xxxl,
                PrivioSpacing.xxl,
                PrivioSpacing.xxl,
              ),
              children: [
                const Center(child: PrivioMark(size: 56, glow: true)),
                const SizedBox(height: PrivioSpacing.xl),
                Text(
                  'Activate Privio',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: PrivioSpacing.sm),
                Text(
                  'Your account is ready. This server asks for a license key before '
                  'it will relay your messages.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: PrivioSpacing.xxxl),
                if (edition.usesLicenseKey) ...[
                  LicenseKeyField(
                    controller: _key,
                    enabled: !license.busy,
                    onChanged: license.clearError,
                    onSubmitted: () => _activate(state),
                  ),
                  if (license.error != null) ...[
                    const SizedBox(height: PrivioSpacing.lg),
                    _Failure(message: license.error!),
                  ],
                  const SizedBox(height: PrivioSpacing.xl),
                  FilledButton(
                    onPressed: license.busy ? null : () => _activate(state),
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
                ] else
                  Text(
                    'This build is paid for through the store it came from. If it is not '
                    'active yet, restore your purchase there and reopen Privio.',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: PrivioSpacing.md),
                TextButton(
                  onPressed: license.busy ? null : () => state.leaveActivation(),
                  child: const Text('Not now'),
                ),
                const SizedBox(height: PrivioSpacing.xl),
                const Divider(height: 1, color: PrivioColors.border),
                const SizedBox(height: PrivioSpacing.lg),
                Text(
                  'Without a key you can sign in and read what arrives, but not send. '
                  'You can enter it later under Settings › Privio License.',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: PrivioSpacing.md),
                Text(
                  '${edition.name} is free software under ${PrivioEdition.licenseSpdxId}. '
                  'The key does not unlock the app — you already have all of it, and can '
                  'build it yourself. It pays for the hosted service that relays your '
                  'messages.',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            );
          },
        ),
      ),
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
