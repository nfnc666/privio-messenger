import 'package:flutter/material.dart';
import '../network/proxy_controller.dart';
import 'proxy_screen.dart';

import '../theme/accent.dart';
import '../theme/motion.dart';
import '../theme/privio_colors.dart';
import '../core/locale_controller.dart';
import '../l10n/app_localizations.dart';
import '../widgets/appear.dart';
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
    this.onLanguageChosen,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;
  final VoidCallback onImportBackup;

  /// What to do when somebody picks a language. The first screen of the app
  /// is in English; somebody who does not read it should not have to get
  /// through it to find the setting.
  final ValueChanged<AppLanguage>? onLanguageChosen;

  /// The language this screen is actually drawn in, read from the screen
  /// rather than handed in — a value handed in went stale the moment the
  /// language changed under it, and the button kept saying "English".
  static AppLanguage _shown(BuildContext context) =>
      AppLanguage.forCode(Localizations.localeOf(context).languageCode) ?? AppLanguage.fallback;

  Future<void> _pickLanguage(BuildContext context) async {
    final text = AppText.of(context);
    final language = _shown(context);
    final picked = await showModalBottomSheet<AppLanguage>(
      context: context,
      backgroundColor: PrivioColors.surface,
      // Five languages and a title are more than half of a short screen.
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(PrivioSpacing.lg),
                child: Text(text.languagePickerTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              for (final option in AppLanguage.values)
                ListTile(
                  title: Text(option.endonym),
                  trailing: option == language
                      ? Icon(Icons.check_rounded, color: sheetContext.accents.accent)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
              const SizedBox(height: PrivioSpacing.sm),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onLanguageChosen?.call(picked);
  }

  /// The four lines under the mark, paired with their icons.
  ///
  /// Built here rather than held in a const list: a const list would have to
  /// hold the English sentence, and these are read at the one moment the app
  /// is making its case.
  static List<(IconData, String)> _promises(AppText text) => [
        (Icons.lock_rounded, text.welcomePromiseEncrypted),
        (Icons.phone_disabled_rounded, text.welcomePromiseNoPhone),
        (Icons.verified_user_outlined, text.welcomePromiseControl),
        (Icons.shield_outlined, text.welcomePromiseByDesign),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Scaffold(
      body: SafeArea(
        // Fills the screen where it fits, and scrolls where it does not — a
        // small phone with large text, or one held sideways, ran out of room
        // and cut off the last buttons.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (onLanguageChosen != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _pickLanguage(context),
                            icon: const Icon(Icons.language_rounded, size: 18),
                            // Named in its own language, which is the word somebody
                            // looking for theirs will recognise.
                            label: Text(_shown(context).endonym),
                          ),
                        ),
                      const Spacer(flex: 2),
                      // The first thing anybody sees of Privio: the mark grows in,
                      // then the name, then the promises one after another — read in
                      // the order they arrive. Under a second in all, and only a fade
                      // when the device asks for less motion.
                      const Appear(
                        duration: PrivioMotion.gentle,
                        scale: 0.7,
                        child: PrivioMark(size: 72, glow: true),
                      ),
                      const SizedBox(height: PrivioSpacing.xl),
                      Appear(
                        delay: const Duration(milliseconds: 150),
                        child: Column(
                          children: [
                            Text(text.welcomeTo, style: theme.textTheme.bodyMedium),
                            Text(
                              'Privio',
                              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: PrivioSpacing.xxxl),
                      for (final (index, (icon, label)) in _promises(text).indexed)
                        Appear(
                          delay: Duration(milliseconds: 260 + 90 * index),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: PrivioSpacing.lg),
                            child: Row(
                              children: [
                                Icon(icon, size: 18, color: context.accents.accent),
                                const SizedBox(width: PrivioSpacing.md),
                                // Wraps rather than running off a narrow screen at large text.
                                Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
                              ],
                            ),
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
                      FilledButton(onPressed: onGetStarted, child: Text(text.welcomeGetStarted)),
                      const SizedBox(height: PrivioSpacing.sm),
                      // Somebody who already has an account is not a new user, and had
                      // to work that out for themselves: the only ways in were a button
                      // that says it creates an account, and one that says it imports a
                      // backup. Reinstalling, or adding a second device, is not an
                      // unusual thing to be doing on this screen.
                      TextButton(onPressed: onSignIn, child: Text(text.welcomeHaveAccount)),
                      if (ProxyController.supported)
                        TextButton(onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const ProxyScreen())),
                          child: Text(text.proxyTitle)),
                      TextButton(
                        onPressed: onImportBackup,
                        child: Text(text.welcomeImportBackup),
                      ),
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
