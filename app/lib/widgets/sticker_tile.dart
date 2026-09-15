import 'package:flutter/material.dart';

import '../core/sticker_controller.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// One sticker, drawn from the cache and fetched if it is not there yet.
///
/// The fallback is the item's own emoji rather than a broken-image box, and
/// that is not only cosmetic: the emoji is what the sticker *stands for*, so a
/// picture that has not arrived — or a pack whose pictures this account may no
/// longer fetch — still reads as the thing it was meant to be.
class StickerTile extends StatefulWidget {
  const StickerTile({
    required this.controller,
    required this.mediaId,
    required this.emoji,
    super.key,
    this.size = 72,
  });

  final StickerController controller;
  final String mediaId;

  /// What to draw until the picture arrives, and instead of it if it does not.
  final String emoji;
  final double size;

  @override
  State<StickerTile> createState() => _StickerTileState();
}

class _StickerTileState extends State<StickerTile> {
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(StickerTile old) {
    super.didUpdateWidget(old);
    if (old.mediaId != widget.mediaId) _fetch();
  }

  void _fetch() {
    // Not awaited and not held: the controller caches and notifies, and this
    // widget rebuilds from the cache. Holding the future here would mean a
    // second fetch every time the grid recycled the cell.
    if (widget.controller.imageOf(widget.mediaId) != null) return;
    widget.controller.image(widget.mediaId).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.controller.imageOf(widget.mediaId);
    if (bytes == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Text(
            widget.emoji,
            style: TextStyle(fontSize: widget.size * 0.5),
          ),
        ),
      );
    }
    return Image.memory(
      bytes,
      width: widget.size,
      height: widget.size,
      // Contain, not cover: a sticker is a shape with transparency around it,
      // and cropping it to fill a square is how a shape becomes a rectangle.
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Text(widget.emoji, style: TextStyle(fontSize: widget.size * 0.5)),
        ),
      ),
    );
  }
}

/// The square a pack shows for itself in a list: its first sticker, or a mark.
class StickerPackThumb extends StatelessWidget {
  const StickerPackThumb({
    required this.controller,
    required this.pack,
    super.key,
    this.size = 44,
  });

  final StickerController controller;
  final StickerPack pack;
  final double size;

  @override
  Widget build(BuildContext context) {
    final first = pack.items.isEmpty ? null : pack.items.first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.accents.surface,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
      ),
      child: first == null
          ? Icon(
              pack.kind == StickerPackKind.emoji
                  ? Icons.emoji_emotions_outlined
                  : Icons.sticky_note_2_outlined,
              size: size * 0.5,
              color: context.accents.bright,
            )
          : Padding(
              padding: EdgeInsets.all(size * 0.1),
              child: StickerTile(
                controller: controller,
                mediaId: first.mediaId,
                emoji: first.emoji,
                size: size * 0.8,
              ),
            ),
    );
  }
}
