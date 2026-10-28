import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/crypto/safety_number.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/contacts_screen.dart';
import 'package:privio/screens/safety_number_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/widgets/chat_list_row.dart';

import 'crypto_test.dart' show FakeKeyServer, TestDevice;
import 'deletion_test.dart' show ScriptedMessaging, buildServices, storeWith, text;
import 'safety_number_test.dart' show introduce;
import 'saved_test.dart' show signedInAs;
import 'support/fake_voice.dart';
import 'widget_test.dart' show quietServices, wrap;

/// The mark beside a name in the chat and contact lists.
///
/// What these pin: the lists say what the safety number screen says, a
/// changed number is never shown as verified, and nothing is shown for a
/// number nobody compared.

/// Finds the mark by the words a screen reader says for it.
Finder markReading(String words) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == words,
    );

/// Alice's and Bob's devices, each having written once, so each has the
/// other's key pinned and a number to compare.
Future<(FakeKeyServer, TestDevice, TestDevice)> aliceAndBob() async {
  final server = FakeKeyServer();
  final alice = TestDevice('account-alice', 'device-alice-1', 1);
  final bob = TestDevice('account-bob', 'device-bob-1', 1);
  await alice.boot(server);
  await bob.boot(server);
  await introduce(server, alice, bob);
  await introduce(server, bob, alice);
  return (server, alice, bob);
}

Future<SafetyNumbers> numbersOf(PrivioCrypto crypto) => crypto.safetyNumbers(
      localAccountId: 'account-alice',
      remoteAccountId: 'account-bob',
    );

void main() {
  group('the keystore answer', () {
    test('says what the safety number screen says, in every state', () async {
      final (server, alice, bob) = await aliceAndBob();
      Future<void> agree(VerificationState expected) async {
        expect(await alice.crypto.verificationState('account-bob'), expected);
        expect((await numbersOf(alice.crypto)).state, expected);
      }

      await agree(VerificationState.unverified);

      await alice.crypto.markVerified('account-bob', await numbersOf(alice.crypto));
      await agree(VerificationState.verified);

      // A second device joining Bob's account is what a server adding one of
      // its own would look like.
      final laptop = TestDevice(bob.accountId, 'device-bob-2', 2);
      await laptop.boot(server);
      await introduce(server, alice, laptop);
      await agree(VerificationState.changed);

      await alice.crypto.clearVerified('account-bob');
      await agree(VerificationState.unverified);
    });

    test('somebody never written to is unverified', () async {
      final (_, alice, _) = await aliceAndBob();
      expect(await alice.crypto.verificationState('account-nobody'), VerificationState.unverified);
    });
  });

  group('the controller', () {
    Future<(ConversationController, ScriptedMessaging, TestDevice, TestDevice, FakeKeyServer)>
        controllerFor() async {
      final (server, alice, bob) = await aliceAndBob();
      final (services, messaging) = await buildServices(
        storeWith([text('t1')]),
        crypto: alice.crypto,
      );
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      return (controller, messaging, alice, bob, server);
    }

    test('nothing is marked before anything was compared', () async {
      final (controller, _, _, _, _) = await controllerFor();
      await controller.refreshTrust();
      expect(controller.trustMarkOf('account-bob'), TrustMark.none);
      expect(controller.chats.single.trust, TrustMark.none);
    });

    test('verifying marks the row, and withdrawing it takes the mark away', () async {
      final (controller, _, alice, _, _) = await controllerFor();
      var redraws = 0;
      controller.addListener(() => redraws += 1);

      final numbers = await numbersOf(alice.crypto);
      await controller.setVerified('account-bob', numbers, verified: true);
      expect(controller.trustMarkOf('account-bob'), TrustMark.verified);
      expect(controller.chats.single.trust, TrustMark.verified);
      expect(redraws, greaterThan(0), reason: 'the list was not told');

      await controller.setVerified('account-bob', numbers, verified: false);
      expect(controller.chats.single.trust, TrustMark.none);
    });

    test('a device joining a verified account turns the mark to changed', () async {
      final (controller, _, alice, bob, server) = await controllerFor();
      await controller.setVerified('account-bob', await numbersOf(alice.crypto), verified: true);

      final laptop = TestDevice(bob.accountId, 'device-bob-2', 2);
      await laptop.boot(server);
      await introduce(server, alice, laptop);

      await controller.refreshTrust();
      expect(controller.chats.single.trust, TrustMark.changed);
    });

    test('a number that changed under a message stays changed after it is seen', () async {
      // The alert says so until the new number has been looked at. After that
      // it is the keystore's answer that has to say it, and that answer is
      // only as fresh as the last time the controller asked.
      final (controller, messaging, alice, bob, server) = await controllerFor();
      await controller.setVerified('account-bob', await numbersOf(alice.crypto), verified: true);
      expect(controller.trustMarkOf('account-bob'), TrustMark.verified);

      // Bob reinstalls and writes. Receiving is not refused; it is reported.
      final reinstalled = TestDevice(bob.accountId, bob.deviceId, bob.deviceIndex);
      await reinstalled.boot(server);
      await introduce(server, reinstalled, alice);
      messaging.inbox.add(
        IncomingMessage(
          envelopeId: 9,
          senderAccountId: 'account-bob',
          payload: const MessagePayload.text('neu installiert', clientId: 't2'),
          receivedAt: DateTime(2026, 1, 1, 13),
        ),
      );
      await controller.drain();
      expect(controller.trustMarkOf('account-bob'), TrustMark.changed);

      await controller.acknowledgeKeyChange('account-bob');
      expect(controller.trustMarkOf('account-bob'), TrustMark.changed,
          reason: 'looking at the new number is not verifying it',
      );
    });

    test('an unanswered key change is marked where nothing was verified', () async {
      final (controller, _, alice, _, _) = await controllerFor();
      await alice.crypto.raiseKeyChangeAlert('account-bob');
      await controller.loadKeyChangeAlerts();
      expect(controller.chats.single.trust, TrustMark.changed);

      await controller.acknowledgeKeyChange('account-bob');
      expect(controller.chats.single.trust, TrustMark.none);
    });

    test('accepting a changed key reads again what the keystore says', () async {
      final (controller, _, alice, _, _) = await controllerFor();
      await controller.setVerified('account-bob', await numbersOf(alice.crypto), verified: true);

      // What accepting does underneath: the key is unpinned and the
      // verification it broke is dropped.
      await alice.crypto.acceptIdentityChange('account-bob', 1);
      await controller.acceptIdentityChange('account-bob');
      expect(controller.trustMarkOf('account-bob'), TrustMark.none);
    });
  });

  group('the chat list row', () {
    ChatSummary row(TrustMark trust) => ChatSummary(
          id: 'acc-bob',
          title: 'bob',
          preview: const ChatPreview(ChatPreviewKind.body, text: 'hallo'),
          timestamp: ChatStamp.none,
          trust: trust,
        );

    Future<void> draw(WidgetTester tester, ChatSummary chat) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(Scaffold(body: ChatListRow(chat: chat)), state));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('a verified person wears the mark', (tester) async {
      await draw(tester, row(TrustMark.verified));
      expect(markReading('Verified'), findsOneWidget);
      expect(markReading('Safety number changed'), findsNothing);
    });

    testWidgets('a changed number wears the warning', (tester) async {
      await draw(tester, row(TrustMark.changed));
      expect(markReading('Safety number changed'), findsOneWidget);
      expect(markReading('Verified'), findsNothing);
    });

    testWidgets('a number nobody compared wears nothing', (tester) async {
      await draw(tester, row(TrustMark.none));
      expect(markReading('Verified'), findsNothing);
      expect(markReading('Safety number changed'), findsNothing);
    });
  });

  testWidgets('the contact list shows the same mark', (tester) async {
    final services = await quietServices(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'contacts': [
              {'id': 'acc-bob', 'username': 'bob', 'displayName': 'Bob'},
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
    addTearDown(state.conversations.stop);
    await services.crypto.raiseKeyChangeAlert('acc-bob');
    await state.conversations.loadKeyChangeAlerts();

    await tester.pumpWidget(wrap(const ContactsScreen(), state));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Bob'), findsOneWidget);
    expect(markReading('Safety number changed'), findsOneWidget);
  });

  group('signed in', () {
    /// A signed-in start on Alice's device, with whatever the server says
    /// about contacts. [contacts] null means the server does not answer.
    Future<AppState> signedIn(
      PrivioCrypto crypto, {
      List<Map<String, Object?>>? contacts = const [],
      InMemoryMessageStore? messages,
    }) async {
      final client = MockClient(
        (request) async => contacts == null
            ? http.Response(
                jsonEncode({'error': 'unavailable', 'message': 'down'}),
                503,
                headers: {'content-type': 'application/json'},
              )
            : http.Response(
                // Enough of every answer a signed-in start asks for; the prekey
                // count keeps it from topping up keys in the middle of a test.
                jsonEncode({'contacts': contacts, 'envelopes': <Object>[], 'more': false, 'remaining': 100}),
                200,
                headers: {'content-type': 'application/json'},
              ),
      );
      final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: client);
      final messaging = MessagingService(api: api, crypto: crypto);
      final store = InMemorySecureStore();
      await store.writeSession(token: 'session', username: 'alice', accountId: 'account-alice');
      final services = PrivioServices(
        api: api,
        crypto: crypto,
        messaging: messaging,
        channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
        recorder: FakeVoiceRecorder(),
        player: FakeVoicePlayer(),
        backup: BackupService(api: api, store: store, messages: InMemoryMessageStore()),
        store: messages ?? InMemoryMessageStore(),
        secureStore: store,
      );
      final state = AppState(services: services, store: store);
      await state.initialise();
      return state;
    }

    /// A signed-in start keeps timers of its own. Stopped inside the test,
    /// because the pending-timer check runs before any tear-down.
    Future<void> finish(WidgetTester tester, AppState state) async {
      state.conversations.stop();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('a start reads the marks from the keystore, server or not', (tester) async {
      final (_, alice, _) = await aliceAndBob();
      await alice.crypto.markVerified('account-bob', await numbersOf(alice.crypto));

      final state = await signedIn(alice.crypto, contacts: null, messages: storeWith([text('t1')]));
      await tester.pump(const Duration(seconds: 1));

      expect(state.conversations.trustMarkOf('account-bob'), TrustMark.verified);
      await finish(tester, state);
    });

    testWidgets('somebody the contact list brings in is marked too', (tester) async {
      final (_, alice, _) = await aliceAndBob();
      await alice.crypto.markVerified('account-bob', await numbersOf(alice.crypto));

      final state = await signedIn(
        alice.crypto,
        contacts: [
          {'id': 'account-bob', 'username': 'bob', 'displayName': 'Bob'},
        ],
      );
      await tester.pump(const Duration(seconds: 1));

      expect(state.conversations.trustMarkOf('account-bob'), TrustMark.verified);
      await finish(tester, state);
    });

    testWidgets('verifying on the safety number screen reaches the lists', (tester) async {
      final (_, alice, _) = await aliceAndBob();
      final state = await signedIn(alice.crypto);

      await tester.pumpWidget(
        wrap(const SafetyNumberScreen(accountId: 'account-bob', title: 'bob'), state),
      );
      await tester.pump(const Duration(seconds: 1));
      // The button is at the foot of a list, under the numbers and the QR code.
      await tester.scrollUntilVisible(
        find.byKey(const Key('safety-verify')),
        300,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      );
      await tester.tap(find.byKey(const Key('safety-verify')));
      await tester.pump(const Duration(seconds: 1));

      expect(state.conversations.trustMarkOf('account-bob'), TrustMark.verified);
      await finish(tester, state);
    });
  });
}
