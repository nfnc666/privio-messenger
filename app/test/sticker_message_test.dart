import 'package:flutter_test/flutter_test.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';

/// A sticker in a conversation: how it is stored, reacted to, and kept.
///
/// The payload's own round trip is `sticker_payload_test.dart`. This is the
/// half after it — what a device holds once one has arrived, and what survives
/// being written to the archive and read back.

const _ref = StickerRef(itemId: 'item-1', packId: 'pack-1', mediaId: 'media-1');

Message sticker(String clientId, {bool isMine = false}) => Message(
      id: clientId,
      clientId: clientId,
      body: '😺',
      kind: MessageKind.sticker,
      sticker: _ref,
      sentAt: DateTime(2026),
      isMine: isMine,
    );

Message text(String clientId, {String body = 'hallo'}) => Message(
      id: clientId,
      clientId: clientId,
      body: body,
      sentAt: DateTime(2026),
      isMine: false,
    );

InMemoryMessageStore storeWith(List<Message> messages) {
  final store = InMemoryMessageStore()
    ..upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'));
  for (final message in messages) {
    store.append('acc-bob', message);
  }
  return store;
}

void main() {
  group('a sticker message', () {
    test('keeps its fallback character beside its picture', () {
      final store = storeWith([sticker('c1')]);
      final held = store.conversationWith('acc-bob')!.messages.single;

      expect(held.kind, MessageKind.sticker);
      expect(held.sticker, _ref);
      // The character is not decoration: it is what renders when the picture
      // will not come.
      expect(held.body, '😺');
    });
  });

  group('a reaction made with a custom emoji', () {
    test('records the picture alongside the character', () {
      final store = storeWith([text('c1')]);

      expect(
        store.applyReaction(
          conversationId: 'acc-bob',
          targetClientId: 'c1',
          accountId: 'acc-alice',
          emoji: '😺',
          sticker: _ref,
        ),
        isTrue,
      );

      final message = store.conversationWith('acc-bob')!.messages.single;
      expect(message.reactions, {'acc-alice': '😺'});
      expect(message.reactionStickers, {'acc-alice': _ref});
    });

    test('a plain reaction leaves no picture behind', () {
      final store = storeWith([text('c1')]);
      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'acc-alice',
        emoji: '👍',
      );

      final message = store.conversationWith('acc-bob')!.messages.single;
      expect(message.reactions, {'acc-alice': '👍'});
      expect(message.reactionStickers, isEmpty);
    });

    test('replacing a custom one with a plain one drops the picture', () {
      final store = storeWith([text('c1')]);
      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'acc-alice',
        emoji: '😺',
        sticker: _ref,
      );
      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'acc-alice',
        emoji: '👍',
      );

      final message = store.conversationWith('acc-bob')!.messages.single;
      expect(message.reactions, {'acc-alice': '👍'});
      expect(message.reactionStickers, isEmpty,
          reason: 'the old picture must not survive under the new character');
    });

    test('two custom emoji sharing a character are still different reactions', () {
      // The case that makes the sticker part of the comparison rather than an
      // afterthought: both of these fall back to 😺, and treating them as the
      // same reaction would make picking the second one silently do nothing.
      const other = StickerRef(itemId: 'item-2', packId: 'pack-1', mediaId: 'media-2');
      final store = storeWith([text('c1')]);

      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'acc-alice',
        emoji: '😺',
        sticker: _ref,
      );
      expect(
        store.applyReaction(
          conversationId: 'acc-bob',
          targetClientId: 'c1',
          accountId: 'acc-alice',
          emoji: '😺',
          sticker: other,
        ),
        isTrue,
        reason: 'a different picture is a different reaction',
      );
      expect(
        store.conversationWith('acc-bob')!.messages.single.reactionStickers['acc-alice'],
        other,
      );
    });

    test('taking it back removes both halves', () {
      final store = storeWith([text('c1')]);
      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'acc-alice',
        emoji: '😺',
        sticker: _ref,
      );
      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'acc-alice',
        emoji: '',
      );

      final message = store.conversationWith('acc-bob')!.messages.single;
      expect(message.reactions, isEmpty);
      expect(message.reactionStickers, isEmpty);
    });
  });

  group('the archive', () {
    /// Writes and reads back, which is what a restart and a restore both do.
    List<Conversation> roundTrip(List<Message> messages) =>
        ArchiveCodec.decode(ArchiveCodec.encode(storeWith(messages).conversations()));

    test('keeps a sticker', () {
      final back = roundTrip([sticker('c1')]).single.messages.single;

      expect(back.kind, MessageKind.sticker);
      expect(back.sticker, _ref);
      expect(back.body, '😺');
    });

    test('keeps a custom-emoji overlay', () {
      const ref = CustomEmojiRef(
        itemId: 'item-1',
        packId: 'pack-1',
        mediaId: 'media-1',
        offset: 6,
        length: 2,
      );
      final message = Message(
        id: 'c1',
        clientId: 'c1',
        body: 'hello 😺 there',
        sentAt: DateTime(2026),
        isMine: false,
        customEmoji: const [ref],
      );

      final back = roundTrip([message]).single.messages.single;
      expect(back.body, 'hello 😺 there');
      expect(back.customEmoji, [ref]);
    });

    test('drops an overlay span that no longer fits its text', () {
      // What an archive edited by hand, or written by another build, can hold.
      // Applied, it would be a range error while restoring somebody's history.
      final encoded = ArchiveCodec.encode(
        storeWith([
          Message(
            id: 'c1',
            clientId: 'c1',
            body: 'hi',
            sentAt: DateTime(2026),
            isMine: false,
            customEmoji: const [
              CustomEmojiRef(
                itemId: 'item-1',
                packId: 'pack-1',
                mediaId: 'media-1',
                offset: 50,
                length: 2,
              ),
            ],
          ),
        ]).conversations(),
      );

      final back = ArchiveCodec.decode(encoded).single.messages.single;
      expect(back.body, 'hi');
      expect(back.customEmoji, isNull);
    });

    test('keeps a custom reaction, and the plain one beside it', () {
      final store = storeWith([text('c1')])
        ..applyReaction(
          conversationId: 'acc-bob',
          targetClientId: 'c1',
          accountId: 'acc-alice',
          emoji: '😺',
          sticker: _ref,
        )
        ..applyReaction(
          conversationId: 'acc-bob',
          targetClientId: 'c1',
          accountId: 'acc-carol',
          emoji: '👍',
        );

      final back = ArchiveCodec.decode(ArchiveCodec.encode(store.conversations())).single.messages.single;
      expect(back.reactions, {'acc-alice': '😺', 'acc-carol': '👍'});
      expect(back.reactionStickers, {'acc-alice': _ref});
    });

    test('an archive written before any of this still reads', () {
      // No sticker, no overlay, no reactionStickers — the shape every existing
      // archive on every existing device has.
      final back = roundTrip([text('c1')]).single.messages.single;

      expect(back.body, 'hallo');
      expect(back.sticker, isNull);
      expect(back.customEmoji, isNull);
      expect(back.reactionStickers, isEmpty);
    });
  });
}
