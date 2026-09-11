import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';
import '../widgets/channel_avatar.dart';
import '../widgets/settings_row.dart';
import 'channel_admins_screen.dart';
import 'channel_subscribers_screen.dart';

/// Editing a channel: its picture, its name, and everything it offers.
///
/// Cancel and Done rather than a screen that saves as you type, because half of
/// what is on here changes what other people see — a name, a welcome message,
/// whether posts carry a signature — and backing out of that has to be
/// possible. Nothing here touches the server until Done.
class ChannelEditScreen extends StatefulWidget {
  const ChannelEditScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelEditScreen> createState() => _ChannelEditScreenState();
}

class _ChannelEditScreenState extends State<ChannelEditScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.channel.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.channel.description ?? '');
  late final TextEditingController _welcome =
      TextEditingController(text: widget.channel.welcome.message ?? '');

  late bool _showSenderName = widget.channel.showSenderName;
  late bool _welcomeEnabled = widget.channel.welcome.enabled;
  late bool _directMessages = widget.channel.directMessagesEnabled;
  late String? _accent = widget.channel.appearance.accent;
  late String? _background = widget.channel.appearance.background;

  /// A picture chosen but not yet uploaded, and whether Done should remove the
  /// one that is there. Both are part of the draft: cancelling must leave the
  /// channel's picture exactly as it was.
  Uint8List? _pendingPicture;
  bool _removePicture = false;

  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _welcome.dispose();
    super.dispose();
  }

  ChannelInfo get _channel =>
      PrivioScope.of(context).channels.channelById(widget.channel.id) ?? widget.channel;

  bool get _dirty =>
      _title.text.trim() != _channel.title ||
      _description.text.trim() != (_channel.description ?? '') ||
      _welcome.text.trim() != (_channel.welcome.message ?? '') ||
      _showSenderName != _channel.showSenderName ||
      _welcomeEnabled != _channel.welcome.enabled ||
      _directMessages != _channel.directMessagesEnabled ||
      _accent != _channel.appearance.accent ||
      _background != _channel.appearance.background ||
      _pendingPicture != null ||
      _removePicture;

  Future<void> _cancel() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Discard your changes?'),
        content: const Text('Nothing here has been saved yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard', style: TextStyle(color: PrivioColors.danger)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final channel = _channel;
    final controller = PrivioScope.of(context).channels;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _say('A channel needs a name.');
      return;
    }

    setState(() => _saving = true);
    try {
      // The picture first: it is a separate upload, and a failed one must not
      // take the text changes down with it.
      if (_removePicture) {
        await controller.clearAvatar(channel);
      } else if (_pendingPicture != null) {
        if (!await controller.setAvatar(channel, _pendingPicture!)) {
          _say(controller.error ?? 'Could not use that picture.');
          return;
        }
      }

      final saved = await controller.saveSettings(
        channel,
        title: title,
        description: _description.text.trim(),
        showSenderName: _showSenderName,
        welcomeEnabled: _welcomeEnabled,
        welcomeMessage: _welcome.text.trim(),
        clearAccent: _accent == null,
        accent: _accent,
        clearBackground: _background == null,
        background: _background,
        directMessagesEnabled: _directMessages,
      );
      if (!mounted) return;
      if (!saved) {
        _say(controller.error ?? 'Could not save those changes.');
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _choosePicture() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a picture'),
              onTap: () => Navigator.of(sheetContext).pop('pick'),
            ),
            if (_channel.hasAvatar || _pendingPicture != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: PrivioColors.danger),
                title: const Text('Remove it', style: TextStyle(color: PrivioColors.danger)),
                onTap: () => Navigator.of(sheetContext).pop('remove'),
              ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'remove') {
      setState(() {
        _pendingPicture = null;
        _removePicture = true;
      });
      return;
    }

    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.image)
          .timeout(const Duration(minutes: 2));
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

    // Said before it happens, not after. A public channel's picture is not
    // encrypted — it is drawn on the invite page and in link previews, where
    // nobody holds a key — and that is a real difference from the rest of
    // this app.
    if (_channel.isPublic) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: PrivioColors.surfaceRaised,
          title: const Text('This picture will be public'),
          content: const Text(
            "A public channel's picture is shown on its web page and in link "
            'previews, so it is stored unencrypted — the same as its name, '
            'handle and description. Posts stay end-to-end encrypted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Use it'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() {
      _pendingPicture = bytes;
      _removePicture = false;
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final controller = state.channels;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final channel = _channel;
        final theme = Theme.of(context);

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            automaticallyImplyLeading: false,
            leading: TextButton(
              onPressed: _saving ? null : () => unawaited(_cancel()),
              child: const Text('Cancel'),
            ),
            leadingWidth: 96,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: PrivioSpacing.md),
                child: TextButton(
                  onPressed: _saving ? null : () => unawaited(_save()),
                  style: TextButton.styleFrom(
                    backgroundColor: PrivioColors.surfaceRaised,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: PrivioSpacing.lg,
                      vertical: PrivioSpacing.sm,
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Done'),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
            children: [
              // --- Picture ---
              Center(
                child: _removePicture
                    ? const _NoPicture()
                    : _pendingPicture != null
                        ? ClipOval(
                            child: Image.memory(
                              _pendingPicture!,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                            ),
                          )
                        : ChannelAvatar(
                            channel: channel,
                            imageBytes: controller.avatarFor(channel),
                            size: 88,
                          ),
              ),
              const SizedBox(height: PrivioSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () => unawaited(_choosePicture()),
                  child: const Text('Change picture'),
                ),
              ),
              const SizedBox(height: PrivioSpacing.md),

              // --- Name and description ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                child: _Card(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PrivioSpacing.lg,
                        vertical: PrivioSpacing.xs,
                      ),
                      child: TextField(
                        controller: _title,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 64,
                        decoration: const InputDecoration(
                          hintText: 'Channel name',
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                    const _Hairline(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PrivioSpacing.lg,
                        vertical: PrivioSpacing.xs,
                      ),
                      child: TextField(
                        controller: _description,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 4,
                        minLines: 1,
                        maxLength: 512,
                        decoration: const InputDecoration(
                          hintText: 'Description',
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!channel.isPublic)
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    PrivioSpacing.xl,
                    PrivioSpacing.sm,
                    PrivioSpacing.xl,
                    0,
                  ),
                  child: Text(
                    'This channel is private, so its name is encrypted with the '
                    'channel key. Renaming it re-seals that for every member.',
                    style: TextStyle(color: PrivioColors.textTertiary, fontSize: 12),
                  ),
                ),
              const SizedBox(height: PrivioSpacing.lg),

              // --- What the channel offers ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                child: _Card(
                  children: [
                    SettingsRow(
                      icon: Icons.campaign_rounded,
                      iconTint: const Color(0xFF2563EB),
                      label: 'Channel type',
                      value: channel.isPublic ? 'Public' : 'Private',
                      onTap: () => unawaited(_openVisibility()),
                    ),
                    const _Hairline(),
                    SettingsRow(
                      icon: Icons.forum_rounded,
                      iconTint: PrivioColors.accent,
                      label: 'Discussion',
                      value: channel.commentsEnabled ? 'On' : 'Add',
                      onTap: () => unawaited(_openDiscussion()),
                    ),
                    const _Hairline(),
                    SettingsRow(
                      icon: Icons.favorite_rounded,
                      iconTint: const Color(0xFFE11D48),
                      label: 'Reactions',
                      value: '${channel.reactionEmojis.length} emoji',
                      onTap: () => Navigator.of(context).pop('reactions'),
                    ),
                    const _Hairline(),
                    SettingsRow(
                      icon: Icons.waving_hand_rounded,
                      iconTint: const Color(0xFF7C3AED),
                      label: 'Welcome message',
                      value: _welcomeEnabled ? 'On' : 'Off',
                      onTap: () => unawaited(_openWelcome()),
                    ),
                    const _Hairline(),
                    SettingsRow(
                      icon: Icons.brush_rounded,
                      iconTint: const Color(0xFFD97706),
                      label: 'Appearance',
                      value: _accent == null && _background == null ? 'Default' : 'Custom',
                      onTap: () => unawaited(_openAppearance()),
                    ),
                    const _Hairline(),
                    SettingsRow(
                      icon: Icons.translate_rounded,
                      iconTint: const Color(0xFF9333EA),
                      label: 'Auto-translation',
                      value: 'Unavailable',
                      onTap: () => unawaited(_explainTranslation()),
                    ),
                    const _Hairline(),
                    SettingsRow(
                      icon: Icons.chat_bubble_rounded,
                      iconTint: const Color(0xFF4F46E5),
                      label: 'Direct messages',
                      value: _directMessages ? 'On' : 'Off',
                      trailing: Switch(
                        value: _directMessages,
                        onChanged: (on) => setState(() => _directMessages = on),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: PrivioSpacing.lg),

              // --- Who runs it ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                child: _Card(
                  children: [
                    SettingsRow(
                      icon: Icons.shield_rounded,
                      iconTint: PrivioColors.accent,
                      label: 'Administrators',
                      value: '${controller.adminsOf(channel.id).length}',
                      onTap: () => unawaited(
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ChannelAdminsScreen(channel: channel),
                          ),
                        ),
                      ),
                    ),
                    const _Hairline(),
                    SettingsRow(
                      icon: Icons.people_alt_rounded,
                      iconTint: const Color(0xFF2563EB),
                      label: 'Subscribers',
                      value: '${channel.memberCount}',
                      onTap: () => unawaited(
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ChannelSubscribersScreen(channel: channel),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: PrivioSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xl),
                child: Text(
                  'Signed posts show the name of whoever wrote them. With it '
                  'off, everything the channel publishes is published by the '
                  'channel.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: PrivioColors.textTertiary),
                ),
              ),
              const SizedBox(height: PrivioSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                child: _Card(
                  children: [
                    SettingsRow(
                      label: 'Show sender name',
                      trailing: Switch(
                        value: _showSenderName,
                        onChanged: (on) => setState(() => _showSenderName = on),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openVisibility() async {
    // Changing a channel between public and private is not a toggle: it decides
    // whether its name is a plaintext column or a sealed blob, and moving one
    // way means re-sealing everything while moving the other means publishing
    // what was sealed. Said plainly rather than offered as a switch that would
    // half-work.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(_channel.isPublic ? 'This channel is public' : 'This channel is private'),
        content: Text(
          _channel.isPublic
              ? 'Anyone can find it by name and read its posts. Its handle is '
                  '@${_channel.handle ?? ''}.\n\n'
                  'Privio cannot turn a public channel private after the fact: '
                  'its name and description have been readable, and unsaying '
                  'that is not something an app can do.'
              : 'It is not listed, not searchable, and reachable only through '
                  'its invite link. Its name is encrypted with the channel key.\n\n'
                  'Making it public would publish that name, which is a '
                  'decision Privio does not make on your behalf — create a '
                  'public channel instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Alright'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDiscussion() async {
    final channel = _channel;
    final controller = PrivioScope.of(context).channels;
    final on = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Discussion'),
        content: const Text(
          'With this on, every post gets a thread underneath it. Comments are '
          'sealed with the same channel key as the post, so a device that '
          'cannot read the post cannot read the thread.\n\n'
          'Turning it off later hides the threads rather than deleting them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(!channel.commentsEnabled),
            child: Text(channel.commentsEnabled ? 'Turn off' : 'Turn on'),
          ),
        ],
      ),
    );
    if (on == null || !mounted) return;
    await controller.setCommentsEnabled(channel.id, enabled: on);
  }

  Future<void> _openWelcome() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Welcome message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatefulBuilder(
              builder: (_, setLocal) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show it to new subscribers'),
                value: _welcomeEnabled,
                onChanged: (on) {
                  setLocal(() {});
                  setState(() => _welcomeEnabled = on);
                },
              ),
            ),
            TextField(
              controller: _welcome,
              maxLines: 4,
              minLines: 2,
              maxLength: 1024,
              decoration: const InputDecoration(hintText: 'Shown once, on joining'),
            ),
            if (!_channel.isPublic)
              const Text(
                'This channel is private, so the message is encrypted with the '
                'channel key like its name.',
                style: TextStyle(color: PrivioColors.textTertiary, fontSize: 12),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openAppearance() async {
    final chosen = await showModalBottomSheet<({String? accent, String? background})>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (_) => _AppearanceSheet(accent: _accent, background: _background),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _accent = chosen.accent;
      _background = chosen.background;
    });
  }

  Future<void> _explainTranslation() async {
    // The honest version, and the reason this row is not a switch. See
    // docs/channels.md.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Auto-translation is not set up'),
        content: const Text(
          'Translating a post means sending what it says to a translation '
          'service. Privio\'s server cannot do that — it holds ciphertext and '
          'no key — so it would have to happen on your device, and the text '
          'would leave it in the clear.\n\n'
          'That is a decision for whoever runs this server to enable and for '
          'each reader to agree to, so it is off until both have happened. No '
          'post has been sent anywhere.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Alright'),
          ),
        ],
      ),
    );
  }
}

class _NoPicture extends StatelessWidget {
  const _NoPicture();

  @override
  Widget build(BuildContext context) => Container(
        width: 88,
        height: 88,
        decoration: const BoxDecoration(
          color: PrivioColors.surfaceRaised,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.campaign_rounded, color: PrivioColors.textTertiary),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: PrivioColors.surfaceRaised,
          borderRadius: BorderRadius.circular(PrivioSpacing.md),
        ),
        child: Column(children: children),
      );
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: PrivioSpacing.lg),
        child: Divider(height: 1, thickness: 1, color: PrivioColors.border),
      );
}

/// The channel's own colours, with the result drawn rather than described.
class _AppearanceSheet extends StatefulWidget {
  const _AppearanceSheet({this.accent, this.background});

  final String? accent;
  final String? background;

  @override
  State<_AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<_AppearanceSheet> {
  late String? _accent = widget.accent;
  late String? _background = widget.background;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(PrivioSpacing.gutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: PrivioSpacing.xs),
                Text(
                  'A fixed set rather than a colour picker: every pair here was '
                  'checked for contrast, so a channel cannot pick something its '
                  'readers cannot read.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: PrivioSpacing.lg),

                // The preview, which is the point of the sheet.
                Container(
                  height: 96,
                  decoration: BoxDecoration(
                    color: ChannelPalette.backgroundFor(_background),
                    borderRadius: BorderRadius.circular(PrivioSpacing.md),
                    border: Border.all(color: PrivioColors.border),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'A post in this channel',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: PrivioSpacing.xs),
                        Text(
                          'and a link in it',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: ChannelPalette.accentFor(_accent),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.lg),

                Text('Accent', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: PrivioSpacing.sm),
                Wrap(
                  spacing: PrivioSpacing.sm,
                  children: [
                    for (final entry in ChannelPalette.accents.entries)
                      GestureDetector(
                        onTap: () => setState(() => _accent = entry.key),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: entry.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _accent == entry.key
                                  ? PrivioColors.textPrimary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.lg),

                Text('Background', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: PrivioSpacing.sm),
                Wrap(
                  spacing: PrivioSpacing.sm,
                  children: [
                    for (final entry in ChannelPalette.backgrounds.entries)
                      GestureDetector(
                        onTap: () => setState(() => _background = entry.key),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: entry.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _background == entry.key
                                  ? PrivioColors.textPrimary
                                  : PrivioColors.border,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.lg),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _accent = null;
                        _background = null;
                      }),
                      child: const Text('Use the default'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(context)
                          .pop((accent: _accent, background: _background)),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
