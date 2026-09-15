import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/phone_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/privio_colors.dart';
import '../widgets/phone_field.dart';
import '../widgets/phone_verify_sheet.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Settings → Privacy → Phone number & contacts.
///
/// Everything about the optional number in one place: add it, change it, remove
/// it, and the **two separate switches** — being findable, and syncing the
/// address book. They are two decisions and the screen keeps them apart, each
/// with the paragraph that says what it actually does.
class PhoneContactsScreen extends StatefulWidget {
  const PhoneContactsScreen({super.key});

  @override
  State<PhoneContactsScreen> createState() => _PhoneContactsScreenState();
}

class _PhoneContactsScreenState extends State<PhoneContactsScreen> {
  final TextEditingController _number = TextEditingController();
  final GlobalKey<PhoneFieldState> _field = GlobalKey<PhoneFieldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = PrivioScope.of(context);
      final account = state.accountId;
      if (account != null) unawaited(state.phone.load(account));
    });
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Asks for a number, sends a code, then opens the sheet.
  Future<void> _addOrChange(PhoneController controller) async {
    final text = AppText.of(context);
    _number.clear();

    final entered = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(controller.link.linked ? text.phoneChange : text.phoneAdd),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhoneField(key: _field, controller: _number, autofocus: true),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              text.phoneFieldExplain,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: PrivioColors.textTertiary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.phoneVerifyConfirm),
          ),
        ],
      ),
    );
    if (entered != true || !mounted) return;

    final number = _field.currentState?.value;
    if (number == null) {
      _say(text.failurePhoneInvalid);
      return;
    }

    if (!await controller.requestCode(number.e164)) {
      if (mounted) _say(controller.failure?.words(text) ?? text.failureUnexpected);
      return;
    }
    if (!mounted) return;

    // A number is linked only if the sheet says so. Backing out leaves the
    // account exactly as it was, which is a complete account.
    await showPhoneVerifySheet(context, controller);
  }

  Future<void> _remove(PhoneController controller) async {
    final text = AppText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.phoneRemove),
        content: Text(text.phoneRemoveExplain),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.phoneRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await controller.removeNumber() && mounted) {
      _say(controller.failure?.words(text) ?? text.failureUnexpected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).phone;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.privacyPhoneSection),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final link = controller.link;
          return ListView(
            padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
            children: [
              const SizedBox(height: PrivioSpacing.sm),
              SettingsSection(
                children: [
                  SettingsRow(
                    icon: Icons.phone_outlined,
                    label: link.linked ? text.phoneChange : text.phoneAdd,
                    value: link.hint ?? text.phoneNotLinkedYet,
                    // A server with no SMS provider cannot verify anything, so
                    // the row says so rather than offering a button that always
                    // fails. See `failurePhoneSmsUnavailable`.
                    enabled: link.canVerify && !controller.busy,
                    onTap: () => _addOrChange(controller),
                  ),
                  if (link.linked)
                    SettingsRow(
                      label: text.phoneRemove,
                      destructive: true,
                      enabled: !controller.busy,
                      onTap: () => _remove(controller),
                    ),
                ],
              ),
              if (!link.canVerify) _Note(text: text.failurePhoneSmsUnavailable),

              SettingsSection(
                caption: text.privacyPhoneSection,
                children: [
                  SettingsRow(
                    icon: Icons.person_search_outlined,
                    label: text.phoneDiscoverable,
                    // Only meaningful with a verified number behind it. Shown
                    // rather than hidden, so the switch is where somebody
                    // expects it once they add one.
                    enabled: link.linked && !controller.busy,
                    trailing: Switch.adaptive(
                      value: link.discoverable,
                      onChanged: link.linked && !controller.busy
                          ? (on) => unawaited(controller.setDiscoverable(on))
                          : null,
                    ),
                  ),
                ],
              ),
              _Note(text: text.phoneDiscoverableExplain),

              SettingsSection(
                children: [
                  SettingsRow(
                    icon: Icons.contacts_outlined,
                    label: text.phoneContactSync,
                    enabled: !controller.busy,
                    trailing: Switch.adaptive(
                      value: link.contactSync,
                      onChanged: controller.busy
                          ? null
                          : (on) => unawaited(controller.setContactSync(on)),
                    ),
                  ),
                ],
              ),
              _Note(text: text.phoneContactSyncExplain),

              if (controller.failure != null)
                _Note(text: controller.failure!.words(text), danger: true),
            ],
          );
        },
      ),
    );
  }
}

/// A paragraph under a switch.
class _Note extends StatelessWidget {
  const _Note({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.xl,
          PrivioSpacing.sm,
          PrivioSpacing.xl,
          PrivioSpacing.lg,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: danger ? PrivioColors.danger : PrivioColors.textTertiary,
              ),
        ),
      );
}
