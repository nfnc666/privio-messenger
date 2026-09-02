import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../disguise/skin.dart';
import '../theme/privio_colors.dart';
import '../widgets/settings_row.dart';
import 'calculator_screen.dart';
import 'screen_lock_screen.dart';

/// Screen 14: disguise mode.
///
/// It says what it does and, more importantly, what it does not: this hides
/// what is on the screen, not that Privio is installed.
class DisguiseScreen extends StatelessWidget {
  const DisguiseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Disguise mode')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.xxl,
                PrivioSpacing.lg,
                PrivioSpacing.xxl,
                PrivioSpacing.lg,
              ),
              child: Text(
                'A locked Privio opens to a working calculator instead of a lock '
                'screen. Typing your passcode and pressing = opens Privio; any '
                'other sum is a sum.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (!state.disguiseAvailable)
              _NeedsNumericLock(kind: state.passcodeKind == null ? null : 'phrase')
            else ...[
              SettingsSection(
                caption: 'Open to',
                children: [
                  SettingsRow(
                    label: 'The lock screen',
                    trailing: _tick(state.disguise == null),
                    onTap: () => state.setDisguise(null),
                  ),
                  for (final skin in CalculatorSkin.values)
                    SettingsRow(
                      label: '${skin.label} calculator',
                      trailing: _tick(state.disguise == skin),
                      onTap: () => state.setDisguise(skin),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PrivioSpacing.xxl,
                  PrivioSpacing.md,
                  PrivioSpacing.xxl,
                  PrivioSpacing.lg,
                ),
                child: Text(
                  'Pick the one your phone already ships. A calculator that does '
                  'not look like the usual one is the thing somebody notices.',
                  style: theme.textTheme.labelSmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _Preview(skin: state.disguise ?? CalculatorSkin.iphone),
                    ),
                  ),
                  child: const Text('See it'),
                ),
              ),
            ],
            const SizedBox(height: PrivioSpacing.xl),
            const _WhatItDoesNotDo(),
          ],
        ),
      ),
    );
  }

  static Widget _tick(bool on) => SizedBox(
        width: 20,
        child: on
            ? const Icon(Icons.check_rounded, color: PrivioColors.accent, size: 20)
            : null,
      );
}

/// Shown when there is no numeric passcode to type into a calculator.
class _NeedsNumericLock extends StatelessWidget {
  const _NeedsNumericLock({required this.kind});

  /// 'phrase' when a lock exists but cannot be typed here; null when there is
  /// no lock at all. The two need different sentences.
  final String? kind;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kind == null
                ? 'There is no screen lock on this device yet, so there is no '
                    'code to type into a calculator.'
                : 'Your screen lock is a passphrase. A calculator has ten keys '
                    'and no letters, so there is no way to type it in. Switch the '
                    'lock to 4 or 6 digits to use a disguise.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: PrivioSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScreenLockScreen()),
            ),
            child: const Text('Screen lock'),
          ),
        ],
      ),
    );
  }
}

class _WhatItDoesNotDo extends StatelessWidget {
  const _WhatItDoesNotDo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What this does not do', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: PrivioSpacing.sm),
          Text(
            'The app is still called Privio in the launcher and still has its '
            'icon. This hides what is on the screen from someone looking at it, '
            'not the fact that Privio is installed from someone going through '
            'the phone. Changing the icon and the name needs work on the Android '
            'and iOS side that is not done.\n\n'
            'It is also not a defence against anyone with the phone for long: '
            'the app, its size and its network traffic are all still there to '
            'find. What it is good at is the ordinary case — a screen glanced '
            'at, or a phone handed over unlocked.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// The disguise, shown from inside the app so it can be looked at before it is
/// the only thing standing between someone and their messages.
class _Preview extends StatelessWidget {
  const _Preview({required this.skin});

  final CalculatorSkin skin;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CalculatorScreen(skin: skin),
        Positioned(
          left: PrivioSpacing.sm,
          top: MediaQuery.of(context).padding.top + PrivioSpacing.sm,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            tooltip: 'Close preview',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
