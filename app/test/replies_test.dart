import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';

Message text(String clientId, {bool isMine = false, String body = 'hallo'}) => Message(
      id: clientId,
      clientId: clientId,
      body: body,
      sentAt: DateTime(2026),
      isMine: isMine,
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
  group('the reaction payload', () {
    test('survives encoding and is never a message', () {
      const payload = MessagePayload.reaction(reactionTo: 'c1', reactionEmoji: '👍');
      final decoded = MessagePayload.decode(payload.encode());

      expect(decoded.isReaction, isTrue);
      expect(decoded.isControl, isTrue);
      expect(decoded.reactionTo, 'c1');
      expect(decoded.reactionEmoji, '👍');
      expect(decoded.body, isEmpty);
    });

    test('an empty emoji means "take it back"', () {
      const payload = MessagePayload.reaction(reactionTo: 'c1', reactionEmoji: '');
      final decoded = MessagePayload.decode(payload.encode());
      expect(decoded.isReaction, isTrue);
      expect(decoded.clearsReaction, isTrue);
    });
  });

  group('the reply payload', () {
    test('carries its own quote, so the reply reads without the original', () {
      const payload = MessagePayload.text(
        'Ja, um sieben',
        clientId: 'c2',
        replyToId: 'c1',
        replyPreview: 'Treffen wir uns?',
        replySender: 'You',
      );
      final decoded = MessagePayload.decode(payload.encode());

      expect(decoded.replyToId, 'c1');
      expect(decoded.replyPreview, 'Treffen wir uns?');
      expect(decoded.replySender, 'You');
      expect(decoded.body, 'Ja, um sieben');
      expect(decoded.isControl, isFalse, reason: 'a reply is still a message');
    });

    test('the quote survives having a profile key attached', () {
      const payload = MessagePayload.text(
        'Ja',
        clientId: 'c2',
        replyToId: 'c1',
        replyPreview: 'Treffen?',
      );
      final withKey = payload.withProfileKey('a2V5');
      expect(withKey.replyToId, 'c1');
      expect(withKey.replyPreview, 'Treffen?');
      expect(withKey.clientId, 'c2');
    });

    test('a media reply keeps both the file and the quote', () {
      const payload = MessagePayload.media(
        mediaId: 'm1',
        mediaKey: 'a2V5',
        mediaType: 'image/jpeg',
        byteSize: 10,
        clientId: 'c3',
        replyToId: 'c1',
        replyPreview: 'Zeig mal',
      );
      final decoded = MessagePayload.decode(payload.encode());
      expect(decoded.isMedia, isTrue);
      expect(decoded.replyToId, 'c1');
      expect(decoded.replyPreview, 'Zeig mal');
    });
  });

  group('reactions on a message', () {
    test('are one per person, and replaced rather than added to', () {
      final store = storeWith([text('c1')]);

      expect(
        store.applyReaction(
          conversationId: 'acc-bob',
          targetClientId: 'c1',
          accountId: 'acc-alice',
          emoji: '👍',
        ),
        isTrue,
      );
      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'acc-alice',
        emoji: '❤️',
      );

      final reactions = store.conversationWith('acc-bob')!.messages.single.reactions;
      expect(reactions, {'acc-alice': '❤️'});
    });

    test('an empty emoji takes one back', () {
      final store = storeWith([text('c1')]);
      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'acc-alice',
        emoji: '👍',
      );
      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'acc-alice',
        emoji: '',
      );
      expect(store.conversationWith('acc-bob')!.messages.single.reactions, isEmpty);
    });

    test('several people can react to the same message', () {
      final store = storeWith([text('c1')]);
      for (final who in ['a', 'b', 'c']) {
        store.applyReaction(
          conversationId: 'acc-bob',
          targetClientId: 'c1',
          accountId: who,
          emoji: '👍',
        );
      }
      expect(store.conversationWith('acc-bob')!.messages.single.reactions, hasLength(3));
    });

    test('a reaction to a message this device does not have is dropped', () {
      final store = storeWith([text('c1')]);
      expect(
        store.applyReaction(
          conversationId: 'acc-bob',
          targetClientId: 'gone',
          accountId: 'acc-alice',
          emoji: '👍',
        ),
        isFalse,
        reason: 'nothing to attach it to, and inventing a message would be worse',
      );
      expect(store.conversationWith('acc-bob')!.messages, hasLength(1));
    });

    test('reacting the same way twice changes nothing', () {
      final store = storeWith([text('c1')]);
      store.applyReaction(
        conversationId: 'acc-bob',
        targetClientId: 'c1',
        accountId: 'a',
        emoji: '👍',
      );
      expect(
        store.applyReaction(
          conversationId: 'acc-bob',
          targetClientId: 'c1',
          accountId: 'a',
          emoji: '👍',
        ),
        isFalse,
      );
    });
  });

  group('the quote a reply carries', () {
    test('is the text, shortened when it is long', () {
      expect(ConversationController.previewOfMessage(text('c1', body: 'kurz')), 'kurz');

      final long = ConversationController.previewOfMessage(
        text('c2', body: 'a' * 300),
      );
      expect(long.length, lessThanOrEqualTo(120));
      expect(long, endsWith('…'));
    });

    test('names the kind when there is no text', () {
      final voice = Message(
        id: 'v',
        body: '',
        sentAt: DateTime(2026),
        isMine: false,
        kind: MessageKind.voice,
      );
      expect(ConversationController.previewOfMessage(voice), 'Voice message');
    });
  });

  test('replies and reactions survive a restart', () async {
    final archive = EncryptedMessageArchive(
      storage: InMemoryArchiveStorage(),
      keyStore: InMemorySecureStore(),
    );
    await archive.save([
      Conversation.direct(
        const KnownUser(accountId: 'acc-bob', username: 'bob'),
        messages: [
          Message(
            id: 'c2',
            clientId: 'c2',
            body: 'Ja, um sieben',
            sentAt: DateTime.utc(2026, 4, 1, 18),
            isMine: true,
            replyToId: 'c1',
            replyPreview: 'Treffen wir uns?',
            replySender: 'bob',
            reactions: const {'acc-bob': '👍'},
          ),
        ],
      ),
    ]);

    final message = (await archive.load()).conversations.single.messages.single;
    expect(message.isReply, isTrue);
    expect(message.replyToId, 'c1');
    expect(message.replyPreview, 'Treffen wir uns?');
    expect(message.replySender, 'bob');
    expect(message.reactions, {'acc-bob': '👍'});
  });
}
