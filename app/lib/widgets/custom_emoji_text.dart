import 'package:flutter/material.dart';

import '../core/sticker_controller.dart';
import '../models/models.dart';
import 'sticker_tile.dart';

/// A message's text, with custom emoji drawn in place of their fallbacks.
///
/// **The text is always complete without this.** [Message.body] holds ordinary
/// characters in the places the custom emoji go, and every span this replaces
/// is one of them — so a pack that was never installed, or has since been
/// deleted, costs nothing but the picture. That is why this widget can be
/// wholly absent from a build and the conversation still reads.
///
/// Spans were validated against the body when the message was decoded and again
/// when it was read back from the archive, so the slicing below cannot run off
/// the end. It re-checks anyway, because a range error here would be a crash in
/// somebody's message list rather than a slightly wrong picture.
class CustomEmojiText extends StatelessWidget {
  const CustomEmojiText({
    required this.message,
    required this.controller,
    super.key,
    this.style,
  });

  final Message message;

  /// Where pictures come from, or null when there is no app around this widget.
  /// Null renders the body as plain text, which is already correct.
  final StickerController? controller;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final refs = message.customEmoji;
    final body = message.body;
    final controller = this.controller;
    if (refs == null || refs.isEmpty || controller == null) {
      return Text(body, style: style);
    }

    final ordered = [...refs]..sort((a, b) => a.offset.compareTo(b.offset));
    final size = (style?.fontSize ?? 15) * 1.35;
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final ref in ordered) {
      // Overlapping or out-of-order spans are skipped rather than rearranged:
      // a message whose picture is in the wrong place is worse than one that
      // simply shows its fallback character.
      if (ref.offset < cursor || !ref.fits(body)) continue;
      if (ref.offset > cursor) {
        spans.add(TextSpan(text: body.substring(cursor, ref.offset)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: StickerTile(
            controller: controller,
            mediaId: ref.mediaId,
            // The characters it stands for, taken from the message itself
            // rather than from the pack: this is what the sender saw, and it is
            // still right when the pack is gone.
            emoji: body.substring(ref.offset, ref.offset + ref.length),
            size: size,
          ),
        ),
      );
      cursor = ref.offset + ref.length;
    }
    if (cursor < body.length) {
      spans.add(TextSpan(text: body.substring(cursor)));
    }

    return Text.rich(TextSpan(children: spans), style: style);
  }
}

/// A sticker in a conversation: the picture, with no bubble around it.
///
/// No bubble because a sticker is not a sentence — it has no caption to sit
/// beside and no background that would not fight with its own transparency.
/// Tapping offers the pack it came from, which is what the brief asks for and
/// what anybody who has used stickers elsewhere expects.
class StickerMessage extends StatelessWidget {
  const StickerMessage({
    required this.sticker,
    required this.fallback,
    required this.controller,
    super.key,
    this.onTap,
    this.size = 128,
  });

  final StickerRef sticker;

  /// The character it stands for, shown until the picture arrives and instead
  /// of it if it never does.
  final String fallback;

  /// Null where there is no app around this widget: the character is drawn on
  /// its own, which is the same thing that happens when the picture will not
  /// come.
  final StickerController? controller;

  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: Text(fallback, style: TextStyle(fontSize: size * 0.5))),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: StickerTile(
        controller: controller,
        mediaId: sticker.mediaId,
        emoji: fallback,
        size: size,
      ),
    );
  }
}
