import 'package:flutter/material.dart';

import '../core/sticker_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import 'sticker_tile.dart';

/// What somebody picked out of the picker.
///
/// A sticker is sent; a custom emoji goes into the text being written. Two
/// outcomes rather than one with a flag, so the caller cannot forget which it
/// got — the compiler asks.
sealed class StickerChoice {
  const StickerChoice();
}

/// Send this as a message of its own.
class SendSticker extends StickerChoice {
  const SendSticker(this.pack, this.item);

  final StickerPack pack;
  final StickerItem item;
}

/// Put this into the message being written.
class InsertCustomEmoji extends StickerChoice {
  const InsertCustomEmoji(this.pack, this.item);

  final StickerPack pack;
  final StickerItem item;
}

/// A plain Unicode emoji, typed into the field like any other character.
class InsertEmoji extends StickerChoice {
  const InsertEmoji(this.emoji);

  final String emoji;
}

/// The composer's picker: Emoji, Stickers, and this account's own packs.
///
/// Three tabs because they are three different things to send, not three
/// filters of one list:
///
/// - **Emoji** are characters. They go into the sentence being written and the
///   other side needs nothing to read them.
/// - **Stickers** are messages. Picking one sends it.
/// - **Mine** is the packs this account made, both kinds together, so somebody
///   who just built a pack can find it where they put it rather than hunting
///   for which of the other two tabs it landed in.
///
/// Favourites and recents sit above the packs on the sticker tab, because that
/// is what anybody actually reaches for — and they belong to the account, so
/// they are still there after signing out and back in.
Future<StickerChoice?> showStickerPicker(
  BuildContext context,
  StickerController controller, {
  VoidCallback? onManagePacks,
}) =>
    showModalBottomSheet<StickerChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PrivioColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: PrivioRadius.card),
      ),
      builder: (context) => _StickerPicker(
        controller: controller,
        onManagePacks: onManagePacks,
      ),
    );

class _StickerPicker extends StatefulWidget {
  const _StickerPicker({required this.controller, this.onManagePacks});

  final StickerController controller;
  final VoidCallback? onManagePacks;

  @override
  State<_StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<_StickerPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => FractionallySizedBox(
        heightFactor: 0.62,
        child: Column(
          children: [
            const SizedBox(height: PrivioSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PrivioColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: context.accents.bright,
              unselectedLabelColor: PrivioColors.textSecondary,
              indicatorColor: context.accents.bright,
              tabs: [
                Tab(text: text.pickerEmoji),
                Tab(text: text.pickerStickers),
                Tab(text: text.pickerMine),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _EmojiTab(onPick: (emoji) => Navigator.of(context).pop(InsertEmoji(emoji))),
                  _StickerTab(
                    controller: widget.controller,
                    packs: widget.controller.stickerPacks,
                    emptyMessage: text.pickerNoStickers,
                    onPick: (pack, item) =>
                        Navigator.of(context).pop(SendSticker(pack, item)),
                    onManagePacks: widget.onManagePacks,
                  ),
                  _StickerTab(
                    controller: widget.controller,
                    packs: widget.controller.myPacks,
                    emptyMessage: text.stickersEmptyBody,
                    // Whatever kind the pack is, "Mine" behaves like the tab it
                    // came from: an emoji pack inserts, a sticker pack sends.
                    onPick: (pack, item) => Navigator.of(context).pop(
                      pack.kind == StickerPackKind.emoji
                          ? InsertCustomEmoji(pack, item)
                          : SendSticker(pack, item),
                    ),
                    onManagePacks: widget.onManagePacks,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The plain-Unicode tab.
///
/// A fixed, hand-picked set rather than every emoji Unicode defines. A full
/// keyboard is the *system's* job — it is already one tap away on the field —
/// and duplicating it here badly is worse than not having it.
class _EmojiTab extends StatelessWidget {
  const _EmojiTab({required this.onPick});

  final void Function(String emoji) onPick;

  static const List<String> _common = [
    '😀', '😂', '🙂', '😉', '😍', '😘', '😎', '🤔', '😐', '🙄',
    '😴', '😢', '😭', '😡', '🥳', '🤯', '😱', '🤗', '🤝', '🙏',
    '👍', '👎', '👏', '💪', '🫶', '❤️', '💔', '🔥', '✨', '🎉',
    '💯', '✅', '❌', '⚠️', '☕', '🍕', '🎵', '📷', '🌧️', '☀️',
  ];

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 8,
        padding: const EdgeInsets.all(PrivioSpacing.md),
        children: [
          for (final emoji in _common)
            InkWell(
              onTap: () => onPick(emoji),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
            ),
        ],
      );
}

/// A tab of packs, with favourites and recents above them.
class _StickerTab extends StatelessWidget {
  const _StickerTab({
    required this.controller,
    required this.packs,
    required this.emptyMessage,
    required this.onPick,
    this.onManagePacks,
  });

  final StickerController controller;
  final List<StickerPack> packs;
  final String emptyMessage;
  final void Function(StickerPack pack, StickerItem item) onPick;
  final VoidCallback? onManagePacks;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);

    if (packs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(PrivioSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
              ),
              if (onManagePacks != null) ...[
                const SizedBox(height: PrivioSpacing.lg),
                TextButton(onPressed: onManagePacks, child: Text(text.pickerManagePacks)),
              ],
            ],
          ),
        ),
      );
    }

    // Favourites and recents are resolved back to real items rather than drawn
    // from the use row alone: an item removed from its pack should leave the
    // recents list rather than linger as a picture nothing points at.
    final favourites = _resolve(controller.favourites.map((use) => use.itemId));
    final recents = _resolve(
      controller.recents.where((use) => !use.favourite).map((use) => use.itemId),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.xxl),
      children: [
        if (favourites.isNotEmpty)
          _Section(title: text.pickerFavourites, items: favourites, onPick: onPick,
              controller: controller),
        if (recents.isNotEmpty)
          _Section(title: text.pickerRecent, items: recents.take(16).toList(),
              onPick: onPick, controller: controller),
        for (final pack in packs)
          if (pack.items.isNotEmpty)
            _Section(
              title: pack.title,
              items: [for (final item in pack.items) (pack: pack, item: item)],
              onPick: onPick,
              controller: controller,
            ),
        if (onManagePacks != null)
          Padding(
            padding: const EdgeInsets.only(top: PrivioSpacing.md),
            child: Center(
              child: TextButton(onPressed: onManagePacks, child: Text(text.pickerManagePacks)),
            ),
          ),
      ],
    );
  }

  /// Turns item ids into the items themselves, dropping any this account can no
  /// longer reach. Order is preserved, which is what makes "recent" mean recent.
  List<({StickerPack pack, StickerItem item})> _resolve(Iterable<String> itemIds) {
    final out = <({StickerPack pack, StickerItem item})>[];
    final shown = <String>{};
    for (final id in itemIds) {
      if (!shown.add(id)) continue;
      final found = controller.itemById(id);
      // Only from the packs this tab is showing, so a custom emoji does not
      // turn up among the stickers because it was used recently.
      if (found != null && packs.any((pack) => pack.id == found.pack.id)) {
        out.add(found);
      }
    }
    return out;
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.onPick,
    required this.controller,
  });

  final String title;
  final List<({StickerPack pack, StickerItem item})> items;
  final void Function(StickerPack pack, StickerItem item) onPick;
  final StickerController controller;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.lg,
              PrivioSpacing.lg,
              PrivioSpacing.lg,
              PrivioSpacing.sm,
            ),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(letterSpacing: 0.8, color: PrivioColors.textTertiary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.md),
            child: Wrap(
              spacing: PrivioSpacing.sm,
              runSpacing: PrivioSpacing.sm,
              children: [
                for (final entry in items)
                  InkWell(
                    onTap: () => onPick(entry.pack, entry.item),
                    // Long press marks a favourite: the gesture that is already
                    // "tell me more about this one" everywhere else in the app.
                    onLongPress: () => controller.setFavourite(
                      entry.item.id,
                      !controller.favourites.any((use) => use.itemId == entry.item.id),
                    ),
                    child: StickerTile(
                      controller: controller,
                      mediaId: entry.item.mediaId,
                      emoji: entry.item.emoji,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}
