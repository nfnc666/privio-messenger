import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../models/distribution_list.dart';
import '../models/models.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/privio_back_button.dart';

/// This device's distribution lists, and the way to make one.
class DistributionListsScreen extends StatelessWidget {
  const DistributionListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final lists = state.conversations.distributionLists;
        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: Text(text.listsTitle),
          ),
          floatingActionButton: FloatingActionButton(
            key: const Key('lists-new'),
            tooltip: text.listsNew,
            backgroundColor: context.accents.accent,
            foregroundColor: PrivioColors.background,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DistributionListEditScreen()),
            ),
            child: const Icon(Icons.add_rounded),
          ),
          body: lists.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(PrivioSpacing.xxxl),
                    child: Text(
                      text.listsEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: PrivioColors.textSecondary),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: lists.length,
                  itemBuilder: (context, index) {
                    final list = lists[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                      leading: Icon(Icons.campaign_outlined, color: context.accents.accent),
                      title: Text(list.name, style: theme.textTheme.titleMedium),
                      subtitle: Text(text.listsMembers(list.memberIds.length)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DistributionListScreen(listId: list.id),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// One list: who is on it, what reaches them and how, and a field to write to
/// all of them.
class DistributionListScreen extends StatefulWidget {
  const DistributionListScreen({super.key, required this.listId});

  final String listId;

  @override
  State<DistributionListScreen> createState() => _DistributionListScreenState();
}

class _DistributionListScreenState extends State<DistributionListScreen> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _message.text;
    if (body.trim().isEmpty || _sending) return;
    final state = PrivioScope.of(context);
    final text = AppText.of(context);
    setState(() => _sending = true);
    final reached = await state.conversations.sendToList(widget.listId, body);
    if (!mounted) return;
    setState(() => _sending = false);
    _message.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text.listsSent(reached))));
  }

  Future<void> _delete() async {
    final text = AppText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.listsDelete),
        content: Text(text.listsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    PrivioScope.of(context).conversations.deleteDistributionList(widget.listId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final list = state.conversations.distributionList(widget.listId);
        if (list == null) return const SizedBox.shrink();
        final contacts = {for (final contact in state.conversations.contacts) contact.id: contact};
        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: Text(list.name),
            actions: [
              IconButton(
                key: const Key('list-edit'),
                tooltip: text.commonEdit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DistributionListEditScreen(listId: list.id),
                  ),
                ),
              ),
              IconButton(
                key: const Key('list-delete'),
                tooltip: text.listsDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _delete,
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(PrivioSpacing.gutter),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_rounded, size: 14, color: context.accents.accent),
                    const SizedBox(width: PrivioSpacing.sm),
                    Expanded(child: Text(text.listsNote, style: theme.textTheme.labelSmall)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final id in list.memberIds)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                        leading: PrivioAvatar(
                          label: contacts[id]?.displayName ??
                              state.services.store.conversationWith(id)?.title ??
                              id,
                          seed: id.hashCode.abs(),
                          imageBytes: contacts[id]?.avatarBytes,
                        ),
                        title: Text(
                          contacts[id]?.displayName ??
                              state.services.store.conversationWith(id)?.title ??
                              id,
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(PrivioSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('list-message'),
                          controller: _message,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(hintText: text.listsMessageHint),
                        ),
                      ),
                      IconButton(
                        key: const Key('list-send'),
                        tooltip: text.listsSend,
                        icon: Icon(Icons.send_rounded, color: context.accents.accent),
                        onPressed: _sending ? null : _send,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Making a list, or changing one: a name, and who is on it.
class DistributionListEditScreen extends StatefulWidget {
  const DistributionListEditScreen({super.key, this.listId});

  /// Null for a new list.
  final String? listId;

  @override
  State<DistributionListEditScreen> createState() => _DistributionListEditScreenState();
}

class _DistributionListEditScreenState extends State<DistributionListEditScreen> {
  final _name = TextEditingController();
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final conversations = PrivioScope.of(context).conversations;
      final existing = widget.listId == null ? null : conversations.distributionList(widget.listId!);
      if (existing != null) {
        setState(() {
          _name.text = existing.name;
          _selected.addAll(existing.memberIds);
        });
      }
      conversations.refreshContacts();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final conversations = PrivioScope.of(context).conversations;
    final id = widget.listId;
    final saved = id == null
        ? conversations.createDistributionList(_name.text, _selected) != null
        : conversations.updateDistributionList(id, name: _name.text, accountIds: _selected);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppText.of(context).listsInvalid)),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final contacts = state.conversations.contacts;
        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: Text(widget.listId == null ? text.listsNew : text.listsEdit),
            actions: [
              TextButton(
                key: const Key('list-save'),
                onPressed: _save,
                child: Text(text.commonSave),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(PrivioSpacing.gutter),
                child: TextField(
                  key: const Key('list-name'),
                  controller: _name,
                  maxLength: DistributionList.maxNameLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: text.listsName),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text.groupSelectedCount(_selected.length),
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ),
              Expanded(
                child: contacts.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(PrivioSpacing.xxxl),
                          child: Text(
                            text.listsNoContacts,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: contacts.length,
                        itemBuilder: (context, index) => _MemberTile(
                          contact: contacts[index],
                          selected: _selected.contains(contacts[index].id),
                          onChanged: (chosen) => setState(() {
                            if (chosen) {
                              _selected.add(contacts[index].id);
                            } else {
                              _selected.remove(contacts[index].id);
                            }
                          }),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.contact, required this.selected, required this.onChanged});

  final Contact contact;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: (value) => onChanged(value ?? false),
      controlAffinity: ListTileControlAffinity.trailing,
      activeColor: context.accents.accent,
      checkColor: PrivioColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
      secondary: PrivioAvatar(
        label: contact.displayName,
        seed: contact.avatarSeed,
        imageBytes: contact.avatarBytes,
      ),
      title: Text(contact.displayName, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text('@${contact.username}', style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
