import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/privio_back_button.dart';

/// Creating a group: a name, and who is in it.
///
/// The name is sealed before it is uploaded, so the group the server stores has
/// no readable name — which is why this screen says so rather than leaving the
/// user to wonder what the server sees.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final TextEditingController _name = TextEditingController();
  final Set<String> _selected = {};
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PrivioScope.of(context).conversations.refreshContacts(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _selected.isEmpty) return;

    setState(() => _creating = true);
    final controller = PrivioScope.of(context).conversations;
    final groupId = await controller.createGroup(name, _selected.toList());
    if (!mounted) return;

    if (groupId == null) {
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not create the group')),
      );
      return;
    }
    Navigator.of(context).pop(groupId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = PrivioScope.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final contacts = state.conversations.contacts;
        final ready = _name.text.trim().isNotEmpty && _selected.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: const Text('New group'),
            actions: [
              TextButton(
                onPressed: ready && !_creating ? _create : null,
                child: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(PrivioSpacing.gutter),
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Group name'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, size: 14, color: PrivioColors.accent),
                    const SizedBox(width: PrivioSpacing.sm),
                    Expanded(
                      child: Text(
                        'The name is encrypted. Privio stores a group it cannot name.',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: PrivioSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _selected.isEmpty
                        ? 'Choose members'
                        : '${_selected.length} selected',
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
                            'Add some contacts first — a group needs people in it.',
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
  const _MemberTile({
    required this.contact,
    required this.selected,
    required this.onChanged,
  });

  final Contact contact;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: (value) => onChanged(value ?? false),
      controlAffinity: ListTileControlAffinity.trailing,
      activeColor: PrivioColors.accent,
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
