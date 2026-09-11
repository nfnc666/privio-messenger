import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../media/avatar.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';

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

  /// The picture, already prepared, waiting for the channel to exist.
  ///
  /// It cannot be uploaded before creation: a private channel's picture is
  /// sealed with the channel key, and there is no channel and no key until the
  /// Create button has been pressed. So it is held here and set immediately
  /// afterwards — and shown here so what is being held is visible.
  Uint8List? _picture;

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

  Future<void> _pickPicture() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.image,
      ).timeout(const Duration(minutes: 2));
    } on Object catch (failure) {
      if (mounted) _say('Could not open the picker: $failure');
      return;
    }
    if (picked == null || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object catch (failure) {
      if (mounted) _say('Could not read ${picked.name}: $failure');
      return;
    }
    if (!mounted) return;

    // Prepared here rather than at upload, so a file that is not a picture is
    // refused while the person is still looking at the picker they chose it
    // from — not a minute later, after a channel has already been created.
    final prepared = AvatarImage.prepare(bytes);
    if (prepared == null) {
      _say('That file is not an image Privio can use.');
      return;
    }
    setState(() => _picture = prepared);
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

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

    // The channel exists now, so the picture can be sealed with its key and
    // uploaded. A failure here does not undo the channel: it is a channel
    // without a picture, which is a thing somebody can fix from the menu, and
    // throwing away a created channel over an image would be much worse.
    final picture = _picture;
    if (picture != null) {
      final ok = await controller.setAvatar(created, picture);
      if (!mounted) return;
      if (!ok) _say(controller.error ?? 'The channel was created without the picture.');
    }
    if (!mounted) return;
    Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPublic = _visibility == ChannelVisibility.public;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
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
          Row(
            children: [
              _PicturePicker(
                picture: _picture,
                isPublic: isPublic,
                onTap: _pickPicture,
                onClear: _picture == null ? null : () => setState(() => _picture = null),
              ),
              const SizedBox(width: PrivioSpacing.md),
              Expanded(
                child: TextField(
                  controller: _title,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Channel name'),
                ),
              ),
            ],
          ),
          if (_picture != null && isPublic) ...[
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              'A public channel\'s picture is shown on its web page and in link '
              'previews, so it is stored unencrypted — the same as its name, '
              'handle and description.',
              style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
            ),
          ],
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

/// The square that shows the chosen picture, or invites one.
///
/// A rounded square rather than a circle, matching every other place a channel
/// is drawn: a circle is a person in this app, and a channel wearing one reads
/// as somebody messaging you.
class _PicturePicker extends StatelessWidget {
  const _PicturePicker({
    required this.picture,
    required this.isPublic,
    required this.onTap,
    this.onClear,
  });

  final Uint8List? picture;
  final bool isPublic;
  final VoidCallback onTap;

  /// Null until there is something to clear.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    const side = 64.0;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onClear,
      child: Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: PrivioColors.accentSurface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: picture == null
            ? Icon(
                isPublic ? Icons.campaign_rounded : Icons.lock_rounded,
                color: PrivioColors.accentBright,
                size: 26,
              )
            : Image.memory(picture!, width: side, height: side, fit: BoxFit.cover),
      ),
    );
  }
}
