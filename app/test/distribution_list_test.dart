import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/distribution_list.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chats_screen.dart';
import 'package:privio/screens/distribution_lists_screen.dart';

import 'deletion_test.dart' show buildServices, storeWith;
import 'widget_test.dart' show quietServices, wrap;

/// Distribution lists: one message, sent as that many ordinary one-to-one
/// messages.
///
/// What these pin is that nobody on a list can learn from what arrives that
/// a list exists or who else is on it, that each copy behaves exactly as if it
/// had been sent by hand, and that the list never leaves this device.

/// Bob and Carol, each with a chat on this device.
InMemoryMessageStore bobAndCarol() => storeWith([])
  ..upsertUser(const KnownUser(accountId: 'account-carol', username: 'carol'));

Future<ConversationController> controllerOver(InMemoryMessageStore store) async {
  final (services, _) = await buildServices(store);
  final controller = ConversationController(services)..accountId = 'account-alice';
  addTearDown(controller.stop);
  return controller;
}

List<Message> mineWith(InMemoryMessageStore store, String id) =>
    store.conversationWith(id)!.messages.where((message) => message.isMine).toList();

void main() {
  group('a list', () {
    test('has a name and between one and the most people, each once', () {
      expect(DistributionList.isValid('Team', ['a']), isTrue);
      expect(DistributionList.isValid('   ', ['a']), isFalse);
      expect(DistributionList.isValid('x' * (DistributionList.maxNameLength + 1), ['a']), isFalse);
      expect(DistributionList.isValid('Team', []), isFalse);
      expect(DistributionList.isValid('Team', ['a', 'a']), isFalse);
      expect(
        DistributionList.isValid('Team', [for (var i = 0; i <= DistributionList.maxMembers; i++) '$i']),
        isFalse,
      );
    });

    test('reads back only what it wrote', () {
      const list = DistributionList(id: 'l1', name: 'Team', memberIds: ['a', 'b']);
      final back = DistributionList.fromJson(list.toJson())!;
      expect(back.id, 'l1');
      expect(back.name, 'Team');
      expect(back.memberIds, ['a', 'b']);
      expect(DistributionList.fromJson({'id': 'l1', 'n': '', 'm': ['a']}), isNull);
      expect(DistributionList.fromJson('Team'), isNull);
    });

    test('survives the archive, and an archive without lists reads as none', () async {
      final archive = EncryptedMessageArchive(
        storage: InMemoryArchiveStorage(),
        keyStore: InMemorySecureStore(),
      );
      await archive.save(const []);
      expect((await archive.load()).distributionLists, isEmpty);

      await archive.save(
        const [],
        distributionLists: const [DistributionList(id: 'l1', name: 'Team', memberIds: ['a'])],
      );
      expect((await archive.load()).distributionLists.single.name, 'Team');
    });
  });

  group('keeping lists', () {
    test('only people with a chat here, not this account, each once', () async {
      final controller = await controllerOver(bobAndCarol());
      // Saved is a chat with this account's own id, as in the app, so the
      // account would otherwise count as somebody with a chat here.
      controller.ensureSaved(username: 'alice');

      final id = controller.createDistributionList(
        '  Team  ',
        ['account-bob', 'account-alice', 'account-nobody', 'account-carol', 'account-bob'],
      );
      final list = controller.distributionList(id!)!;
      expect(list.name, 'Team');
      expect(list.memberIds, ['account-bob', 'account-carol']);

      expect(controller.createDistributionList('', ['account-bob']), isNull);
      expect(controller.createDistributionList('Leer', ['account-nobody']), isNull);
    });

    test('rename, change who is on it, and refuse what would not be a list', () async {
      final controller = await controllerOver(bobAndCarol());
      final id = controller.createDistributionList('Team', ['account-bob'])!;

      expect(controller.updateDistributionList(id, name: 'Wanderung', accountIds: ['account-carol']), isTrue);
      expect(controller.distributionList(id)!.name, 'Wanderung');
      expect(controller.distributionList(id)!.memberIds, ['account-carol']);

      expect(controller.updateDistributionList(id, name: ' '), isFalse);
      expect(controller.updateDistributionList(id, accountIds: ['account-nobody']), isFalse);
      expect(controller.distributionList(id)!.name, 'Wanderung');
      expect(controller.updateDistributionList('missing', name: 'x'), isFalse);
    });

    test('are saved, and read back even with no chats at all', () async {
      final store = bobAndCarol();
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      controller.createDistributionList('Team', ['account-bob']);
      // Not `flush`, which writes whatever is there.
      await Future<void>.delayed(const Duration(seconds: 1));

      final later = ConversationController(services)..accountId = 'account-alice';
      addTearDown(later.stop);
      await later.restore();
      expect(later.distributionLists.single.name, 'Team');
    });

    test('going to the background writes them at once', () async {
      final store = bobAndCarol();
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      controller.createDistributionList('Team', ['account-bob']);

      await controller.flush();
      expect((await services.archive.load()).distributionLists.single.name, 'Team');
    });

    test('deleting the list leaves what was sent', () async {
      final store = bobAndCarol();
      final controller = await controllerOver(store);
      final id = controller.createDistributionList('Team', ['account-bob'])!;
      await controller.sendToList(id, 'hallo');

      expect(controller.deleteDistributionList(id), isTrue);
      expect(controller.distributionLists, isEmpty);
      expect(mineWith(store, 'account-bob'), hasLength(1));
      expect(controller.deleteDistributionList(id), isFalse);
    });
  });

  group('sending', () {
    test('each person gets an ordinary message of their own, and nothing about the list', () async {
      final store = bobAndCarol();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      final id = controller.createDistributionList('Team', ['account-bob', 'account-carol'])!;

      expect(await controller.sendToList(id, '  Treffen um 8  '), 2);

      expect(mineWith(store, 'account-bob').single.body, 'Treffen um 8');
      expect(mineWith(store, 'account-carol').single.body, 'Treffen um 8');
      expect(messaging.sent, hasLength(2));
      final ids = {for (final payload in messaging.sent) payload.clientId};
      expect(ids, hasLength(2), reason: 'two people shared one message id');
      for (final payload in messaging.sent) {
        final json = jsonDecode(payload.encode()) as Map<String, dynamic>;
        expect(json['t'], 'text');
        expect(json.keys.toSet(), {'v', 't', 'b', 'ci'},
            reason: 'something about the list went out with the message');
        expect(payload.encode(), isNot(contains('carol')));
        expect(payload.encode(), isNot(contains('Team')));
      }
    });

    test('each copy follows its own chat, as if it had been sent by hand', () async {
      final store = bobAndCarol();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      store.setChatTimer('account-carol', const ChatTimer.after(Duration(hours: 1)));
      final id = controller.createDistributionList('Team', ['account-bob', 'account-carol'])!;

      await controller.sendToList(id, 'hallo');

      final timers = [for (final payload in messaging.sent) payload.expiresInSeconds];
      expect(timers, [null, 3600]);
    });

    test('somebody without a chat any more is skipped, and nothing is sent for nothing',
        () async {
      final store = bobAndCarol();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      final id = controller.createDistributionList('Team', ['account-bob', 'account-carol'])!;

      // Blocking removes the chat.
      store.removeConversation('account-carol');
      expect(await controller.sendToList(id, 'hallo'), 1);
      expect(messaging.sent, hasLength(1));

      expect(await controller.sendToList(id, '   '), 0);
      expect(await controller.sendToList('missing', 'hallo'), 0);
      expect(messaging.sent, hasLength(1));
    });
  });

  group('on screen', () {
    Future<AppState> withContacts() async {
      final services = await quietServices(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'contacts': [
                {'id': 'acc-bob', 'username': 'bob', 'displayName': 'Bob'},
                {'id': 'acc-carol', 'username': 'carol', 'displayName': 'Carol'},
              ],
              'envelopes': <Object>[],
              'more': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final state = AppState(services: services, store: InMemorySecureStore());
      await state.initialise();
      state.conversations.accountId = 'acc-alice';
      await state.conversations.refreshContacts();
      return state;
    }

    testWidgets('the chat list leads to the lists', (tester) async {
      final state = await withContacts();
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ChatsScreen(), state));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('lists-open')));
      await tester.pumpAndSettle();
      expect(find.byType(DistributionListsScreen), findsOneWidget);
      expect(find.textContaining('does not see who else got it'), findsOneWidget);
    });

    testWidgets('make a list, write to it, change it, delete it', (tester) async {
      final state = await withContacts();
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const DistributionListsScreen(), state));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('lists-new')));
      await tester.pumpAndSettle();
      // Saving with nobody picked says what is missing and keeps the screen.
      await tester.enterText(find.byKey(const Key('list-name')), 'Team');
      await tester.tap(find.byKey(const Key('list-save')));
      await tester.pump();
      expect(find.text('Give the list a name and pick at least one person.'), findsOneWidget);
      // Gone again before going on: it sits over the bottom of the screen,
      // where the send button will be. Its clock starts once it is fully in.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bob'));
      await tester.tap(find.text('Carol'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('list-save')));
      await tester.pumpAndSettle();
      expect(find.text('Team'), findsOneWidget);
      expect(find.text('2 people'), findsOneWidget);

      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The list itself stays on this device.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('list-message')), 'Treffen um 8');
      await tester.tap(find.byKey(const Key('list-send')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Sent to 2 people.'), findsOneWidget);
      for (final id in ['acc-bob', 'acc-carol']) {
        expect(
          state.conversations.messagesWith(id).where((m) => m.isMine).single.body,
          'Treffen um 8',
        );
      }
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.byKey(const Key('list-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carol'));
      await tester.tap(find.byKey(const Key('list-save')));
      await tester.pumpAndSettle();
      expect(state.conversations.distributionLists.single.memberIds, ['acc-bob']);

      await tester.tap(find.byKey(const Key('list-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.conversations.distributionLists, hasLength(1));
      await tester.tap(find.byKey(const Key('list-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(state.conversations.distributionLists, isEmpty);
      expect(find.byType(DistributionListsScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
