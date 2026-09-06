import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';
import '../widgets/web_storage_notice.dart';
import '../widgets/privio_logo.dart';

/// Screen 3: what Privio promises, before anything is asked of the user.
///
/// The four promises are the product's whole argument, so they are the first
/// thing shown — and there is no sign-up form here, because there is nothing to
/// collect.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    required this.onGetStarted,
    required this.onSignIn,
    required this.onImportBackup,
    super.key,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;
  final VoidCallback onImportBackup;

  static const List<(IconData, String)> _promises = [
    (Icons.lock_rounded, 'End-to-end encrypted'),
    (Icons.phone_disabled_rounded, 'No phone number required'),
    (Icons.verified_user_outlined, "You're in control"),
    (Icons.shield_outlined, 'Privacy by design'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              const PrivioMark(size: 72, glow: true),
              const SizedBox(height: PrivioSpacing.xl),
              Text('Welcome to', style: theme.textTheme.bodyMedium),
              Text(
                'Privio',
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: PrivioSpacing.xxxl),
              for (final (icon, label) in _promises)
                Padding(
                  padding: const EdgeInsets.only(bottom: PrivioSpacing.lg),
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: PrivioColors.accent),
                      const SizedBox(width: PrivioSpacing.md),
                      Text(label, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              // The call to action sits just under the promises rather than at
              // the very bottom, as the mockup has it.
              const Spacer(),
              // Before the account exists, because it is a reason somebody
              // might choose to install the app instead.
              if (WebStorageNotice.applies) ...[
                const WebStorageNotice(compact: true),
                const SizedBox(height: PrivioSpacing.lg),
              ],
              FilledButton(onPressed: onGetStarted, child: const Text('Get Started')),
              const SizedBox(height: PrivioSpacing.sm),
              // Somebody who already has an account is not a new user, and had
              // to work that out for themselves: the only ways in were a button
              // that says it creates an account, and one that says it imports a
              // backup. Reinstalling, or adding a second device, is not an
              // unusual thing to be doing on this screen.
              TextButton(onPressed: onSignIn, child: const Text('I already have an account')),
              TextButton(
                onPressed: onImportBackup,
                child: const Text('Import from backup'),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
