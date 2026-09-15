import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/sticker_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import '../widgets/sticker_crop_sheet.dart';
import '../widgets/sticker_tile.dart';
import 'stickers_screen.dart';

/// One pack: its pictures, and what can be done with it.
///
/// The same screen in three situations, because they are the same pack seen
/// from three distances:
///
/// - **Mine.** Add, reorder, re-emoji, remove, rename, share, delete.
/// - **Added.** Look at it, and drop it.
/// - **A link somebody sent.** Look at it, and decide — which is the preview
///   the brief asks for: seeing what is in a pack is not the same as taking it,
///   and a link that installed on tap would make it the same.
///
/// Which one it is comes from the data, never from a flag passed in: the server
/// hands a share code only to a pack's owner, so `pack.isMine` is the server's
/// answer and not this screen's guess.
class StickerPackScreen extends StatefulWidget {
  const StickerPackScreen({
    required this.packId,
    super.key,
    this.preview,
    this.shareCode,
  });

  final String packId;

  /// A pack fetched by its code and not (yet) in the account's own list.
  final StickerPack? preview;

  /// The code it was reached by, needed again to install it.
  final String? shareCode;

  @override
  State<StickerPackScreen> createState() => _StickerPackScreenState();
}

class _StickerPackScreenState extends State<StickerPackScreen> {
  bool _working = false;

  StickerController get _controller => PrivioScope.of(context).stickers;

  /// The pack as the account knows it, or the previewed one.
  StickerPack? get _pack => _controller.packById(widget.packId) ?? widget.preview;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _sayFailure() {
    final text = AppText.of(context);
    _say(_controller.failure?.words(text) ?? text.failureUnexpected);
  }

  Future<void> _addPicture() async {
    final text = AppText.of(context);
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.image)
          .timeout(const Duration(minutes: 2));
    } on Object {
      _say(text.stickersPickFailed);
      return;
    }
    if (picked == null || !mounted) return;

    final Uint8List raw;
    try {
      raw = await picked.readAsBytes();
    } on Object {
      _say(text.stickersPickFailed);
      return;
    }
    if (!mounted) return;

    // Crop, then emoji, then upload. In that order because each step depends on
    // the last and because a person who backs out of the crop should not have
    // been asked for an emoji first.
    final cropped = await showStickerCropSheet(context, raw);
    if (cropped == null || !mounted) return;

    final emoji = await askForStickerText(
      context,
      title: text.stickersItemEmoji,
      confirm: text.stickersUse,
      hint: text.stickersItemEmojiWhy,
    );
    if (emoji == null || !mounted) return;

    setState(() => _working = true);
    final item = await _controller.addItem(widget.packId, bytes: cropped, emoji: emoji);
    if (!mounted) return;
    setState(() => _working = false);
    if (item == null) _sayFailure();
  }

  Future<void> _rename() async {
    final text = AppText.of(context);
    final pack = _pack;
    if (pack == null) return;
    final title = await askForStickerText(
      context,
      title: text.stickersRename,
      confirm: text.stickersRename,
      initial: pack.title,
    );
    if (title == null || !mounted) return;
    if (await _controller.rename(widget.packId, title) == null) _sayFailure();
  }

  Future<void> _delete() async {
    final text = AppText.of(context);
    final pack = _pack;
    if (pack == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.stickersDeleteConfirm(pack.title)),
        content: Text(text.stickersDeleteExplain),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.stickersDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final gone = await _controller.deletePack(widget.packId);
    if (!mounted) return;
    if (gone) {
      Navigator.of(context).pop();
    } else {
      _sayFailure();
    }
  }

  Future<void> _share(bool on) async {
    if (on) {
      final code = await _controller.share(widget.packId);
      if (!mounted) return;
      if (code == null) {
        _sayFailure();
      } else {
        await copyStickerLink(context, code);
      }
      return;
    }
    if (!await _controller.unshare(widget.packId) && mounted) _sayFailure();
  }

  Future<void> _install() async {
    final pack = await _controller.install(widget.packId, code: widget.shareCode);
    if (!mounted) return;
    if (pack == null) _sayFailure();
  }

  Future<void> _uninstall() async {
    final gone = await _controller.uninstall(widget.packId);
    if (!mounted) return;
    if (gone) {
      Navigator.of(context).pop();
    } else {
      _sayFailure();
    }
  }

  Future<void> _editEmoji(StickerItem item) async {
    final text = AppText.of(context);
    final emoji = await askForStickerText(
      context,
      title: text.stickersItemEmoji,
      confirm: text.stickersUse,
      hint: text.stickersItemEmojiWhy,
      initial: item.emoji,
    );
    if (emoji == null || !mounted) return;
    if (!await _controller.setItemEmoji(widget.packId, item.id, emoji) && mounted) {
      _sayFailure();
    }
  }

  Future<void> _removeItem(StickerItem item) async {
    if (!await _controller.removeItem(widget.packId, item.id) && mounted) _sayFailure();
  }

  Future<void> _reorder(List<StickerItem> items, int from, int to) async {
    // `to` arrives already adjusted for the removed row — see the note at the
    // call site — so this is a plain remove-and-insert with no fix-up.
    final moved = [...items];
    final item = moved.removeAt(from);
    moved.insert(to, item);
    if (!await _controller.reorder(
          widget.packId,
          moved.map((each) => each.id).toList(growable: false),
        ) &&
        mounted) {
      _sayFailure();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = _controller;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pack = _pack;
        if (pack == null) {
          // Deleted while this screen was open. Nothing to show and nothing to
          // do, so it says so rather than drawing an empty pack.
          return Scaffold(
            appBar: AppBar(leading: const PrivioBackButton()),
            body: Center(child: Text(text.failureStickerPackNotFound)),
          );
        }

        // A pack reached by a link and not yet added: the server sends no share
        // code for somebody else's pack, so "mine" is its answer, not a guess.
        final isMine = pack.isMine && widget.preview == null;
        final isAdded = pack.installed;

        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: Text(pack.title),
            actions: [
              if (isMine)
                IconButton(
                  onPressed: controller.busy ? null : _rename,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: text.stickersRename,
                ),
              const SizedBox(width: PrivioSpacing.xs),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
            children: [
              const SizedBox(height: PrivioSpacing.sm),
              _Grid(
                controller: controller,
                pack: pack,
                editable: isMine,
                onEditEmoji: _editEmoji,
                onRemove: _removeItem,
                onReorder: (from, to) => _reorder(pack.items, from, to),
              ),
              if (isMine) ...[
                SettingsSection(
                  children: [
                    SettingsRow(
                      icon: Icons.add_photo_alternate_outlined,
                      label: text.stickersAddItem,
                      enabled: !controller.busy && !_working,
                      onTap: _addPicture,
                    ),
                    if (pack.items.length > 1)
                      SettingsRow(
                        icon: Icons.swap_vert_rounded,
                        label: text.stickersReorderHint,
                        enabled: false,
                      ),
                  ],
                ),
                SettingsSection(
                  caption: text.stickersShare,
                  children: [
                    SettingsRow(
                      icon: Icons.link_rounded,
                      label: text.stickersShare,
                      subtitle: pack.shared ? text.stickersSharedOn : text.stickersSharedOff,
                      trailing: Switch.adaptive(
                        value: pack.shared,
                        onChanged: controller.busy ? null : _share,
                      ),
                    ),
                    if (pack.shared && pack.shareCode != null) ...[
                      SettingsRow(
                        icon: Icons.copy_rounded,
                        label: text.stickersCopyLink,
                        onTap: () => copyStickerLink(context, pack.shareCode!),
                      ),
                      SettingsRow(
                        icon: Icons.refresh_rounded,
                        label: text.stickersNewLinkNote,
                        enabled: !controller.busy,
                        onTap: () => _share(true),
                      ),
                    ],
                  ],
                ),
                _Note(text: text.stickersShareExplain),
                SettingsSection(
                  children: [
                    SettingsRow(
                      label: text.stickersDelete,
                      destructive: true,
                      enabled: !controller.busy,
                      onTap: _delete,
                    ),
                  ],
                ),
              ] else
                SettingsSection(
                  children: [
                    if (isAdded)
                      SettingsRow(
                        label: text.stickersRemovePack,
                        destructive: true,
                        enabled: !controller.busy,
                        onTap: _uninstall,
                      )
                    else
                      SettingsRow(
                        icon: Icons.add_rounded,
                        label: text.stickersAddPack,
                        enabled: !controller.busy,
                        onTap: _install,
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The pictures, as a grid. Reorderable only for a pack of one's own.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.controller,
    required this.pack,
    required this.editable,
    required this.onEditEmoji,
    required this.onRemove,
    required this.onReorder,
  });

  final StickerController controller;
  final StickerPack pack;
  final bool editable;
  final Future<void> Function(StickerItem) onEditEmoji;
  final Future<void> Function(StickerItem) onRemove;
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    if (pack.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(PrivioSpacing.xxl),
        child: Center(
          child: Text(
            text.stickersEmptyPack,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: PrivioColors.textTertiary),
          ),
        ),
      );
    }

    if (!editable) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
        child: Wrap(
          spacing: PrivioSpacing.md,
          runSpacing: PrivioSpacing.md,
          children: [
            for (final item in pack.items)
              StickerTile(controller: controller, mediaId: item.mediaId, emoji: item.emoji),
          ],
        ),
      );
    }

    // A reorderable *list* of rows rather than a grid: a grid that reorders on
    // drag needs a drag target per cell and reads as a puzzle. A row carries
    // the picture, what it stands for, and the two things that can be done to
    // it, which is everything an editor needs at a glance.
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: pack.items.length > 1,
      // `onReorderItem` rather than `onReorder`: the older callback hands a
      // newIndex that still counts the dragged row, so every caller has to
      // subtract one and every caller that forgets has an off-by-one only
      // visible when dragging downwards. This one is already adjusted.
      onReorderItem: onReorder,
      children: [
        for (final item in pack.items)
          ListTile(
            key: ValueKey(item.id),
            leading: StickerTile(
              controller: controller,
              mediaId: item.mediaId,
              emoji: item.emoji,
              size: 44,
            ),
            title: Text(item.emoji, style: const TextStyle(fontSize: 20)),
            subtitle: Text(
              text.stickersItemEmojiWhy,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: PrivioColors.textTertiary),
            ),
            onTap: () => unawaited(onEditEmoji(item)),
            trailing: IconButton(
              onPressed: () => unawaited(onRemove(item)),
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: text.stickersRemoveItem,
            ),
          ),
      ],
    );
  }
}

/// The paragraph under the share switch.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

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
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: PrivioColors.textTertiary),
        ),
      );
}
