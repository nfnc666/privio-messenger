import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/sticker_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import '../widgets/sticker_tile.dart';
import 'sticker_pack_screen.dart';

/// Settings → Stickers & Emoji: the packs this account owns and has added.
///
/// Two sections rather than one list, because the two are different things:
/// a pack of one's own can be edited, renamed and shared, and a pack somebody
/// else shared can only be kept or dropped. Putting them together would mean
/// every row carrying a menu half of whose entries did nothing.
class StickersScreen extends StatefulWidget {
  const StickersScreen({super.key});

  @override
  State<StickersScreen> createState() => _StickersScreenState();
}

class _StickersScreenState extends State<StickersScreen> {
  @override
  void initState() {
    super.initState();
    // Read again on open rather than trusting what sign-in fetched: a pack
    // added on another device should be here, and this is the screen where
    // somebody would notice it was not.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = PrivioScope.of(context);
      final account = state.accountId;
      if (account != null) unawaited(state.stickers.load(account));
    });
  }

  Future<void> _create(StickerPackKind kind) async {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).stickers;
    final title = await _askForName(
      context,
      title: kind == StickerPackKind.emoji
          ? text.stickersNewEmojiPack
          : text.stickersNewStickerPack,
      confirm: text.stickersCreate,
    );
    if (title == null || !mounted) return;

    final pack = await controller.createPack(title: title, kind: kind);
    if (!mounted) return;
    if (pack == null) {
      _say(controller.failure?.words(text) ?? text.failureUnexpected);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => StickerPackScreen(packId: pack.id)),
    );
  }

  /// Opens a pack from a link or a bare code, and shows what is in it.
  Future<void> _openLink() async {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).stickers;
    final entered = await _askForName(
      context,
      title: text.stickersOpenLinkTitle,
      confirm: text.stickersOpen,
      hint: text.stickersOpenLinkHint,
    );
    if (entered == null || !mounted) return;

    // A link or the code out of one. Somebody who was sent a link pastes the
    // link; somebody reading it off a screen types the code. Both name the
    // same pack, and neither should be the only one that works.
    final parsed = ChannelService.parseLink(entered);
    final code = parsed is StickerPackLink ? parsed.code : entered.trim();

    final pack = await controller.previewByCode(code);
    if (!mounted) return;
    if (pack == null) {
      _say(controller.failure?.words(text) ?? text.failureStickerLinkDead);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StickerPackScreen(packId: pack.id, preview: pack, shareCode: code),
      ),
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).stickers;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.stickersTitle),
        actions: [
          IconButton(
            onPressed: _openLink,
            icon: const Icon(Icons.link_rounded),
            tooltip: text.stickersOpenLinkTitle,
          ),
          const SizedBox(width: PrivioSpacing.xs),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final mine = controller.myPacks;
          final added = controller.installedPacks;

          return ListView(
            padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
            children: [
              const SizedBox(height: PrivioSpacing.sm),
              if (mine.isEmpty && added.isEmpty && controller.loaded)
                _Empty(text: text),
              if (mine.isNotEmpty)
                SettingsSection(
                  caption: text.stickersMyPacks,
                  children: [
                    for (final pack in mine)
                      _PackRow(controller: controller, pack: pack),
                  ],
                ),
              if (added.isNotEmpty)
                SettingsSection(
                  caption: text.stickersInstalled,
                  children: [
                    for (final pack in added)
                      _PackRow(controller: controller, pack: pack),
                  ],
                ),
              SettingsSection(
                children: [
                  SettingsRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: text.stickersNewStickerPack,
                    enabled: !controller.busy,
                    onTap: () => _create(StickerPackKind.sticker),
                  ),
                  SettingsRow(
                    icon: Icons.emoji_emotions_outlined,
                    label: text.stickersNewEmojiPack,
                    enabled: !controller.busy,
                    onTap: () => _create(StickerPackKind.emoji),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({required this.controller, required this.pack});

  final StickerController controller;
  final StickerPack pack;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return SettingsRow(
      label: pack.title,
      subtitle: '${pack.kind == StickerPackKind.emoji ? text.stickersKindEmoji : text.stickersKindSticker}'
          ' · ${text.stickersItemCount(pack.items.length)}',
      trailing: Padding(
        padding: const EdgeInsets.only(left: PrivioSpacing.sm),
        child: StickerPackThumb(controller: controller, pack: pack),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => StickerPackScreen(packId: pack.id)),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final AppText text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.xxl,
        vertical: PrivioSpacing.xxxl,
      ),
      child: Column(
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 48, color: context.accents.bright),
          const SizedBox(height: PrivioSpacing.lg),
          Text(text.stickersEmptyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: PrivioSpacing.sm),
          Text(
            text.stickersEmptyBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Asks for one line of text. Returns null when cancelled or left empty.
///
/// Cancelling discards, which is the rule everywhere in this app: a dialog that
/// kept what was typed after Cancel would be a dialog that ignored the button.
Future<String?> _askForName(
  BuildContext context, {
  required String title,
  required String confirm,
  String? hint,
  String? initial,
}) async {
  final text = AppText.of(context);
  final field = TextEditingController(text: initial ?? '');
  try {
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 64,
          decoration: InputDecoration(
            labelText: text.stickersNameLabel,
            hintText: hint ?? text.stickersNameHint,
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(text.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: Text(confirm),
          ),
        ],
      ),
    );
    final trimmed = entered?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  } finally {
    field.dispose();
  }
}

/// Puts a pack's link on the clipboard.
Future<void> copyStickerLink(BuildContext context, String shareCode) async {
  final text = AppText.of(context);
  await Clipboard.setData(ClipboardData(text: ChannelService.linkForStickerPack(shareCode)));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text.stickersLinkCopied)));
  }
}

/// Shared by the pack screen: ask for a line of text.
Future<String?> askForStickerText(
  BuildContext context, {
  required String title,
  required String confirm,
  String? hint,
  String? initial,
}) =>
    _askForName(context, title: title, confirm: confirm, hint: hint, initial: initial);
