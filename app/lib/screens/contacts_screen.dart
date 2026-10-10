import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../l10n/channel_text.dart';
import '../models/models.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/search_field.dart';
import 'chat_screen.dart';

/// Contacts, addressed by username rather than phone number.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String _query = '';

  /// Which tab was showing when this screen last looked.
  int _lastSeenTab = _contactsTab;
  static const int _contactsTab = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PrivioScope.of(context).conversations.refreshContacts(),
    );
  }

  /// Asks again when this tab comes back into view.
  ///
  /// Without it the list is whatever it was on the first visit — which was
  /// tolerable while it held only names, and is not now that it holds a time.
  void _refreshOnReturn(AppState state) {
    final now = state.selectedTab;
    final returned = now == _contactsTab && _lastSeenTab != _contactsTab;
    _lastSeenTab = now;
    if (!returned) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(state.conversations.refreshContacts()),
    );
  }

  List<Contact> _visible(List<Contact> contacts) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return contacts;
    return contacts
        .where((contact) =>
            contact.displayName.toLowerCase().contains(query) ||
            contact.username.contains(query),)
        .toList();
  }

  Future<void> _openChat(Contact contact) async {
    final controller = PrivioScope.of(context).conversations;
    final accountId = await controller.openConversation(contact.username);
    if (accountId == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(accountId: accountId, title: contact.displayName),
      ),
    );
  }

  /// The username, and — only when the server was willing to say — when this
  /// person was last connected.
  ///
  /// The server reports a moment, so this reports a moment. It does not say
  /// "online": that would be this app inferring a state from a timestamp and
  /// presenting the guess as a fact about somebody else.
  static String _subtitleFor(AppText text, Contact contact) {
    final seen = contact.lastSeenAt;
    if (seen == null) return '@${contact.username}';
    return text.contactsLastSeen(contact.username, _when(text, seen));
  }

  static String _when(AppText text, DateTime at) {
    final now = DateTime.now();
    final difference = now.difference(at);
    if (difference.inMinutes < 1) return text.contactsSeenJustNow;
    if (difference.inMinutes < 60) return text.contactsSeenMinutes(difference.inMinutes);
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    final time = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    if (sameDay) return text.contactsSeenAtTime(time);
    if (difference.inDays < 7) return text.contactsSeenDays(difference.inDays);
    // Written the way the reader's language writes a date rather than always
    // as dd.mm.yyyy, which is one language's habit.
    return formatDate(text, at);
  }

  @override
  Widget build(BuildContext context) {
    // PrivioScope is an InheritedNotifier, so this rebuilds when the shell
    // records a tab change.
    final state = PrivioScope.of(context);
    _refreshOnReturn(state);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final contacts = _visible(state.conversations.contacts);

        return Scaffold(
          appBar: AppBar(
            // Contacts is both a tab and a screen the chat list pushes. A
            // leading widget is drawn whether or not there is anywhere to go
            // back to, so it is only supplied when there is.
            leading: Navigator.of(context).canPop()
                ? const PrivioBackButton()
                : null,
            title: Text(AppText.of(context).contactsTitle),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => unawaited(showAddContactSheet(context)),
            // A round icon with no words on it is the one thing a screen
            // reader cannot guess; this is also the long-press label.
            tooltip: AppText.of(context).contactsAddTitle,
            backgroundColor: context.accents.accent,
            foregroundColor: PrivioColors.background,
            child: const Icon(Icons.person_add_alt_1_rounded),
          ),
          body: Column(
            children: [
              PrivioSearchField(
                hintText: AppText.of(context).contactsSearch,
                onChanged: (value) => setState(() => _query = value),
              ),
              Expanded(
                child: contacts.isEmpty
                    ? (_query.trim().isEmpty
                        ? _EmptyContacts(onAdd: () => unawaited(showAddContactSheet(context)))
                        : _NoMatch(
                            query: _query,
                            onAdd: (username) =>
                                unawaited(showAddContactSheet(context, initial: username)),
                          ))
                    : ListView.builder(
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: PrivioSpacing.gutter,
                              vertical: PrivioSpacing.xs,
                            ),
                            leading: PrivioAvatar(
                              label: contact.displayName,
                              seed: contact.avatarSeed,
                              imageBytes: contact.avatarBytes,
                            ),
                            title: Text(
                              contact.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            subtitle: Text(
                              _subtitleFor(AppText.of(context), contact),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: PrivioColors.textTertiary,
                            ),
                            onTap: () => _openChat(contact),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Usernames are what [usernamePattern] allows, and nothing else is worth
/// sending to the server as one.
final RegExp usernamePattern = RegExp(r'^[a-z0-9_.]{3,32}$');

/// What somebody typed, as the username it means: no `@`, no spaces, lower case.
String normaliseUsername(String typed) {
  var name = typed.trim().toLowerCase();
  while (name.startsWith('@')) {
    name = name.substring(1).trimLeft();
  }
  return name;
}

/// Asks for a username and adds that person as a contact.
///
/// Contacts are added by exact username: there is no directory to browse and
/// no address book to upload. Returns the username that was added, or null
/// when nothing was — so a caller that wanted a conversation can open one.
///
/// The sheet's own state lives here, outside the builder. Declared inside it,
/// every rebuild reset it: the refusal was never shown and the button never
/// stopped accepting presses while a request was out.
Future<String?> showAddContactSheet(BuildContext context, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  final state = PrivioScope.of(context);
  var busy = false;
  var failure = '';

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: PrivioColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: PrivioRadius.card),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final text = AppText.of(sheetContext);

        Future<void> add() async {
          if (busy) return;
          final username = normaliseUsername(controller.text);
          if (username.isEmpty) return;
          if (!usernamePattern.hasMatch(username)) {
            setSheetState(() => failure = text.contactsCouldNotAdd);
            return;
          }
          setSheetState(() {
            busy = true;
            failure = '';
          });
          final ok = await state.conversations.addContact(username);
          if (!sheetContext.mounted) return;
          if (ok) {
            Navigator.of(sheetContext).pop(username);
          } else {
            setSheetState(() {
              busy = false;
              failure = state.conversations.failure?.words(text) ?? text.contactsCouldNotAdd;
            });
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            left: PrivioSpacing.xxl,
            right: PrivioSpacing.xxl,
            top: PrivioSpacing.xxl,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + PrivioSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.contactsAddTitle,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                text.contactsAddNote,
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: PrivioSpacing.xl),
              TextField(
                controller: controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => add(),
                onChanged: (_) {
                  if (failure.isNotEmpty) setSheetState(() => failure = '');
                },
                decoration: InputDecoration(
                  hintText: text.contactsUsernameHint,
                  prefixText: '@ ',
                ),
              ),
              if (failure.isNotEmpty) ...[
                const SizedBox(height: PrivioSpacing.md),
                Text(
                  failure,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: PrivioColors.danger),
                ),
              ],
              const SizedBox(height: PrivioSpacing.lg),
              FilledButton(
                onPressed: busy ? null : add,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PrivioColors.background,
                        ),
                      )
                    : Text(text.commonAdd),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline_rounded, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text(text.contactsEmptyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.xs),
            Text(
              text.contactsEmptyBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            FilledButton(onPressed: onAdd, child: Text(text.contactsAddTitle)),
          ],
        ),
      ),
    );
  }
}

/// A search that found nobody among the contacts.
///
/// "No contacts yet" was wrong here — there may be many — and a search box is
/// where people type the name of somebody they want to add. When what they
/// typed could be a username, adding it is one press away.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query, required this.onAdd});

  final String query;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final username = normaliseUsername(query);
    final addable = usernamePattern.hasMatch(username);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text(text.searchNoResults, style: theme.textTheme.titleMedium),
            if (addable) ...[
              const SizedBox(height: PrivioSpacing.xl),
              FilledButton.icon(
                onPressed: () => onAdd(username),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(text.contactsAddUsername(username)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
