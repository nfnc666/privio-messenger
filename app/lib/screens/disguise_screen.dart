import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../disguise/launcher_disguise.dart';
import '../disguise/skin.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
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
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsDisguise),
      ),
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
                text.disguiseIntro,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (!state.disguiseAvailable)
              _NeedsNumericLock(hasLock: state.passcodeKind != null)
            else ...[
              SettingsSection(
                caption: text.disguiseOpenTo,
                children: [
                  SettingsRow(
                    label: text.disguiseLockScreen,
                    trailing: _tick(state.disguise == null),
                    onTap: () => state.setDisguise(null),
                  ),
                  for (final skin in CalculatorSkin.values)
                    SettingsRow(
                      label: text.disguiseCalculatorNamed(skin.label),
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
                  text.disguisePickNote,
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
                  child: Text(text.disguiseSeeIt),
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
                  text.disguiseErrorSuffix(state.disguiseError!),
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
  const _NeedsNumericLock({required this.hasLock});

  /// Whether this device has a screen lock at all. When it does and the
  /// disguise is still unavailable, the lock is a passphrase.
  final bool hasLock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasLock
                ? AppText.of(context).disguisePhraseLock
                : AppText.of(context).disguiseNoLock,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: PrivioSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScreenLockScreen()),
            ),
            child: Text(AppText.of(context).privacyScreenLock),
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
    final text = AppText.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text.disguiseOnHomeScreen, style: theme.textTheme.titleSmall),
          const SizedBox(height: PrivioSpacing.sm),
          Text(_homeScreen(text), style: theme.textTheme.labelSmall),
          const SizedBox(height: PrivioSpacing.lg),
          Text(text.disguiseWhatItDoesNotDo, style: theme.textTheme.titleSmall),
          const SizedBox(height: PrivioSpacing.sm),
          Text(
            text.disguiseNotADefence,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  String _homeScreen(AppText text) => launcher.icon && launcher.name
      ? text.disguiseHomeScreenChanges
      : text.disguiseIconUnchanged;
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
            tooltip: AppText.of(context).disguiseClosePreview,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
