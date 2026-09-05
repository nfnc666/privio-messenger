import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/app.dart';
import 'package:privio/calls/call.dart';
import 'package:privio/calls/call_signal.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/disguise/launcher_disguise.dart';
import 'package:privio/core/passcode.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/screens/call_screen.dart';
import 'package:privio/screens/nav_shell.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/call_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

import 'support/fake_call_peer.dart';
import 'support/fake_voice.dart';

/// A signed-in app whose calls are driven by a fake connection.
///
/// [launcher] is for the tests that switch a disguise on: the real one talks to
/// a platform channel nothing answers under `flutter test`, and awaiting it
/// hangs the run rather than failing it.
Future<(AppState, CallService)> signedInApp({LauncherDisguise? launcher}) async {
  // Enough of a server for the screens under test: nothing to fetch, and a
  // recipient with no devices, so a signal seals to nobody and the send is a
  // no-op rather than a crash.
  final client = MockClient(
    (request) async => http.Response(
      jsonEncode(const {
        'contacts': <Object>[],
        'envelopes': <Object>[],
        'more': false,
        'remaining': 100,
        'accountId': 'acc-rosa',
        'devices': <Object>[],
        'deliveredTo': 0,
      }),
      200,
      headers: {'content-type': 'application/json'},
    ),
  );
  final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: client);
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  final store = InMemorySecureStore();
  await store.writeSession(token: 'session', username: 'nina', accountId: 'acc-nina');
  final calls = CallService(
    messaging: messaging,
    peers: (_) => FakeCallPeer(),
    lookUp: (accountId) async => CallParty(accountId: accountId, username: 'rosa'),
    store: store,
  );
  final services = PrivioServices(
    api: api,
    crypto: crypto,
    messaging: messaging,
    channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
    calls: calls,
    recorder: FakeVoiceRecorder(),
    player: FakeVoicePlayer(),
    backup: BackupService(api: api, store: store, messages: InMemoryMessageStore()),
    store: InMemoryMessageStore(),
    secureStore: store,
  );
  final state = AppState(
    services: services,
    store: store,
    launcher: launcher,
    supportsDisguise: launcher == null ? null : true,
  );
  await state.initialise();
  return (state, calls);
}

void main() {
  testWidgets('a call is rendered above the navigator, not inside it', (tester) async {
    final (state, calls) = await signedInApp();
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(PrivioApp(state: state));
    await tester.pump(const Duration(seconds: 1));
    expect(state.stage, AppStage.ready);

    await calls.handleSignal(
      'acc-rosa',
      const CallSignal(callId: 'call-1', action: CallAction.offer, sdp: 'sdp'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('rosa'), findsOneWidget);
    expect(find.text('Incoming call'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);

    // The invariant that makes a call cover the screen someone is on. The
    // overlay lived inside the `home` route first, which put it *under* every
    // pushed screen: starting a call from a chat rang the other phone while the
    // caller went on looking at their chat, with no way to hang up. Anything
    // the navigator can push is inside it; this must not be.
    expect(
      find.ancestor(of: find.byType(CallScreen), matching: find.byType(Navigator)),
      findsNothing,
      reason: 'inside a Navigator is underneath everything that Navigator pushes',
    );

    await calls.decline();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CallScreen), findsNothing, reason: 'and gives the screen back');
    expect(find.byType(NavShell), findsOneWidget);
  });

  testWidgets('a call does not show over the lock screen', (tester) async {
    final (state, calls) = await signedInApp();
    addTearDown(state.conversations.stop);
    await state.setScreenLock('1234', PasscodeKind.digits4);
    state.lock();

    await tester.pumpWidget(PrivioApp(state: state));
    await tester.pump(const Duration(seconds: 1));
    expect(state.stage, AppStage.locked);

    await calls.handleSignal(
      'acc-rosa',
      const CallSignal(callId: 'call-2', action: CallAction.offer, sdp: 'sdp'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Accept'),
      findsNothing,
      reason: 'the lock screen is the whole point of the lock screen',
    );
  });
}
