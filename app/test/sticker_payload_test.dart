import 'package:flutter_test/flutter_test.dart';
import 'package:privio/media/attachment.dart';

/// What a sticker and a custom emoji look like on the wire.
///
/// The theme of every test here is the same and it is the point of the design:
/// **a reader that does not understand the new fields still sees something
/// sensible.** A sticker decodes as the emoji it stands for; a sentence with
/// custom emoji in it decodes as that sentence with ordinary characters; a
/// custom reaction decodes as an ordinary reaction. None of that is a
/// courtesy — it is what stops a pack being deleted, or an old phone being on
/// the other end, turning somebody's chat into empty boxes.
void main() {
  group('a sticker', () {
    test('survives a round trip with its three ids', () {
      const sent = MessagePayload.sticker(
        stickerItemId: 'item-1',
        stickerPackId: 'pack-1',
        stickerMediaId: 'media-1',
        body: '😺',
      );
      final back = MessagePayload.decode(sent.encode());

      expect(back.isSticker, isTrue);
      expect(back.stickerItemId, 'item-1');
      expect(back.stickerPackId, 'pack-1');
      expect(back.stickerMediaId, 'media-1');
      expect(back.body, '😺');
    });

    test('is not mistaken for an attachment', () {
      const sent = MessagePayload.sticker(
        stickerItemId: 'item-1',
        stickerPackId: 'pack-1',
        stickerMediaId: 'media-1',
        body: '😺',
      );
      final back = MessagePayload.decode(sent.encode());

      // A sticker carries no key and is not a file somebody sent.
      expect(back.isMedia, isFalse);
      expect(back.mediaKey, isNull);
      expect(back.mediaToken, isNull);
    });

    test('reads as the emoji it stands for on a client that predates it', () {
      const sent = MessagePayload.sticker(
        stickerItemId: 'item-1',
        stickerPackId: 'pack-1',
        stickerMediaId: 'media-1',
        body: '😺',
      );
      // What an older build's decoder does: it does not know the tag, so it
      // falls through to text and shows the body. Simulated by rewriting the
      // tag to something this build has never heard of either.
      final older = sent.encode().replaceFirst('"t":"sticker"', '"t":"something_new"');
      final back = MessagePayload.decode(older);

      expect(back.isSticker, isFalse);
      expect(back.body, '😺', reason: 'the fallback character is the whole point');
    });

    test('a sticker with nothing to fetch falls back rather than half-drawing', () {
      // Malformed, or from a build that sent the tag without the ids.
      const raw = '{"v":1,"t":"sticker","b":"😺"}';
      final back = MessagePayload.decode(raw);

      expect(back.isSticker, isFalse);
      expect(back.body, '😺');
    });

    test('carries a reply and a disappearing timer like any other message', () {
      const sent = MessagePayload.sticker(
        stickerItemId: 'item-1',
        stickerPackId: 'pack-1',
        stickerMediaId: 'media-1',
        body: '😺',
        replyToId: 'msg-7',
        replyPreview: 'what do you think',
        expiresInSeconds: 3600,
      );
      final back = MessagePayload.decode(sent.encode());

      expect(back.replyToId, 'msg-7');
      expect(back.replyPreview, 'what do you think');
      expect(back.expiresInSeconds, 3600);
    });
  });

  group('custom emoji in a sentence', () {
    const ref = CustomEmojiRef(
      itemId: 'item-1',
      packId: 'pack-1',
      mediaId: 'media-1',
      offset: 6,
      length: 2,
    );

    test('travel as an overlay, leaving the sentence readable', () {
      const sent = MessagePayload.text('hello 😺 there', customEmoji: [ref]);
      final back = MessagePayload.decode(sent.encode());

      // The body is a sentence, not a template full of markers.
      expect(back.body, 'hello 😺 there');
      expect(back.customEmoji, hasLength(1));
      expect(back.customEmoji!.single.itemId, 'item-1');
      expect(back.customEmoji!.single.offset, 6);
    });

    test('a client without the overlay still reads the sentence', () {
      const sent = MessagePayload.text('hello 😺 there', customEmoji: [ref]);
      // An older decoder ignores `ce` entirely; this is what it is left with.
      final stripped = sent.encode().replaceFirst(RegExp(r',"ce":\[.*?\]'), '');
      final back = MessagePayload.decode(stripped);

      expect(back.body, 'hello 😺 there');
      expect(back.customEmoji, isNull);
    });

    test('a span that does not fit the text is dropped, not drawn', () {
      // The kind of thing a buggy or hostile sender produces. Applied, it would
      // be a range error inside somebody's message list.
      const raw = '{"v":1,"t":"text","b":"hi",'
          '"ce":[{"i":"item-1","p":"pack-1","m":"media-1","o":50,"l":2}]}';
      final back = MessagePayload.decode(raw);

      expect(back.body, 'hi');
      expect(back.customEmoji, isNull);
    });

    test('a span with no picture to fetch is dropped too', () {
      const raw = '{"v":1,"t":"text","b":"hi",'
          '"ce":[{"i":"item-1","p":"pack-1","m":"","o":0,"l":2}]}';
      expect(MessagePayload.decode(raw).customEmoji, isNull);
    });

    test('the good spans survive when a bad one is thrown out', () {
      const raw = '{"v":1,"t":"text","b":"ab",'
          '"ce":[{"i":"a","p":"p","m":"m","o":0,"l":1},'
          '{"i":"b","p":"p","m":"m","o":99,"l":1}]}';
      final back = MessagePayload.decode(raw);

      expect(back.customEmoji, hasLength(1));
      expect(back.customEmoji!.single.itemId, 'a');
    });
  });

  group('a reaction made with a custom emoji', () {
    test('still carries a real character for anyone without the pack', () {
      const sent = MessagePayload.reaction(
        reactionTo: 'msg-1',
        reactionEmoji: '😺',
        stickerItemId: 'item-1',
        stickerPackId: 'pack-1',
        stickerMediaId: 'media-1',
      );
      final back = MessagePayload.decode(sent.encode());

      expect(back.isReaction, isTrue);
      expect(back.isCustomReaction, isTrue);
      expect(back.reactionEmoji, '😺', reason: 'the fallback is not optional');
      expect(back.stickerMediaId, 'media-1');
      // And it is a reaction, not a sticker message.
      expect(back.isSticker, isFalse);
    });

    test('an ordinary reaction is unchanged and is not custom', () {
      const sent = MessagePayload.reaction(reactionTo: 'msg-1', reactionEmoji: '👍');
      final back = MessagePayload.decode(sent.encode());

      expect(back.isReaction, isTrue);
      expect(back.isCustomReaction, isFalse);
      expect(back.reactionEmoji, '👍');
    });

    test('taking a reaction back is still an empty emoji', () {
      const sent = MessagePayload.reaction(reactionTo: 'msg-1', reactionEmoji: '');
      final back = MessagePayload.decode(sent.encode());

      expect(back.isReaction, isTrue);
      expect(back.reactionEmoji, '');
    });
  });

  group('nothing else changed shape', () {
    test('a plain text message still decodes as one', () {
      final back = MessagePayload.decode(const MessagePayload.text('hello').encode());
      expect(back.body, 'hello');
      expect(back.isSticker, isFalse);
      expect(back.customEmoji, isNull);
    });

    test('a message from before any of this is still read', () {
      // Not JSON at all: what the very first builds sent.
      final back = MessagePayload.decode('just a sentence');
      expect(back.body, 'just a sentence');
    });
  });
}
