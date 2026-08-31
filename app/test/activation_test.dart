import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/biometric_gate.dart';
import 'package:privio/core/edition.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/screens/activation_screen.dart';
import 'package:privio/screens/license_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/license_key_field.dart';

import 'support/fake_voice.dart';

/// A server that sells access: it answers the license endpoints, and everything
/// else with the empty collections a fresh account would get.
class FakeLicenseServer {
  FakeLicenseServer({required this.enforced, this.licensed = false});

  final bool enforced;
  bool licensed;

  /// Keys this server would accept. Anything else comes back as unknown.
  final Set<String> keys = {'PRIVIO-2345-6789-ABCD-EFGH'};

  int statusCalls = 0;
  int redeemCalls = 0;

  http.Response call(http.Request request) {
    final path = request.url.path;
    if (path == '/v1/accounts') {
      return _json({
        'token': 'session-token',
        'username': 'nina',
        'accountId': 'account-nina',
      });
    }
    if (path == '/v1/licenses/me') {
      statusCalls++;
      return _json({'licensed': licensed, 'required': enforced});
    }
    if (path == '/v1/licenses/redeem') {
      redeemCalls++;
      final key = (jsonDecode(request.body) as Map<String, dynamic>)['licenseKey'] as String;
      if (!keys.contains(key)) {
        return _json({'error': 'license_not_found', 'message': 'No license matches'}, 404);
      }
      licensed = true;
      return _json({'licensed': true, 'required': enforced, 'source': 'key'});
    }
    // Everything the app touches behind a sign-in, answered as an account with
    // nothing in it yet: no contacts, no queue, and a full prekey pool.
    return _json(const {'contacts': [], 'envelopes': [], 'more': false, 'remaining': 100});
  }

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

Future<PrivioServices> servicesFor(FakeLicenseServer server) async {
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient((request) async => server.call(request)),
  );
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  return PrivioServices(
    api: api,
    crypto: crypto,
    messaging: messaging,
    channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
    recorder: FakeVoiceRecorder(),
    player: FakeVoicePlayer(),
    backup: BackupService(
      api: api,
      store: InMemorySecureStore(),
      messages: InMemoryMessageStore(),
    ),
    store: InMemoryMessageStore(),
    secureStore: InMemorySecureStore(),
  );
}

/// Lets the work a sign-in kicks off finish, then stops the delivery loop.
///
/// The license question runs unawaited behind the sign-in, exactly as it does
/// on a device, so the stage only settles once the queue has drained. The stop
/// is not cosmetic: the controller opens a real socket to the fake host and
/// reconnects forever, which hangs the suite rather than failing it.
Future<void> settle(AppState state) async {
  await pumpEventQueue();
  state.conversations.stop();
}

/// Signs up and lets the license answer arrive.
Future<AppState> signUpOn(
  FakeLicenseServer server, {
  SecureStore? store,
  String edition = 'libre',
}) async {
  final state = AppState(
    services: await servicesFor(server),
    store: store ?? InMemorySecureStore(),
    biometrics: const NoBiometrics(),
    edition: PrivioEdition.parse(edition),
  );
  await state.initialise();
  await state.register(username: 'nina', password: 'correct-horse-battery');
  await settle(state);
  return state;
}

void main() {
  test('a server that sells access asks a new account for a key', () async {
    final state = await signUpOn(FakeLicenseServer(enforced: true));

    expect(state.stage, AppStage.activation);
  });

  test('a self-hosted server never asks', () async {
    final server = FakeLicenseServer(enforced: false);
    final state = await signUpOn(server);

    expect(state.stage, AppStage.ready);
    expect(server.statusCalls, 1, reason: 'it is still asked, and the answer is no');
  });

  test('the APK from the website asks, like the Libre build', () async {
    final state = await signUpOn(FakeLicenseServer(enforced: true), edition: 'direct');

    expect(state.stage, AppStage.activation);
  });

  test('a store build is never asked for a key', () async {
    // Paid for at the moment it was installed. A key field would be asking for
    // something this build has no way to have.
    for (final edition in ['play', 'appstore']) {
      final server = FakeLicenseServer(enforced: true);
      final state = await signUpOn(server, edition: edition);

      expect(state.stage, AppStage.ready, reason: '$edition should go straight in');
      expect(
        server.statusCalls,
        1,
        reason: 'the license is still read — Settings has something to say',
      );
    }
  });

  test('an account that already holds a license is not asked', () async {
    final state = await signUpOn(FakeLicenseServer(enforced: true, licensed: true));

    expect(state.stage, AppStage.ready);
  });

  test('activating moves on to the app', () async {
    final state = await signUpOn(FakeLicenseServer(enforced: true));

    final ok = await state.license.redeem('privio 2345 6789 abcd efgh');
    await state.leaveActivation(asked: false);

    expect(ok, isTrue);
    expect(state.stage, AppStage.ready);
  });

  test('a key that is refused leaves the step where it is', () async {
    final state = await signUpOn(FakeLicenseServer(enforced: true));

    final ok = await state.license.redeem('PRIVIO-0000-0000-0000-0000');

    expect(ok, isFalse);
    expect(state.stage, AppStage.activation);
    expect(state.license.error, contains('No license matches'));
  });

  test('"Not now" is remembered, so it is asked once and not every launch', () async {
    final store = InMemorySecureStore();
    final first = await signUpOn(FakeLicenseServer(enforced: true), store: store);
    await first.leaveActivation();
    expect(first.stage, AppStage.ready);

    // The same device, opened again with the session already on it.
    final server = FakeLicenseServer(enforced: true);
    final second = AppState(
      services: await servicesFor(server),
      store: store,
      biometrics: const NoBiometrics(),
    );
    await second.initialise();
    await settle(second);

    expect(second.stage, AppStage.ready);
    expect(server.statusCalls, 1, reason: 'still asked; only the screen is skipped');
  });

  test('a second account on the same device is asked in its turn', () async {
    final store = InMemorySecureStore();
    final first = await signUpOn(FakeLicenseServer(enforced: true), store: store);
    await first.leaveActivation();

    // Not a sign-out, which wipes the store: this is the case the flag has to
    // survive — a different account id against the same remembered answer.
    await store.writeSession(
      token: 'session-token',
      username: 'omar',
      accountId: 'account-omar',
    );
    final second = AppState(
      services: await servicesFor(FakeLicenseServer(enforced: true)),
      store: store,
      biometrics: const NoBiometrics(),
    );
    await second.initialise();
    await settle(second);

    expect(second.stage, AppStage.activation);
  });

  group('the key field', () {
    /// What the field would hold after [typed] was entered one character at a
    /// time, which is the only way the formatter is ever used.
    String afterTyping(String typed) {
      const formatter = LicenseKeyFormatter();
      var value = TextEditingValue.empty;
      for (final character in typed.split('')) {
        final next = value.text + character;
        value = formatter.formatEditUpdate(
          value,
          TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length)),
        );
      }
      return value.text;
    }

    test('a key pasted in any shape lands in the printed one', () {
      expect(afterTyping('privio 2345 6789 abcd efgh'), 'PRIVIO-2345-6789-ABCD-EFGH');
      expect(afterTyping('2345-6789-abcd-efgh'), 'PRIVIO-2345-6789-ABCD-EFGH');
    });

    test('typing the prefix does not leave PR1V10 in front of the key', () {
      // The prefix contains an I and an O of its own. Folding them while they
      // are still being typed used to push "PR1V1" into the body, where every
      // later keystroke kept it.
      expect(afterTyping('PRIVIO'), 'PRIVIO-');
      expect(afterTyping('PRIVIO2345'), 'PRIVIO-2345');
      expect(afterTyping('privio${'0' * 16}'), 'PRIVIO-0000-0000-0000-0000');
    });

    test('a body that starts like the prefix survives it', () {
      // P and R are ordinary key characters; I is not, so the ambiguity only
      // lasts until the character that settles it.
      expect(afterTyping('PR2345'), 'PRIVIO-PR23-45');
    });

    test('backspace can empty the field again', () {
      const formatter = LicenseKeyFormatter();
      var value = const TextEditingValue(
        text: 'PRIVIO-2345',
        selection: TextSelection.collapsed(offset: 11),
      );
      for (var i = 0; i < 20 && value.text.isNotEmpty; i++) {
        final shorter = value.text.substring(0, value.text.length - 1);
        value = formatter.formatEditUpdate(
          value,
          TextEditingValue(
            text: shorter,
            selection: TextSelection.collapsed(offset: shorter.length),
          ),
        );
      }
      expect(
        value.text,
        isEmpty,
        reason: 'a field that puts the prefix back on every delete can never be corrected',
      );
    });

    test('the field stops at the length of a key', () {
      expect(
        afterTyping('23456789ABCDEFGHJKMNPQRS'),
        'PRIVIO-2345-6789-ABCD-EFGH',
        reason: 'a 16-symbol body, however much was typed',
      );
    });
  });

  testWidgets('the screen offers a key field and a way past it', (tester) async {
    // Signing in is real async — HTTP, storage, the crypto boot — and the fake
    // clock a widget test runs under never lets it finish. runAsync steps out.
    final state = await tester.runAsync(
      () => signUpOn(FakeLicenseServer(enforced: true)),
    ) as AppState;

    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        home: PrivioScope(notifier: state, child: const ActivationScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Activate Privio'), findsOneWidget);
    expect(find.text('Activate'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'privio 2345 6789 abcd efgh');
    await tester.pump();
    expect(
      find.text('PRIVIO-2345-6789-ABCD-EFGH'),
      findsOneWidget,
      reason: 'the field formats what was typed into the shape a key is printed in',
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Activate'));
      await pumpEventQueue();
    });
    await tester.pump();

    expect(state.stage, AppStage.ready);
  });

  testWidgets('a store build is told to settle it with the store, not with a key',
      (tester) async {
    final state = await tester.runAsync(
      () => signUpOn(FakeLicenseServer(enforced: true), edition: 'appstore'),
    ) as AppState;

    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        home: PrivioScope(notifier: state, child: const LicenseScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Handled by the store'), findsOneWidget);
    expect(find.byType(LicenseKeyField), findsNothing);
  });

  testWidgets('"Not now" leaves for the app without a key', (tester) async {
    final state = await tester.runAsync(
      () => signUpOn(FakeLicenseServer(enforced: true)),
    ) as AppState;

    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        home: PrivioScope(notifier: state, child: const ActivationScreen()),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Not now'));
      await pumpEventQueue();
    });
    await tester.pump();

    expect(state.stage, AppStage.ready);
    expect(state.license.needsActivation, isTrue, reason: 'skipped, not activated');
  });
}
