import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../disguise/launcher_disguise.dart';
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
                'screen. Any sum that comes to your passcode opens Privio when '
                'you press =, so the code itself never has to appear on screen. '
                'Every other sum is just a sum.',
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
            if (state.disguiseError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PrivioSpacing.xxl,
                  PrivioSpacing.md,
                  PrivioSpacing.xxl,
                  0,
                ),
                child: Text(
                  '${state.disguiseError} The lock screen changed anyway; the '
                  'home screen did not.',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: PrivioColors.danger),
                ),
              ),
            const SizedBox(height: PrivioSpacing.xl),
            _WhatItDoesNotDo(launcher: state.launcherCapability),
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

/// What the home screen will look like, and what the disguise still cannot do.
///
/// Written from what the platform actually reports rather than from a general
/// claim, because the two differ: Android changes the icon and the name, iOS
/// changes the icon and cannot change the name, and the web build changes
/// neither. An app that promised the same thing everywhere would be wrong on
/// two platforms out of three.
class _WhatItDoesNotDo extends StatelessWidget {
  const _WhatItDoesNotDo({required this.launcher});

  final LauncherCapability launcher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('On the home screen', style: theme.textTheme.titleSmall),
          const SizedBox(height: PrivioSpacing.sm),
          Text(_homeScreen, style: theme.textTheme.labelSmall),
          const SizedBox(height: PrivioSpacing.lg),
          Text('What this does not do', style: theme.textTheme.titleSmall),
          const SizedBox(height: PrivioSpacing.sm),
          Text(
            'It is not a defence against anyone who has the phone for long. The '
            'app is still installed, and its size, its files and its network '
            'traffic are all still there to find by anyone who looks properly. '
            'What it is good at is the ordinary case — a screen glanced at, or '
            'a phone handed over unlocked.',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  String get _homeScreen {
    if (launcher.icon && launcher.name) {
      return 'On the home screen and in the app drawer, Privio becomes a '
          'calculator icon called "Calculator". Your launcher may take a few '
          'seconds to redraw, and an icon you pinned to the home screen '
          'yourself may need pinning again. Turning the disguise off puts it '
          'back.\n\n'
          'Android\'s own app list — Settings, app info, the name shown when '
          'Privio asks for a permission — still says Privio. That name is set '
          'when the app is built and no app can change it while running.';
    }
    return 'On this device the icon and the name do not change — only what the '
        'app opens to. Someone going through the home screen still finds '
        'Privio by name.';
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
