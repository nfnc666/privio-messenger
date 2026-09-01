import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/core/security_controller.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/screens/blocked_users_screen.dart';
import 'package:privio/screens/two_factor_screen.dart';
import 'package:privio/theme/privio_theme.dart';

import 'support/fake_voice.dart';

/// A server that behaves the way the real one does for the account settings
/// this screen drives: a secret is issued once, the factor only turns on after
/// a code has been checked, and turning it off needs the password.
class FakeAccountServer {
  FakeAccountServer({this.twoFactorEnabled = false});

  bool twoFactorEnabled;
  String? issuedSecret;
  String? duressCode;
  String password = 'correct-horse-battery';
  String lastSeen = 'everyone';
  List<Map<String, dynamic>> blocked = [];

  /// The code the authenticator would be showing right now.
  String get code => '123456';

  final List<String> calls = [];

  http.Response call(http.Request request) {
    final path = request.url.path;
    calls.add('${request.method} $path');
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;

    switch ((request.method, path)) {
      case ('GET', '/v1/accounts/me'):
        return _json({
          'username': 'nina',
          'twoFactorEnabled': twoFactorEnabled,
          'duressCodeSet': duressCode != null,
          'privacy': {'lastSeen': lastSeen, 'readReceipts': true, 'typingIndicators': true},
        });
      case ('PATCH', '/v1/accounts/me'):
        final privacy = body['privacy'] as Map<String, dynamic>? ?? const {};
        lastSeen = privacy['lastSeen'] as String? ?? lastSeen;
        return _json({'privacy': {'lastSeen': lastSeen}});
      case ('POST', '/v1/accounts/me/totp/setup'):
        if (twoFactorEnabled) {
          return _json({'error': 'totp_already_enabled', 'message': 'already on'}, 409);
        }
        issuedSecret = 'JBSWY3DPEHPK3PXP';
        return _json({
          'secret': issuedSecret,
          'otpauthUrl': 'otpauth://totp/Privio:nina?secret=$issuedSecret&issuer=Privio',
        });
      case ('POST', '/v1/accounts/me/totp/enable'):
        if (issuedSecret == null) {
          return _json({'error': 'totp_not_set_up', 'message': 'start again'}, 400);
        }
        if (body['code'] != code) {
          return _json({'error': 'invalid_totp', 'message': 'wrong'}, 400);
        }
        twoFactorEnabled = true;
        return _json({'twoFactorEnabled': true});
      case ('DELETE', '/v1/accounts/me/totp'):
        if (body['currentPassword'] != password) {
          return _json({'error': 'invalid_credentials', 'message': 'nope'}, 401);
        }
        twoFactorEnabled = false;
        issuedSecret = null;
        return _json({'twoFactorEnabled': false});
      case ('PUT', '/v1/accounts/me/duress-code'):
        if (body['currentPassword'] != password) {
          return _json({'error': 'invalid_credentials', 'message': 'nope'}, 401);
        }
        final code = body['duressCode'] as String?;
        if (code == password) {
          return _json(
            {'error': 'duress_code_matches_password', 'message': 'must differ'},
            400,
          );
        }
        duressCode = code;
        return _json({'duressCodeSet': code != null});
      case ('GET', '/v1/blocks'):
        return _json({'blocked': blocked});
      default:
        if (request.method == 'DELETE' && path.startsWith('/v1/blocks/')) {
          final id = path.split('/').last;
          blocked = [...blocked.where((entry) => entry['accountId'] != id)];
          return _json({'unblocked': true});
        }
        return _json(const {});
    }
  }

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

PrivioApiClient clientFor(FakeAccountServer server) => PrivioApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient((request) async => server.call(request)),
    )..useToken('token');

SecurityController controllerFor(FakeAccountServer server) =>
    SecurityController(clientFor(server));

/// An app wired to [server], the way the screens get theirs.
Future<AppState> appFor(FakeAccountServer server) async {
  final api = clientFor(server);
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  final state = AppState(
    services: PrivioServices(
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
    ),
    store: InMemorySecureStore(),
  );
  await state.initialise();
  return state;
}

void main() {
  group('two-factor', () {
    test('nothing is claimed before the server has answered', () {
      final security = controllerFor(FakeAccountServer());

      expect(
        security.twoFactorEnabled,
        isNull,
        reason: 'the screen used to say "On" over an account that had none',
      );
    });

    test('the state comes from the account, not from a constant', () async {
      final security = controllerFor(FakeAccountServer(twoFactorEnabled: true));
      await security.load();

      expect(security.twoFactorEnabled, isTrue);
    });

    test('a secret is issued, then the code turns it on', () async {
      final server = FakeAccountServer();
      final security = controllerFor(server);
      await security.load();

      expect(await security.beginTotpSetup(), isTrue);
      expect(security.setUpSecret, isNotEmpty);
      expect(security.setUpUrl, contains('otpauth://'));
      expect(
        security.twoFactorEnabled,
        isFalse,
        reason: 'issuing a secret must not switch the factor on by itself',
      );

      expect(await security.confirmTotp(server.code), isTrue);
      expect(security.twoFactorEnabled, isTrue);
    });

    test('the wrong code changes nothing, and says why', () async {
      final server = FakeAccountServer();
      final security = controllerFor(server);
      await security.load();
      await security.beginTotpSetup();

      expect(await security.confirmTotp('000000'), isFalse);
      expect(security.twoFactorEnabled, isFalse);
      expect(security.error, contains('not right'));
      expect(server.twoFactorEnabled, isFalse);
    });

    test('the secret is forgotten once the factor is on', () async {
      final server = FakeAccountServer();
      final security = controllerFor(server);
      await security.beginTotpSetup();
      await security.confirmTotp(server.code);

      expect(
        security.setUpSecret,
        isNull,
        reason: 'the secret is the factor; it has no business outliving the setup',
      );
    });

    test('turning it off needs the password', () async {
      final server = FakeAccountServer(twoFactorEnabled: true);
      final security = controllerFor(server);
      await security.load();

      expect(await security.disableTotp('not-the-password'), isFalse);
      expect(security.twoFactorEnabled, isTrue);
      expect(server.twoFactorEnabled, isTrue);

      expect(await security.disableTotp(server.password), isTrue);
      expect(security.twoFactorEnabled, isFalse);
    });
  });

  group('the duress code', () {
    test('is set with the password, and shows as set afterwards', () async {
      final server = FakeAccountServer();
      final security = controllerFor(server);
      await security.load();
      expect(security.duressCodeSet, isFalse);

      expect(
        await security.setDuressCode(currentPassword: server.password, duressCode: '911911'),
        isTrue,
      );
      expect(security.duressCodeSet, isTrue);
      expect(server.duressCode, '911911');
    });

    test('cannot be the password', () async {
      // Otherwise an ordinary sign-in would destroy the account.
      final server = FakeAccountServer();
      final security = controllerFor(server);

      expect(
        await security.setDuressCode(
          currentPassword: server.password,
          duressCode: server.password,
        ),
        isFalse,
      );
      expect(server.duressCode, isNull);
      expect(security.error, contains('different from your password'));
    });

    test('the wrong password changes nothing', () async {
      final server = FakeAccountServer();
      final security = controllerFor(server);

      expect(
        await security.setDuressCode(currentPassword: 'guess', duressCode: '911911'),
        isFalse,
      );
      expect(server.duressCode, isNull);
      expect(security.error, contains('not right'));
    });

    test('removing it needs the password too', () async {
      final server = FakeAccountServer()..duressCode = '911911';
      final security = controllerFor(server);
      await security.load();
      expect(security.duressCodeSet, isTrue);

      expect(
        await security.setDuressCode(currentPassword: 'guess', duressCode: null),
        isFalse,
      );
      expect(server.duressCode, '911911', reason: 'an unlocked phone is not authority');

      expect(
        await security.setDuressCode(currentPassword: server.password, duressCode: null),
        isTrue,
      );
      expect(server.duressCode, isNull);
      expect(security.duressCodeSet, isFalse);
    });
  });

  group('privacy and blocks', () {
    test('last seen is read from the account and written back', () async {
      final server = FakeAccountServer();
      final security = controllerFor(server);
      await security.load();
      expect(security.lastSeen, 'everyone');

      await security.setLastSeen('contacts');
      expect(server.lastSeen, 'contacts');
      expect(SecurityController.labelForLastSeen(security.lastSeen), 'My contacts');
    });

    test('a value the server would not take is put back', () async {
      final server = FakeAccountServer();
      final security = controllerFor(server);
      await security.setLastSeen('whoever');

      expect(security.lastSeen, 'everyone', reason: 'never offered, never sent');
      expect(server.calls, isNot(contains('PATCH /v1/accounts/me')));
    });

    test('the blocked list is the account\'s, and lifting one removes it', () async {
      final server = FakeAccountServer()
        ..blocked = [
          {'accountId': 'acc-1', 'username': 'mallory'},
          {'accountId': 'acc-2', 'username': 'trudy', 'displayName': 'T'},
        ];
      final security = controllerFor(server);
      await security.loadBlocks();

      expect(security.blocked, hasLength(2));
      expect(security.blocked!.first.label, 'mallory');
      expect(security.blocked!.last.label, 'T');

      await security.unblock('acc-1');
      expect(security.blocked!.single.accountId, 'acc-2');
      expect(server.blocked.single['accountId'], 'acc-2');
    });

    test('one screen open reads the account once, not twice', () async {
      // The whole account plugin used to share the login rate limit, and this
      // screen wants both halves of the same object. Two reads per open is two
      // of ten attempts spent on opening a settings screen.
      final server = FakeAccountServer();
      final security = controllerFor(server);
      await security.load();

      expect(
        server.calls.where((call) => call == 'GET /v1/accounts/me'),
        hasLength(1),
      );
      expect(security.privacy, isNotNull, reason: 'the messaging half is handed on');
    });

    test('the count is null until the list has been read', () {
      final security = controllerFor(FakeAccountServer());

      expect(security.blocked, isNull, reason: 'the row used to read 3, always');
    });
  });

  group('the screens', () {
    Widget wrap(Widget child, AppState state) => MaterialApp(
          theme: PrivioTheme.dark(),
          home: PrivioScope(notifier: state, child: child),
        );

    testWidgets('two-factor offers setup, then the code field', (tester) async {
      final server = FakeAccountServer();
      // Signing the app in is real async, which the fake clock inside a widget
      // test never runs. runAsync steps out for the setup only.
      final state = await tester.runAsync(() => appFor(server)) as AppState;

      await tester.pumpWidget(wrap(const TwoFactorScreen(), state));
      await tester.pump();
      await tester.pump();

      expect(find.text('Off'), findsOneWidget);
      await tester.tap(find.text('Set it up'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Scan this'), findsOneWidget);
      expect(find.text('Turn on'), findsOneWidget);
    });

    testWidgets('an empty block list says so instead of showing a number', (tester) async {
      final state = await tester.runAsync(() => appFor(FakeAccountServer())) as AppState;

      await tester.pumpWidget(wrap(const BlockedUsersScreen(), state));
      await tester.pump();
      await tester.pump();

      expect(find.text('Nobody is blocked'), findsOneWidget);
    });
  });
}
