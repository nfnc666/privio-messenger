import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/display_name.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// The two names of this account, side by side, doing what each of them can.
///
/// The screen is mostly an argument about which is which: the display name is
/// a field with a keyboard, and the username is a row with a copy button and
/// no way in. Putting them on the same screen is the point — somebody who
/// wants to "change their name" finds out here, in one glance, which of the
/// two they can change.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _controller = TextEditingController();

  /// What the field held when the screen opened, so Cancel has something to
  /// compare against and Save has something to be different from.
  String _opened = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final names = PrivioScope.of(context).names;
    _opened = names.displayName ?? '';
    _controller.text = _opened;
    _ready = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _changed => _controller.text.trim() != _opened.trim();

  Future<void> _save() async {
    final text = AppText.of(context);
    final names = PrivioScope.of(context).names;
    final saved = await names.save(_controller.text);
    if (!mounted) return;
    if (!saved) {
      // The field keeps what was typed. A screen that cleared it on failure
      // would lose the name *and* say it could not save it.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(names.failure?.words(text) ?? text.failureCouldNotSave)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.profileEditSaved)),
    );
    Navigator.of(context).pop();
  }

  Future<void> _copyUsername(String username) async {
    final text = AppText.of(context);
    await Clipboard.setData(ClipboardData(text: username));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.profileEditUsernameCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final state = PrivioScope.of(context);

    return ListenableBuilder(
      listenable: state.names,
      builder: (context, _) {
        final names = state.names;
        final username = names.username ?? state.username ?? '';
        final typed = _controller.text;
        final tooLong = displayNameProblem(typed) == DisplayNameProblem.tooLong;
        final left = displayNameLimit - visibleLength(cleanDisplayName(typed) ?? '');

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: Text(text.profileEditTitle),
            actions: [
              TextButton(
                // Cancel is the way out that changes nothing, and it is only
                // offered while there is something to discard.
                onPressed: _changed && !names.saving ? () => Navigator.of(context).pop() : null,
                child: Text(text.commonCancel),
              ),
              TextButton(
                onPressed: _changed && !tooLong && !names.saving ? () => unawaited(_save()) : null,
                child: names.saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(text.commonSave),
              ),
              const SizedBox(width: PrivioSpacing.xs),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
            children: [
              const SizedBox(height: PrivioSpacing.lg),
              Text(
                text.profileEditDisplayName.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.8),
              ),
              const SizedBox(height: PrivioSpacing.sm),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (_changed && !tooLong) unawaited(_save());
                },
                decoration: InputDecoration(
                  hintText: text.profileEditDisplayNameHint,
                  errorText: tooLong ? text.failureDisplayNameTooLong : null,
                  // Counted the way the limit is counted — in characters a
                  // reader would count, so one emoji is one of them.
                  counterText: left <= 10 ? text.profileEditRemaining(left) : '',
                ),
              ),
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                // Says what happens when it is empty rather than refusing to
                // be empty: no display name is a choice, not a mistake.
                text.profileEditEmptyNote(username),
                style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              SettingsSection(
                children: [
                  SettingsRow(
                    icon: Icons.alternate_email_rounded,
                    label: text.accountUsername,
                    value: username,
                    // There is no `onTap`. The row is not disabled-looking
                    // either: it is a fact about the account, and the only
                    // thing to do with a fact is take a copy of it.
                    trailing: IconButton(
                      onPressed: username.isEmpty ? null : () => unawaited(_copyUsername(username)),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: text.profileEditCopyUsername,
                      color: context.accents.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PrivioSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.sm),
                child: Text(
                  text.profileEditUsernameNote,
                  style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
                ),
              ),
              const SizedBox(height: PrivioSpacing.xxxl),
            ],
          ),
        );
      },
    );
  }
}
