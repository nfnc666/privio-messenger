import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/chat_poll_card.dart';

import 'deletion_test.dart' show buildServices, storeWith, text;
import 'group_receipts_test.dart' show groupOf;

const _options = ['Montag', 'Dienstag', 'Mittwoch'];

Message pollMessage(
  String clientId, {
  bool isMine = false,
  String? author,
  ChatPoll poll = const ChatPoll(options: _options),
}) =>
    Message(
      id: 'envelope-$clientId',
      clientId: clientId,
      body: 'Wann treffen wir uns?',
      kind: MessageKind.poll,
      poll: poll,
      sentAt: DateTime(2026, 1, 1, 12),
      isMine: isMine,
      senderAccountId: isMine ? null : (author ?? 'account-bob'),
    );

IncomingMessage arriving(MessagePayload payload, {String from = 'account-bob', int envelope = 7}) =>
    IncomingMessage(
      envelopeId: envelope,
      senderAccountId: from,
      payload: payload,
      receivedAt: DateTime(2026, 1, 1, 12, 10),
    );

ChatPoll pollIn(InMemoryMessageStore store, [int index = 0]) =>
    store.conversationWith('account-bob')!.messages[index].poll!;

void main() {
  group('the wire format', () {
    test('a poll is a message that carries its question and answers', () {
      const payload = MessagePayload.poll(
        body: 'Wann?',
        poll: ChatPollPayload.ask(options: _options, maxChoices: 2),
        clientId: 'p1',
      );
      final decoded = MessagePayload.decode(payload.encode());

      expect(decoded.isPoll, isTrue);
      expect(decoded.isControl, isFalse, reason: 'it is filed and shown like a message');
      expect(decoded.body, 'Wann?');
      expect(decoded.poll!.options, _options);
      expect(decoded.poll!.maxChoices, 2);
      expect(decoded.clientId, 'p1');
    });

    test('a vote carries the poll it is for and the whole choice, nothing else', () {
      const payload = MessagePayload.pollAction(ChatPollPayload.vote(target: 'p1', choices: [0, 2]));
      final json = jsonDecode(payload.encode()) as Map<String, dynamic>;
      expect(json['t'], 'vote');
      expect(json.keys.toSet(), {'v', 't', 'b', 'pt', 'pc'});

      final decoded = MessagePayload.decode(payload.encode());
      expect(decoded.isPollAction, isTrue);
      expect(decoded.isControl, isTrue, reason: 'a vote must never become a bubble');
      expect(decoded.poll!.target, 'p1');
      expect(decoded.poll!.choices, [0, 2]);
    });

    test('ending a poll names it and carries nothing else', () {
      const payload = MessagePayload.pollAction(ChatPollPayload.end('p1'));
      final json = jsonDecode(payload.encode()) as Map<String, dynamic>;
      expect(json['t'], 'pollend');
      expect(json.keys.toSet(), {'v', 't', 'b', 'pt'});
      final decoded = MessagePayload.decode(payload.encode());
      expect(decoded.isPollAction, isTrue);
      expect(decoded.poll!.isEnd, isTrue);
    });

    test('attaching the profile key does not drop the poll', () {
      const payload = MessagePayload.poll(
        body: 'Wann?',
        poll: ChatPollPayload.ask(options: _options),
        clientId: 'p1',
      );
      final withKey = payload.withProfileKey('key');
      expect(withKey.isPoll, isTrue);
      expect(withKey.poll!.options, _options);
      expect(withKey.profileKey, 'key');
      expect(withKey.clientId, 'p1');
    });
  });

  group('the poll', () {
    test('has limits, checked rather than trimmed', () {
      expect(ChatPoll.isValid('Frage?', ['a', 'b'], 1), isTrue);
      expect(ChatPoll.isValid('Frage?', ['a'], 1), isFalse, reason: 'one answer is not a question');
      expect(ChatPoll.isValid('', ['a', 'b'], 1), isFalse);
      expect(ChatPoll.isValid('Frage?', ['a', ' '], 1), isFalse);
      expect(ChatPoll.isValid('Frage?', ['a', 'b'], 3), isFalse, reason: 'more picks than answers');
      expect(ChatPoll.isValid('Frage?', List.filled(13, 'x'), 1), isFalse);
      expect(ChatPoll.isValid('Frage?', ['a', 'x' * 101], 1), isFalse);
    });

    test('one vote per person, replaced when they change it, gone when they take it back', () {
      var poll = const ChatPoll(options: _options);
      poll = poll.withVote('bob', {0}).withVote('carol', {0}).withVote('bob', {2});
      expect(poll.countFor(0), 1);
      expect(poll.countFor(2), 1);
      expect(poll.voters, 2);
      poll = poll.withVote('carol', {});
      expect(poll.voters, 1);
      expect(poll.shareOf(2), 1.0);
    });

    test('takes only what it allows', () {
      const single = ChatPoll(options: _options);
      expect(single.accepts([1]), isTrue);
      expect(single.accepts([]), isTrue, reason: 'empty takes a vote back');
      expect(single.accepts([0, 1]), isFalse);
      expect(single.accepts([3]), isFalse);
      expect(single.accepts([-1]), isFalse);
      const several = ChatPoll(options: _options, maxChoices: 2);
      expect(several.accepts([0, 2]), isTrue);
      expect(several.accepts([0, 0]), isFalse, reason: 'no counting one answer twice');
    });
  });

  group('the store', () {
    test('records a vote, and an ended poll takes no more', () {
      final store = storeWith([pollMessage('p1')]);
      expect(
        store.applyPollVote(conversationId: 'account-bob', clientId: 'p1', accountId: 'a', choices: {1}),
        isTrue,
      );
      expect(store.closePoll(conversationId: 'account-bob', clientId: 'p1'), isTrue);
      expect(
        store.applyPollVote(conversationId: 'account-bob', clientId: 'p1', accountId: 'b', choices: {0}),
        isFalse,
      );
      expect(pollIn(store).voters, 1);
      expect(pollIn(store).closed, isTrue);
    });

    test('a vote for something that is not a poll is dropped', () {
      final store = storeWith([text('c1')]);
      expect(
        store.applyPollVote(conversationId: 'account-bob', clientId: 'c1', accountId: 'a', choices: {0}),
        isFalse,
      );
    });
  });

  group('asking, voting and ending from this device', () {
    test('a poll is filed here and sent sealed', () async {
      final store = storeWith([]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      final sent = await controller.sendPoll(
        'account-bob',
        question: ' Wann treffen wir uns? ',
        options: [' Montag ', 'Dienstag'],
      );

      expect(sent, isTrue);
      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.kind, MessageKind.poll);
      expect(message.body, 'Wann treffen wir uns?');
      expect(message.poll!.options, ['Montag', 'Dienstag']);
      expect(messaging.sent.single.isPoll, isTrue);
      expect(messaging.sent.single.poll!.options, ['Montag', 'Dienstag']);
      expect(messaging.sent.single.clientId, message.clientId);
    });

    test('a poll outside the limits is not sent', () async {
      final store = storeWith([]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      final sent = await controller.sendPoll('account-bob', question: 'Wann?', options: ['nur eins']);

      expect(sent, isFalse);
      expect(store.conversationWith('account-bob')!.messages, isEmpty);
      expect(messaging.sent, isEmpty);
    });

    test('a vote is counted here and sent whole', () async {
      final store = storeWith([pollMessage('p1', poll: const ChatPoll(options: _options, maxChoices: 2))]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      final poll = store.conversationWith('account-bob')!.messages.single;

      await controller.vote('account-bob', poll, {2, 0});

      expect(pollIn(store).choicesOf('account-alice'), {0, 2});
      final vote = messaging.sent.single;
      expect(vote.isPollAction, isTrue);
      expect(vote.poll!.target, 'p1');
      expect(vote.poll!.choices, [0, 2]);

      await controller.vote('account-bob', store.conversationWith('account-bob')!.messages.single, {0, 2});
      expect(messaging.sent, hasLength(1), reason: 'the same vote again is not a change');
    });

    test('only the person who asked can end a poll', () async {
      final store = storeWith([pollMessage('mine', isMine: true), pollMessage('theirs')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      final messages = store.conversationWith('account-bob')!.messages;

      await controller.endPoll('account-bob', messages[1]);
      expect(pollIn(store, 1).closed, isFalse);
      expect(messaging.sent, isEmpty);

      await controller.endPoll('account-bob', messages[0]);
      expect(pollIn(store, 0).closed, isTrue);
      expect(messaging.sent.single.poll!.isEnd, isTrue);
    });
  });

  group('what arrives', () {
    test('a poll arrives as a poll', () async {
      final store = storeWith([]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(arriving(const MessagePayload.poll(
        body: 'Wann?',
        poll: ChatPollPayload.ask(options: _options),
        clientId: 'p1',
      )));
      await controller.drain();

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.kind, MessageKind.poll);
      expect(message.poll!.options, _options);
      expect(message.senderAccountId, 'account-bob');
    });

    test('a poll outside the limits arrives as its question, not as a poll', () async {
      final store = storeWith([]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(arriving(const MessagePayload.poll(
        body: 'Wann?',
        poll: ChatPollPayload.ask(options: ['nur eins']),
        clientId: 'p1',
      )));
      await controller.drain();

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.kind, MessageKind.text);
      expect(message.body, 'Wann?');
      expect(message.poll, isNull);
    });

    test('a vote counts for whoever the session says sent it', () async {
      final store = storeWith([pollMessage('p1', isMine: true)]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(arriving(
        const MessagePayload.pollAction(ChatPollPayload.vote(target: 'p1', choices: [1])),
      ));
      await controller.drain();

      expect(pollIn(store).choicesOf('account-bob'), {1});
      expect(pollIn(store).choicesOf('account-alice'), isEmpty);
      expect(store.conversationWith('account-bob')!.messages, hasLength(1), reason: 'never a bubble');
    });

    test('a vote the poll cannot take is dropped', () async {
      final store = storeWith([pollMessage('p1', isMine: true)]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(arriving(
        const MessagePayload.pollAction(ChatPollPayload.vote(target: 'p1', choices: [0, 1])),
      ));
      messaging.inbox.add(arriving(
        const MessagePayload.pollAction(ChatPollPayload.vote(target: 'p1', choices: [9])),
        envelope: 8,
      ));
      await controller.drain();

      expect(pollIn(store).voters, 0);
    });

    test('nobody can end a poll somebody else asked', () async {
      final store = storeWith([
        pollMessage('mine', isMine: true),
        pollMessage('carols', author: 'account-carol'),
      ]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(arriving(const MessagePayload.pollAction(ChatPollPayload.end('mine'))));
      messaging.inbox.add(
        arriving(const MessagePayload.pollAction(ChatPollPayload.end('carols')), envelope: 8),
      );
      await controller.drain();

      expect(pollIn(store, 0).closed, isFalse);
      expect(pollIn(store, 1).closed, isFalse);
    });

    test('the person who asked can end it, and later votes are dropped', () async {
      final store = storeWith([pollMessage('p1')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(arriving(const MessagePayload.pollAction(ChatPollPayload.end('p1'))));
      messaging.inbox.add(arriving(
        const MessagePayload.pollAction(ChatPollPayload.vote(target: 'p1', choices: [0])),
        envelope: 8,
      ));
      await controller.drain();

      expect(pollIn(store).closed, isTrue);
      expect(pollIn(store).voters, 0);
    });

    test('a vote for a message that is not a poll changes nothing', () async {
      final store = storeWith([text('c1', body: 'kein Poll')]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(arriving(
        const MessagePayload.pollAction(ChatPollPayload.vote(target: 'c1', choices: [0])),
      ));
      await controller.drain();

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.kind, MessageKind.text);
      expect(message.poll, isNull);
    });
  });

  test('a poll, its votes and its end survive the archive', () async {
    final store = storeWith([pollMessage('p1', isMine: true)]);
    store.applyPollVote(conversationId: 'account-bob', clientId: 'p1', accountId: 'account-bob', choices: {2});
    store.closePoll(conversationId: 'account-bob', clientId: 'p1');
    final archive = EncryptedMessageArchive(
      storage: InMemoryArchiveStorage(),
      keyStore: InMemorySecureStore(),
    );
    await archive.save(store.conversations());

    final restored = (await archive.load()).conversations.single.messages.single;
    expect(restored.kind, MessageKind.poll);
    expect(restored.poll!.options, _options);
    expect(restored.poll!.choicesOf('account-bob'), {2});
    expect(restored.poll!.closed, isTrue);
  });

  test('the chat list says it is a poll', () async {
    final store = storeWith([pollMessage('p1')]);
    final (services, _) = await buildServices(store);
    final controller = ConversationController(services)..accountId = 'account-alice';

    final preview = controller.chats.single.preview;
    expect(preview.kind, ChatPreviewKind.poll);
    expect(preview.text, 'Wann treffen wir uns?');
  });

  group('the card', () {
    Future<List<Set<int>>> show(WidgetTester tester, ChatPoll poll, {Set<int> mine = const {}}) async {
      final votes = <Set<int>>[];
      await tester.pumpWidget(MaterialApp(
        theme: PrivioTheme.dark(),
        locale: const Locale('de'),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Scaffold(
          body: ChatPollCard(question: 'Wann?', poll: poll, myChoices: mine, onVote: votes.add),
        ),
      ));
      return votes;
    }

    testWidgets('a one-answer poll is answered by the tap, and results show only afterwards',
        (tester) async {
      final poll = const ChatPoll(options: _options).withVote('account-bob', {1});
      final votes = await show(tester, poll);
      expect(find.text('1'), findsNothing, reason: 'no counts before this account has voted');

      await tester.tap(find.text('Mittwoch'));
      expect(votes, [{2}]);

      await show(tester, poll.withVote('account-alice', {2}), mine: {2});
      expect(find.text('1'), findsNWidgets(2));
    });

    testWidgets('an ended poll says so and takes no votes', (tester) async {
      final votes = await show(tester, const ChatPoll(options: _options).asClosed());
      expect(find.textContaining('beendet'), findsOneWidget);
      await tester.tap(find.text('Montag'));
      expect(votes, isEmpty);
    });
  });

  group('in a group', () {
    IncomingMessage inGroup(MessagePayload payload, String from, int envelope) => IncomingMessage(
          envelopeId: envelope,
          senderAccountId: from,
          groupId: 'group-1',
          payload: payload,
          receivedAt: DateTime(2026, 1, 1, 12, 10),
        );

    test('a poll is asked of everyone and each vote counts for the member who cast it', () async {
      final store = groupOf(3);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.sendPoll('group-1', question: 'Wohin?', options: ['See', 'Berg']);
      expect(messaging.sentToGroup.single.isPoll, isTrue, reason: 'sent to the group, sealed per device');
      final clientId = store.conversationWith('group-1')!.messages.single.clientId!;

      messaging.inbox
        ..add(inGroup(MessagePayload.pollAction(ChatPollPayload.vote(target: clientId, choices: const [0])), 'account-bob', 2))
        ..add(inGroup(MessagePayload.pollAction(ChatPollPayload.vote(target: clientId, choices: const [1])), 'account-carol', 3));
      await controller.drain();

      final poll = store.conversationWith('group-1')!.messages.single.poll!;
      expect(poll.choicesOf('account-bob'), {0});
      expect(poll.choicesOf('account-carol'), {1});
      expect(store.conversationWith('group-1')!.messages, hasLength(1));
    });

    test('a member cannot end a poll another member asked', () async {
      final store = groupOf(3);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';

      messaging.inbox.add(inGroup(
        const MessagePayload.poll(body: 'Wohin?', poll: ChatPollPayload.ask(options: ['See', 'Berg']), clientId: 'bobs'),
        'account-bob',
        2,
      ));
      messaging.inbox.add(inGroup(const MessagePayload.pollAction(ChatPollPayload.end('bobs')), 'account-carol', 3));
      await controller.drain();

      final message = store.conversationWith('group-1')!.messages.single;
      expect(message.kind, MessageKind.poll);
      expect(message.poll!.closed, isFalse);
    });
  });
}
