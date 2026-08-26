import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';

/// Creating a channel.
///
/// The visibility choice is the only one on this screen with a privacy cost, so
/// it says plainly what each option gives the server. Posts are sealed either
/// way; what changes is whether the channel's *name* is discoverable.
class NewChannelScreen extends StatefulWidget {
  const NewChannelScreen({super.key});

  @override
  State<NewChannelScreen> createState() => _NewChannelScreenState();
}

class _NewChannelScreenState extends State<NewChannelScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _handle = TextEditingController();
  final TextEditingController _description = TextEditingController();

  static const List<String> _categories = [
    'News',
    'Technology',
    'Community',
    'Education',
    'Culture',
  ];

  ChannelVisibility _visibility = ChannelVisibility.private;
  String? _category;
  bool _restrictSaving = false;
  bool _creating = false;

  bool get _ready {
    if (_title.text.trim().isEmpty) return false;
    if (_visibility == ChannelVisibility.public && _handle.text.trim().length < 3) return false;
    return true;
  }

  @override
  void dispose() {
    _title.dispose();
    _handle.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    final controller = PrivioScope.of(context).channels;
    final created = await controller.create(
      visibility: _visibility,
      title: _title.text.trim(),
      handle: _visibility == ChannelVisibility.public ? _handle.text.trim() : null,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      category: _category,
      restrictSaving: _restrictSaving,
    );
    if (!mounted) return;

    if (created == null) {
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not create the channel')),
      );
      return;
    }
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPublic = _visibility == ChannelVisibility.public;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New channel'),
        actions: [
          TextButton(
            onPressed: _ready && !_creating ? _create : null,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
          const SizedBox(width: PrivioSpacing.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(PrivioSpacing.gutter),
        children: [
          TextField(
            controller: _title,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Channel name'),
          ),
          const SizedBox(height: PrivioSpacing.lg),

          _VisibilityCard(
            visibility: _visibility,
            onChanged: (value) => setState(() => _visibility = value),
          ),

          if (isPublic) ...[
            const SizedBox(height: PrivioSpacing.lg),
            TextField(
              controller: _handle,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Handle',
                prefixText: '@',
                helperText: '3-32 characters: a-z, 0-9, underscore or dot',
              ),
            ),
            const SizedBox(height: PrivioSpacing.lg),
            TextField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: PrivioSpacing.lg),
            Text('Category', style: theme.textTheme.labelLarge),
            const SizedBox(height: PrivioSpacing.sm),
            Wrap(
              spacing: PrivioSpacing.sm,
              runSpacing: PrivioSpacing.sm,
              children: [
                for (final category in _categories)
                  ChoiceChip(
                    label: Text(category),
                    selected: _category == category,
                    onSelected: (selected) =>
                        setState(() => _category = selected ? category : null),
                  ),
              ],
            ),
          ],

          const SizedBox(height: PrivioSpacing.lg),
          SwitchListTile(
            value: _restrictSaving,
            onChanged: (value) => setState(() => _restrictSaving = value),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: PrivioColors.accent,
            title: const Text('Restrict saving'),
            subtitle: Text(
              'Asks readers’ apps not to save or forward posts. A request, not '
              'a guarantee — anyone who can read a post can photograph it.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisibilityCard extends StatelessWidget {
  const _VisibilityCard({required this.visibility, required this.onChanged});

  final ChannelVisibility visibility;
  final ValueChanged<ChannelVisibility> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PrivioColors.surfaceRaised,
        borderRadius: BorderRadius.all(PrivioRadius.card),
      ),
      child: Column(
        children: [
          _Option(
            selected: visibility == ChannelVisibility.private,
            onTap: () => onChanged(ChannelVisibility.private),
            icon: Icons.lock_rounded,
            title: 'Private',
            body: 'Reachable only with an invite link. The name is uploaded '
                'encrypted, so the server stores a channel it cannot name.',
          ),
          const Divider(height: 1, color: PrivioColors.border),
          _Option(
            selected: visibility == ChannelVisibility.public,
            onTap: () => onChanged(ChannelVisibility.public),
            icon: Icons.public_rounded,
            title: 'Public',
            body: 'Listed and searchable. The name, handle and description are '
                'public by definition; the posts stay end-to-end encrypted.',
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.title,
    required this.body,
  });

  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: selected ? PrivioColors.accent : PrivioColors.textTertiary),
            const SizedBox(width: PrivioSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: PrivioSpacing.xs),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, size: 20, color: PrivioColors.accent),
          ],
        ),
      ),
    );
  }
}
