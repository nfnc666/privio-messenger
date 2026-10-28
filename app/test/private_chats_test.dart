import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/passcode.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/screens/chats_screen.dart';
import 'package:privio/screens/privacy_screen.dart';

import 'deletion_test.dart' show buildServices, storeWith, text;
import 'saved_test.dart' show signedInAs;
import 'widget_test.dart' show quietServices, wrap;

/// Private chats: kept out of the list, the search and the chat screen until
/// the account's own code is typed, and hidden again whenever the app is left.
///
/// What these pin is that "hidden" has no gaps a person holding the unlocked
/// phone could walk through, that the code is never kept as itself, and that
/// a forgotten code costs the private chats and nothing else.

const code = '2468';

Finder lockReading(String words) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == words,
    );

/// A controller over Bob's chat and Carol's, with a code already set.
Future<(ConversationController, InMemoryMessageStore, PrivioServices)> withCode() async {
  final store = storeWith([text('b1', body: 'geheim')])
    ..upsertUser(const KnownUser(accountId: 'account-carol', username: 'carol'))
    ..append('account-carol', text('c1', body: 'offen', author: 'account-carol'));
  final (services, _) = await buildServices(store);
  final controller = ConversationController(services)..accountId = 'account-alice';
  addTearDown(controller.stop);
  expect(await controller.setPrivateChatsCode(code), PrivateCodeOutcome.saved);
  return (controller, store, services);
}

List<String> rowIds(ConversationController controller) =>
    controller.chats.map((chat) => chat.id).toList();

/// Bob, with one message, in a signed-in state that has a code and has made
/// Bob's chat private.
Future<AppState> signedInWithPrivateBob() async {
  final state = await signedInAs('acc-alice');
  state.services.store
    ..upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'))
    ..append(
      'acc-bob',
      Message(
        id: 'b1',
        clientId: 'b1',
        body: 'geheim',
        sentAt: DateTime(2026, 9, 22, 18),
        isMine: false,
        senderAccountId: 'acc-bob',
      ),
    );
  await state.conversations.setPrivateChatsCode(code);
  state.conversations.setPrivate('acc-bob', isPrivate: true);
  return state;
}

Future<void> typeCode(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const Key('private-code-field')), value);
  await tester.tap(find.text('Show'));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('the code', () {
    test('is kept as a hash, for one account', () async {
      final store = InMemorySecureStore();
      await store.setPrivateChatsCode('acc-a', code);

      expect(store.entriesForTest.values.any((value) => value.contains(code)), isFalse,
          reason: 'the code was stored as itself',
      );
      expect(await store.verifyPrivateChatsCode('acc-a', code), isTrue);
      expect(await store.verifyPrivateChatsCode('acc-a', '1357'), isFalse);
      expect(await store.hasPrivateChatsCode('acc-b'), isFalse);
      expect(await store.verifyPrivateChatsCode('acc-b', code), isFalse);

      await store.setPrivateChatsCode('acc-a', null);
      expect(await store.hasPrivateChatsCode('acc-a'), isFalse);
    });

    test('is at least four characters, and not the screen lock', () async {
      final store = storeWith([text('b1')]);
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      expect(await controller.setPrivateChatsCode('123'), PrivateCodeOutcome.tooShort);
      await services.secureStore.setPasscode(code, PasscodeKind.digits4);
      expect(await controller.setPrivateChatsCode(code), PrivateCodeOutcome.sameAsUnlock);
      expect(controller.hasPrivateChatsCode, isFalse);

      expect(await controller.setPrivateChatsCode('1357'), PrivateCodeOutcome.saved);
      expect(controller.hasPrivateChatsCode, isTrue);
    });

    test('changing it takes the current one', () async {
      final (controller, _, services) = await withCode();
      final secure = services.secureStore;

      expect(await controller.setPrivateChatsCode('9999'), PrivateCodeOutcome.wrongCode);
      expect(await controller.setPrivateChatsCode('9999', current: '1111'), PrivateCodeOutcome.wrongCode);
      expect(await secure.verifyPrivateChatsCode('account-alice', code), isTrue);

      expect(await controller.setPrivateChatsCode('9999', current: code), PrivateCodeOutcome.saved);
      expect(await secure.verifyPrivateChatsCode('account-alice', '9999'), isTrue);
    });

    test('is read at sign-in', () async {
      final store = storeWith([text('b1')]);
      final (services, _) = await buildServices(store);
      await services.secureStore.setPrivateChatsCode('account-alice', code);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      expect(controller.hasPrivateChatsCode, isFalse);
      await controller.loadPrivateChatsCode();
      expect(controller.hasPrivateChatsCode, isTrue);
    });
  });

  group('the store', () {
    test('a refresh of the contact or the group keeps it private', () {
      final store = storeWith([text('b1')])
        ..upsertGroup(const GroupInfo(groupId: 'g1', role: 'member', name: 'Wanderung'))
        ..setPrivate('account-bob', isPrivate: true)
        ..setPrivate('g1', isPrivate: true);

      store
        ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'), authoritative: true)
        ..upsertGroup(const GroupInfo(groupId: 'g1', role: 'member', name: 'Wandern'), authoritative: true);
      expect(store.conversationWith('account-bob')!.isPrivate, isTrue);
      expect(store.conversationWith('g1')!.isPrivate, isTrue);
      expect(store.setPrivate('account-bob', isPrivate: true), isFalse);
      expect(store.setPrivate('nobody', isPrivate: true), isFalse);
    });

    test('it survives the archive, for a group too, and once the chat is empty', () async {
      // A private chat emptied by its timer is still private. Left out of the
      // archive, it would come back as nothing, and the next message from that
      // person would arrive in the open.
      final store = storeWith([text('b1')])
        ..upsertUser(const KnownUser(accountId: 'account-carol', username: 'carol'))
        ..append('account-carol', text('c1', author: 'account-carol'))
        ..upsertGroup(const GroupInfo(groupId: 'g1', role: 'member', name: 'Wanderung'))
        ..setPrivate('account-bob', isPrivate: true)
        ..setPrivate('g1', isPrivate: true);
      store.conversationWith('account-bob')!.messages.clear();
      store.conversationWith('account-carol')!.messages.clear();

      final archive = EncryptedMessageArchive(
        storage: InMemoryArchiveStorage(),
        keyStore: InMemorySecureStore(),
      );
      await archive.save(store.conversations());

      final restored = InMemoryMessageStore()..restore((await archive.load()).conversations);
      expect(restored.conversationWith('account-bob')?.isPrivate, isTrue);
      expect(restored.conversationWith('g1')?.isPrivate, isTrue);
      expect(restored.conversationWith('account-carol'), isNull,
          reason: 'an ordinary empty chat is still just a contact',
      );
    });
  });

  group('hidden', () {
    test('a private chat leaves the list and the search until the code', () async {
      final (controller, _, _) = await withCode();
      expect(controller.setPrivate('account-bob', isPrivate: true), isTrue);

      expect(rowIds(controller), ['account-carol']);
      expect(controller.searchMessages('geheim'), isEmpty);

      expect(await controller.showPrivateChats('1111'), isFalse);
      expect(rowIds(controller), ['account-carol']);

      expect(await controller.showPrivateChats(code), isTrue);
      expect(rowIds(controller), containsAll(['account-bob', 'account-carol']));
      expect(controller.chats.firstWhere((chat) => chat.id == 'account-bob').isPrivate, isTrue);
      expect(controller.searchMessages('geheim'), hasLength(1));

      controller.hidePrivateChats();
      expect(rowIds(controller), ['account-carol']);
    });

    test('hidden before the code has even been read', () async {
      // A chat restored from the archive is private from its first frame. The
      // keystore answers later, and must not open a window in between.
      final store = storeWith([text('b1')])..setPrivate('account-bob', isPrivate: true);
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      expect(controller.hasPrivateChatsCode, isFalse);
      expect(controller.chats, isEmpty);
    });

    test('a timer exception does not name it either', () async {
      final (controller, store, _) = await withCode();
      store.setChatTimer('account-bob', const ChatTimer.after(Duration(hours: 1)));
      expect(controller.timerExceptions(), contains('account-bob'));

      controller.setPrivate('account-bob', isPrivate: true);
      expect(controller.timerExceptions(), isNot(contains('account-bob')));

      await controller.showPrivateChats(code);
      expect(controller.timerExceptions(), contains('account-bob'));
    });
  });

  group('making private', () {
    test('needs a code, and is refused for Saved and for a hidden chat', () async {
      final store = storeWith([text('b1')]);
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      controller.ensureSaved(username: 'alice');

      expect(controller.setPrivate('account-bob', isPrivate: true), isFalse,
          reason: 'with no code nothing could show it again',
      );

      await controller.setPrivateChatsCode(code);
      expect(controller.setPrivate('account-alice', isPrivate: true), isFalse);
      expect(controller.setPrivate('account-bob', isPrivate: true), isTrue);
      expect(controller.setPrivate('account-bob', isPrivate: false), isFalse,
          reason: 'a hidden chat was changed without the code',
      );

      await controller.showPrivateChats(code);
      expect(controller.setPrivate('account-bob', isPrivate: false), isTrue);
      expect(controller.isPrivate('account-bob'), isFalse);
    });

    test('is saved', () async {
      final (controller, _, services) = await withCode();
      controller.setPrivate('account-bob', isPrivate: true);
      // Not `flush`, which writes whatever is there.
      await Future<void>.delayed(const Duration(seconds: 1));

      final restored = InMemoryMessageStore()
        ..restore((await services.archive.load()).conversations);
      expect(restored.conversationWith('account-bob')!.isPrivate, isTrue);
    });
  });

  group('the code going away', () {
    test('removing it takes it, and makes every private chat ordinary', () async {
      final (controller, store, services) = await withCode();
      final secure = services.secureStore;
      controller.setPrivate('account-bob', isPrivate: true);

      expect(await controller.removePrivateChatsCode('1111'), isFalse);
      expect(controller.hasPrivateChatsCode, isTrue);

      expect(await controller.removePrivateChatsCode(code), isTrue);
      expect(controller.hasPrivateChatsCode, isFalse);
      expect(await secure.hasPrivateChatsCode('account-alice'), isFalse);
      expect(store.conversationWith('account-bob')!.isPrivate, isFalse);
      expect(rowIds(controller), containsAll(['account-bob', 'account-carol']));
    });

    test('forgetting it deletes the private chats and the code, and nothing else', () async {
      final (controller, store, services) = await withCode();
      final secure = services.secureStore;
      controller.setPrivate('account-bob', isPrivate: true);

      await controller.deletePrivateChats();

      expect(store.conversationWith('account-bob'), isNull);
      expect(store.conversationWith('account-carol'), isNotNull);
      expect(controller.hasPrivateChatsCode, isFalse);
      expect(await secure.hasPrivateChatsCode('account-alice'), isFalse);
    });
  });

  testWidgets('a signed-in start knows there is a code', (tester) async {
    final secure = InMemorySecureStore();
    await secure.writeSession(token: 'session', username: 'alice', accountId: 'acc-alice');
    final services = await quietServices(
      client: MockClient(
        (request) async => http.Response(
          // Enough of every answer a signed-in start asks for.
          jsonEncode({'contacts': <Object>[], 'envelopes': <Object>[], 'more': false, 'remaining': 100}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    // Where the controller reads it. In the app this is the same store as the
    // one holding the session; the test helper makes its own.
    await services.secureStore.setPrivateChatsCode('acc-alice', code);
    final state = AppState(services: services, store: secure);
    await state.initialise();
    await tester.pump(const Duration(seconds: 1));

    expect(state.conversations.hasPrivateChatsCode, isTrue);
    // A signed-in start keeps timers of its own; stopped inside the test,
    // because the pending-timer check runs before any tear-down.
    state.conversations.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  test('leaving the app hides them again, screen lock or not', () async {
    final state = await signedInWithPrivateBob();
    addTearDown(state.conversations.stop);
    expect(state.screenLockSet, isFalse);

    await state.conversations.showPrivateChats(code);
    expect(state.conversations.privateChatsShown, isTrue);

    state.lock();
    expect(state.conversations.privateChatsShown, isFalse);
  });

  group('on screen', () {
    testWidgets('the chat screen shows the lock, not the chat, and opens with the code',
        (tester) async {
      // Straight to the screen, as from a contact or a profile.
      final state = await signedInWithPrivateBob();
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ChatScreen(accountId: 'acc-bob', title: 'bob'), state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('geheim'), findsNothing);
      expect(find.text('This chat is private. Enter your code to see it.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('private-chat-unlock')));
      await tester.pumpAndSettle();
      await typeCode(tester, '1111');
      expect(find.text('geheim'), findsNothing);
      expect(find.text('Wrong code.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('private-chat-unlock')));
      await tester.pumpAndSettle();
      await typeCode(tester, code);
      expect(find.text('geheim'), findsOneWidget);

      state.conversations.hidePrivateChats();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('geheim'), findsNothing, reason: 'hiding left an open chat on screen');
    });

    testWidgets('the list has a lock only once there is a code, and it shows and hides',
        (tester) async {
      final state = await signedInWithPrivateBob();
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ChatsScreen(), state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('bob'), findsNothing);
      await tester.tap(find.byKey(const Key('private-show')));
      await tester.pumpAndSettle();
      await typeCode(tester, code);

      expect(find.text('bob'), findsOneWidget);
      expect(lockReading('Private chat'), findsOneWidget);

      await tester.tap(find.byKey(const Key('private-hide')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('bob'), findsNothing);
    });

    testWidgets('no code, no lock in the list', (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ChatsScreen(), state));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('private-show')), findsNothing);
    });

    testWidgets('making a chat private without a code sets one up first', (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      state.services.store
        ..upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'))
        ..append('acc-bob', Message(id: 'b1', body: 'hallo', sentAt: DateTime(2026, 9, 22), isMine: false));
      await tester.pumpWidget(wrap(const ChatsScreen(), state));
      await tester.pump(const Duration(seconds: 1));

      await tester.longPress(find.text('bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make private'));
      await tester.pumpAndSettle();

      // The code screen, with a note that says what this is not.
      expect(find.textContaining('They are not a second encryption'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('private-new')), code);
      await tester.enterText(find.byKey(const Key('private-repeat')), '2469');
      await tester.tap(find.byKey(const Key('private-save')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('The two codes differ.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('private-repeat')), code);
      await tester.tap(find.byKey(const Key('private-save')));
      await tester.pump(const Duration(seconds: 1));
      Navigator.of(tester.element(find.byKey(const Key('private-save')))).pop();
      await tester.pumpAndSettle();

      expect(state.conversations.isPrivate('acc-bob'), isTrue);
      expect(find.text('bob'), findsNothing);
      // After "Code saved.", which the code screen put up first.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Moved to private chats.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Saved is never offered as private', (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const ChatsScreen(), state));
      await tester.pump(const Duration(seconds: 1));

      await tester.longPress(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('Make private'), findsNothing);
    });

    testWidgets('a forgotten code: the private chats go, after asking', (tester) async {
      final state = await signedInWithPrivateBob();
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const PrivacyScreen(), state));
      await tester.pump(const Duration(seconds: 1));

      final row = find.text('Private chats');
      // Built below the fold already, so scrolling "until visible" stops at
      // once; this scrolls until it can be tapped.
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      // At the foot of the screen, under the fields.
      final forgot = find.byKey(const Key('private-forgot'));
      await tester.ensureVisible(forgot);
      await tester.pumpAndSettle();
      await tester.tap(forgot);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.services.store.conversationWith('acc-bob'), isNotNull);

      await tester.tap(forgot);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete private chats'));
      await tester.pump(const Duration(seconds: 1));
      expect(state.services.store.conversationWith('acc-bob'), isNull);
      expect(state.conversations.hasPrivateChatsCode, isFalse);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
