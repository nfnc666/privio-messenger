import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/channel_avatar.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// The channel's picture, name, description and link.
///
/// One page for the four things that *are* the channel's identity, instead of
/// them being the top third of a settings list with everything else below. The
/// save rules are the ones the old edit screen had, kept deliberately:
///
/// * **Save and Cancel are both explicit.** Nothing is written on a keystroke.
/// * **Leaving with unsaved changes asks first**, and the question names what
///   happens rather than being an "are you sure".
/// * **The picture goes first and on its own.** It is a separate upload, and a
///   failed one must not take the text down with it.
class ChannelProfileEditScreen extends StatefulWidget {
  const ChannelProfileEditScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelProfileEditScreen> createState() => _ChannelProfileEditScreenState();
}

class _ChannelProfileEditScreenState extends State<ChannelProfileEditScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.channel.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.channel.description ?? '');

  Uint8List? _pendingPicture;
  bool _removePicture = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  ChannelInfo get _channel =>
      PrivioScope.of(context).channels.channelById(widget.channel.id) ?? widget.channel;

  bool get _dirty =>
      _title.text.trim() != _channel.title ||
      _description.text.trim() != (_channel.description ?? '') ||
      _pendingPicture != null ||
      _removePicture;

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final text = AppText.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.chUnsavedTitle),
        content: Text(text.chUnsavedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.chUnsavedKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              text.chUnsavedDiscard,
              style: const TextStyle(color: PrivioColors.danger),
            ),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _save() async {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).channels;
    final channel = _channel;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _say(text.editChannelNeedsName);
      return;
    }

    setState(() => _saving = true);
    try {
      if (_removePicture) {
        await controller.clearAvatar(channel);
      } else if (_pendingPicture != null) {
        if (!await controller.setAvatar(channel, _pendingPicture!)) {
          if (mounted) {
            _say(controller.failure?.words(text) ?? text.editChannelCouldNotUsePicture);
          }
          return;
        }
      }

      final saved = await controller.saveSettings(
        channel,
        title: title,
        description: _description.text.trim(),
      );
      if (!mounted) return;
      if (!saved) {
        _say(controller.failure?.words(text) ?? text.editChannelCouldNotSave);
        return;
      }
      _say(text.chSaved);
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _choosePicture() async {
    final text = AppText.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(text.editChannelChoosePicture),
              onTap: () => Navigator.of(sheetContext).pop('pick'),
            ),
            if (_channel.hasAvatar || _pendingPicture != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: PrivioColors.danger,
                ),
                title: Text(
                  text.editChannelRemovePicture,
                  style: const TextStyle(color: PrivioColors.danger),
                ),
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
      if (mounted) _say(text.accountPickerFailed('$failure'));
      return;
    }
    if (picked == null || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object catch (failure) {
      if (mounted) _say(text.accountCouldNotReadFile(picked.name, '$failure'));
      return;
    }
    if (!mounted) return;
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
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).channels;
    final channel = _channel;
    final link = ChannelService.shareLinkFor(channel);
    final picture = _removePicture ? null : (_pendingPicture ?? controller.avatarFor(channel));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (!leave || !mounted) return;
        Navigator.of(this.context).pop();
      },
      child: Scaffold(
        backgroundColor: PrivioColors.background,
        appBar: AppBar(
          backgroundColor: PrivioColors.background,
          // The plain back button: `Navigator.maybePop` runs the PopScope
          // handler above, so the unsaved-changes question is asked once, in
          // one place, whichever way somebody leaves.
          leading: const PrivioBackButton(),
          title: Text(text.chProfileTitle),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: PrivioSpacing.md),
              child: TextButton(
                onPressed: _saving || !_dirty ? null : () => unawaited(_save()),
                child: Text(
                  _saving ? text.chSaving : text.commonSave,
                  style: TextStyle(
                    color: _saving || !_dirty
                        ? PrivioColors.textTertiary
                        : context.accents.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
          children: [
            // The picture, left-aligned with its action beside it rather than
            // centred above everything.
            Padding(
              padding: const EdgeInsets.all(PrivioSpacing.lg),
              child: Row(
                children: [
                  ChannelAvatar(
                    channel: channel,
                    imageBytes: _removePicture ? null : picture,
                    size: 72,
                  ),
                  const SizedBox(width: PrivioSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(text.chProfilePicture, style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: PrivioSpacing.xs),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _saving ? null : () => unawaited(_choosePicture()),
                              child: Text(text.chProfileChange),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SettingsSection(
              caption: text.chProfileName,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrivioSpacing.lg,
                    vertical: PrivioSpacing.xs,
                  ),
                  child: TextField(
                    controller: _title,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 64,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: text.editChannelName,
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),

            SettingsSection(
              caption: text.chProfileDescription,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrivioSpacing.lg,
                    vertical: PrivioSpacing.xs,
                  ),
                  child: TextField(
                    controller: _description,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 5,
                    minLines: 2,
                    maxLength: 512,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: text.editChannelDescriptionHint,
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),

            if (link != null)
              SettingsSection(
                caption: text.chRowLink,
                children: [
                  SettingsRow(
                    label: link,
                    value: text.channelCopyLink,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      _say(text.channelLinkCopied);
                    },
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.lg,
                PrivioSpacing.sm,
                PrivioSpacing.lg,
                0,
              ),
              child: Text(
                channel.isPublic ? text.chProfileLinkNote : text.editChannelPrivateNameNote,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: PrivioColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
