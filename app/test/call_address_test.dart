import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/calls/call.dart';
import 'package:privio/calls/call_signal.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/call_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

import 'support/fake_call_peer.dart';
import 'support/fake_voice.dart';
import 'widget_test.dart' show wrap;

/// A call goes to the username, whatever the chat is titled.
///
/// Found by calling somebody in a browser: the chat handed its title — the
/// display name, "Bob Test" — to the call as the name to send to. The server
/// refused the key lookup for "Bob Test", and the call never rang. Every
/// contact with a display name of their own was unreachable by phone.
void main() {
  testWidgets('calling from a chat asks for the username, and shows the display name',
      (tester) async {
    final asked = <String>[];
    final client = MockClient((request) async {
      asked.add(Uri.decodeComponent(request.url.path));
      return http.Response(
        jsonEncode(const {
          'contacts': <Object>[],
          'envelopes': <Object>[],
          'more': false,
          'remaining': 100,
          'devices': <Object>[],
          'deliveredTo': 0,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: client);
    final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
    final messaging = MessagingService(api: api, crypto: crypto);
    final secure = InMemorySecureStore();
    final messages = InMemoryMessageStore()
      ..upsertUser(
        const KnownUser(accountId: 'acc-bob', username: 'bob', displayName: 'Bob Test'),
      );
    final calls = CallService(
      messaging: messaging,
      peers: (_) => FakeCallPeer(),
      lookUp: (accountId) async => null,
      store: secure,
    );
    final state = AppState(
      services: PrivioServices(
        api: api,
        crypto: crypto,
        messaging: messaging,
        channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
        calls: calls,
        recorder: FakeVoiceRecorder(),
        player: FakeVoicePlayer(),
        backup: BackupService(api: api, store: secure, messages: InMemoryMessageStore()),
        store: messages,
        secureStore: secure,
      ),
      store: secure,
    );
    await tester.runAsync(state.initialise);
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(wrap(const ChatScreen(accountId: 'acc-bob', title: 'Bob Test'), state));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Voice call'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    expect(asked, contains('/v1/keys/bob'), reason: 'the call is addressed to the username');
    expect(asked.where((path) => path.contains('Bob Test')), isEmpty);
    expect(calls.current?.party.username, 'bob');
    expect(calls.current?.party.label, 'Bob Test', reason: 'and shown by the name people see');

    // This server's answer for Bob's keys is not keys, so the offer cannot be
    // sealed. That has to end the call and say so — not leave it dialling with
    // the microphone open while the error goes nowhere.
    expect(calls.current?.state, CallState.ended);
    expect(calls.current?.ending, CallEnding.failed);
    expect(calls.failure, isNotNull);
  });

  test('a party without a display name is shown by its username', () {
    const party = CallParty(accountId: 'a', username: 'bob');
    expect(party.label, 'bob');
    expect(
      party,
      const CallParty(accountId: 'a', username: 'bob', displayName: 'Bob'),
      reason: 'the display name is how a party is shown, not who it is',
    );
  });
}
