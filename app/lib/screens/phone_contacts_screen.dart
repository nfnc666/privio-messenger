import 'dart:async';

import 'package:flutter/material.dart';

import '../contacts/address_book.dart';
import '../core/app_state.dart';
import '../core/phone_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/phone_field.dart';
import '../widgets/phone_verify_sheet.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import 'contact_profile_screen.dart';

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

  /// True while a match is running, so the row cannot start a second one.
  bool _matching = false;

  /// What the last match found, or null if none has been run on this screen.
  ///
  /// Null and empty are different and the screen says so differently: nothing
  /// has been asked, against asked and nobody in the address book is here.
  List<DiscoveredContact>? _matches;

  /// Which account the list above belongs to.
  ///
  /// A match is a list of people *this* account may write to, so it must not
  /// survive a switch. Checked on every build rather than cleared on an event,
  /// because the switch can happen while this screen is on top.
  String? _matchesFor;

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

  /// Matches the address book against Privio accounts.
  ///
  /// The order is the whole privacy design and it is worth reading in one go:
  ///
  ///  1. The account's own **consent** must already be on. This is checked
  ///     before anything else and the row is not even offered without it —
  ///     the app never asks the operating system about contacts on its own
  ///     initiative.
  ///  2. Only then is the **operating system** asked, at the moment the button
  ///     is pressed, by the one piece of code in the app that touches the
  ///     address book.
  ///  3. The numbers are **blinded on this device**. `PhoneController.discover`
  ///     hashes each one and sends hashes; a plaintext number never goes to the
  ///     server. What that is worth, and what it is not, is written out in
  ///     `docs/phone-contacts.md`.
  ///  4. Nothing is kept. The numbers are not stored, the matches live in this
  ///     screen's state, and leaving the screen drops them.
  Future<void> _matchContacts(AppState state, PhoneController controller) async {
    final text = AppText.of(context);
    if (!controller.link.contactSync || _matching) return;

    setState(() => _matching = true);
    final read = await state.services.addressBook.read();
    if (!mounted) return;

    switch (read) {
      case AddressBookDenied():
        setState(() => _matching = false);
        // Not a dead end, and the sentence says so: a PRIVIO ID, an invite
        // link and a QR code all still add somebody.
        _say(text.failureContactsPermissionDenied);
        return;
      case AddressBookUnsupported():
        setState(() => _matching = false);
        _say(text.contactMatchUnsupported);
        return;
      case AddressBookNumbers(:final numbers):
        final account = state.accountId;
        final found = await controller.discover(numbers);
        if (!mounted) return;
        setState(() {
          _matching = false;
          // Filed under the account it was read for. A match that came back
          // after a switch belongs to nobody on this screen.
          _matchesFor = account;
          _matches = found;
        });
        if (found == null) {
          _say(controller.failure?.words(text) ?? text.failureUnexpected);
        }
    }
  }

  Future<void> _addMatch(AppState state, DiscoveredContact match) async {
    final text = AppText.of(context);
    final added = await state.conversations.addContact(match.username);
    if (!mounted) return;
    _say(added ? text.profileContactAdded : text.profileCouldNotAddContact);
    if (added) setState(() {});
  }

  /// Flips the consent, and drops any matches when it goes off.
  ///
  /// Turning the switch off is a withdrawal of consent, so what the consent
  /// produced goes with it rather than staying on screen until somebody leaves
  /// the page.
  Future<void> _setContactSync(PhoneController controller, bool on) async {
    await controller.setContactSync(on);
    if (!mounted || on) return;
    setState(() {
      _matches = null;
      _matchesFor = null;
    });
  }

  /// What the last match found, as rows.
  ///
  /// Returns nothing at all until a match has been run — and nothing for a list
  /// that belongs to a different account, which is what stops one account's
  /// results being read by the next.
  List<Widget> _matchResults(AppState state, AppText text) {
    final matches = _matches;
    if (matches == null || _matchesFor != state.accountId) return const [];
    if (matches.isEmpty) {
      return [_Note(text: text.contactMatchNobody)];
    }

    final known = {for (final contact in state.conversations.contacts) contact.id};
    return [
      SettingsSection(
        caption: text.contactMatchFound(matches.length),
        children: [
          for (final match in matches)
            // Its own Material, because `SettingsSection` draws the card this
            // sits in: a ListTile paints its splash on the nearest Material
            // ancestor, and without one here that is above the card's
            // decoration, so the touch feedback would be painted over. Flutter
            // asserts on exactly this rather than letting it look merely dull.
            Material(
              color: Colors.transparent,
              child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: PrivioSpacing.gutter,
              ),
              leading: PrivioAvatar(
                label: match.displayName ?? match.username,
                seed: match.accountId.hashCode.abs(),
                imageBytes: state.conversations.avatarFor(match.accountId),
              ),
              title: Text(
                match.displayName ?? match.username,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              subtitle: Text(
                '@${match.username}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              // Already in the address book: nothing to add, and the row still
              // opens the profile, which is the useful thing left to do with
              // somebody a match found.
              trailing: known.contains(match.accountId)
                  ? const Icon(Icons.check_rounded, color: PrivioColors.textTertiary)
                  : TextButton(
                      onPressed: () => unawaited(_addMatch(state, match)),
                      child: Text(text.commonAdd),
                    ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ContactProfileScreen(
                    accountId: match.accountId,
                  ),
                ),
              ),
              ),
            ),
        ],
      ),
      _Note(text: text.contactMatchNote),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final state = PrivioScope.of(context);
    final controller = state.phone;

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
                      // Consent, and consent only. Turning it on reads nothing
                      // and asks the operating system for nothing: it is the
                      // permission to offer the match below, which somebody
                      // still has to press.
                      onChanged: controller.busy
                          ? null
                          : (on) => unawaited(_setContactSync(controller, on)),
                    ),
                  ),
                  // Offered only once the consent above is on. A row that was
                  // always there and refused would be teaching people to press
                  // it and be told no.
                  if (link.contactSync)
                    SettingsRow(
                      icon: Icons.sync_rounded,
                      label: text.contactMatchNow,
                      // A deployment with no discovery key cannot match
                      // anything — the row says so rather than failing on a
                      // press. See `failurePhoneDiscoveryUnavailable`.
                      enabled: link.discoveryAvailable && !_matching && !controller.busy,
                      value: _matching ? text.contactMatchRunning : null,
                      onTap: () => unawaited(_matchContacts(state, controller)),
                    ),
                ],
              ),
              _Note(text: text.phoneContactSyncExplain),
              if (link.contactSync && !link.discoveryAvailable)
                _Note(text: text.failurePhoneDiscoveryUnavailable),
              ..._matchResults(state, text),

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
