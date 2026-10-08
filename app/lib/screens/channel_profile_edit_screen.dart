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
import '../widgets/channel_settings_tiles.dart';

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
            // centred above everything — on its own card, with the action as a
            // real button rather than a word somebody has to guess is one.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.gutter,
                PrivioSpacing.sm,
                PrivioSpacing.gutter,
                0,
              ),
              child: Container(
                padding: const EdgeInsets.all(PrivioSpacing.lg),
                decoration: BoxDecoration(
                  color: PrivioColors.surface,
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  border: Border.all(color: PrivioColors.border),
                ),
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
                          Text(
                            text.chProfilePicture,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: PrivioSpacing.sm),
                          FilledButton.tonalIcon(
                            onPressed: _saving ? null : () => unawaited(_choosePicture()),
                            style: FilledButton.styleFrom(
                              backgroundColor: context.accents.surface,
                              foregroundColor: context.accents.bright,
                            ),
                            icon: const Icon(Icons.photo_camera_outlined, size: 18),
                            label: Text(text.chProfileChange),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // The two fields, each labelled inside its own box, with the
            // counter under it: what the field is, and how much room is left.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.gutter,
                PrivioSpacing.xl,
                PrivioSpacing.gutter,
                0,
              ),
              child: Column(
                children: [
                  ChannelTextField(
                    controller: _title,
                    label: text.chProfileName,
                    hint: text.editChannelName,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 64,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: PrivioSpacing.sm),
                  ChannelTextField(
                    controller: _description,
                    label: text.chProfileDescription,
                    hint: text.editChannelDescriptionHint,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 5,
                    minLines: 3,
                    maxLength: 512,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),

            ChannelSettingsGroup(
              caption: text.chRowLink,
              footnote: channel.isPublic ? text.chProfileLinkNote : text.editChannelPrivateNameNote,
              children: [
                if (link != null)
                  ChannelSettingsTile(
                    icon: Icons.copy_rounded,
                    title: text.channelCopyLink,
                    summary: link,
                    summaryLines: 1,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      _say(text.channelLinkCopied);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
