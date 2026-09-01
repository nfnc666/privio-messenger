import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';

/// Screen 7: calls.
///
/// There is no call history, because there have been no calls. This screen
/// used to render five out of `DemoData` — Alice at 11:32, Charlie at 10:21, a
/// missed one from Alice yesterday — under a doc comment claiming "the list is
/// real". It was not, and a fabricated call log is worse than an empty one: it
/// is the app telling someone they spoke to a person they did not speak to.
class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone_outlined, size: 40, color: PrivioColors.textTertiary),
              const SizedBox(height: PrivioSpacing.lg),
              Text('No calls yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                'Encrypted voice and video calls are the next thing being built. '
                'They will run over the Signal sessions this app already has, so '
                'the keys are the ones your chats use and the server relays media '
                'it cannot decode.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: PrivioSpacing.xl),
              Text(
                'Until then this screen has nothing to show, which is the honest '
                'version of a call log.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
