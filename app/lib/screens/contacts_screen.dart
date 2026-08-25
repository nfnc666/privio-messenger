import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/models.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/search_field.dart';

/// Screen 8: contacts, addressed by username rather than phone number.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  static const List<String> _filters = ['All', 'Online'];

  int _filter = 0;
  String _query = '';

  List<Contact> get _visible {
    final query = _query.trim().toLowerCase();
    return DemoData.contacts.where((contact) {
      final matchesFilter = _filter == 0 || contact.presence == Presence.online;
      final matchesQuery = query.isEmpty ||
          contact.displayName.toLowerCase().contains(query) ||
          contact.username.contains(query);
      return matchesFilter && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _visible;

    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddContact(context),
        backgroundColor: PrivioColors.accent,
        foregroundColor: PrivioColors.background,
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
      body: Column(
        children: [
          FilterChips(
            labels: _filters,
            selectedIndex: _filter,
            onSelected: (index) => setState(() => _filter = index),
          ),
          PrivioSearchField(
            hintText: 'Search contacts',
            onChanged: (value) => setState(() => _query = value),
          ),
          Expanded(
            child: ListView.builder(
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
                    presence: contact.presence,
                  ),
                  title: Text(contact.displayName, style: Theme.of(context).textTheme.titleMedium),
                  subtitle: Text(
                    contact.presence == Presence.online ? 'Online' : 'Last seen recently',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: contact.presence == Presence.online
                              ? PrivioColors.accent
                              : PrivioColors.textTertiary,
                        ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: PrivioColors.textTertiary,
                  ),
                  onTap: () {},
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Contacts are added by exact username: there is no directory to browse and
  /// no address book to upload.
  void _showAddContact(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: PrivioRadius.card),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: PrivioSpacing.xxl,
          right: PrivioSpacing.xxl,
          top: PrivioSpacing.xxl,
          bottom: MediaQuery.viewInsetsOf(context).bottom + PrivioSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add contact', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              'Enter their exact Privio username. Nothing is uploaded from your '
              'address book, and nobody can find you by browsing.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            const TextField(
              autofocus: true,
              decoration: InputDecoration(hintText: 'username', prefixText: '@ '),
            ),
            const SizedBox(height: PrivioSpacing.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
