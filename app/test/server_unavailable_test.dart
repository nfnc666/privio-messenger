import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/failure.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/l10n/failure_text.dart';
import 'package:privio/screens/group_info_screen.dart';

import 'widget_test.dart' show quietServices, wrap;

/// A server that is down is not the reader's connection.
///
/// Found on a phone: the hosted database had expired, the server could not
/// start, and the hosting platform answered every request with its own error
/// page. The app said "Could not reach Privio. Check your connection." on a
/// phone whose connection was fine, and the group screen said it "could not
/// read who is in this group" above "0 members".
const _gatewayPage = '<!DOCTYPE html><html><body><h1>502 Bad Gateway</h1></body></html>';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

PrivioApiClient _api(http.Response Function(http.Request) answer) =>
    PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: MockClient((r) async => answer(r)))
      ..useToken('token');

void main() {
  group('what came back', () {
    test("a host's error page is the server being down", () async {
      final api = _api((_) => http.Response(_gatewayPage, 502));
      await expectLater(api.me(), throwsA(isA<ServerUnavailableException>()));
    });

    test('a login page in the way is still the connection', () async {
      // A captive portal answers with its own page and a 200: that is the
      // network between the phone and Privio, and it is the reader's to fix.
      final api = _api((_) => http.Response('<html>Sign in to the Wi-Fi</html>', 200));
      await expectLater(api.me(), throwsA(isA<FormatException>()));
    });

    test("the server's own refusal stays the server's", () async {
      final api = _api((_) => _json({'error': 'unavailable', 'message': 'busy'}, 503));
      await expectLater(
        api.me(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
    });
  });

  group('how it is said', () {
    test('down is not unreachable', () {
      expect(Failure.of(const ServerUnavailableException(502), FailureKind.unreachable).kind,
          FailureKind.serverUnavailable);
      expect(Failure.reaching(const ServerUnavailableException(503), FailureKind.unreachable).kind,
          FailureKind.serverUnavailable);
      expect(Failure.reaching(const SocketException('no route'), FailureKind.unreachable).kind,
          FailureKind.unreachable);
    });

    for (final locale in AppText.supportedLocales) {
      test('${locale.languageCode}: its own sentence', () async {
        final text = await AppText.delegate.load(locale);
        final down = const Failure(FailureKind.serverUnavailable).words(text);
        expect(down, isNotEmpty);
        expect(down, isNot(text.failureUnreachableCheckConnection));
        expect(text.groupInfoMembersNotLoaded, isNotEmpty);
      });
    }
  });

  test('the channel list says the server is down, not to check the connection', () async {
    final services = await quietServices(
      client: MockClient((request) async => http.Response(_gatewayPage, 502)),
    );
    final state = AppState(services: services, store: InMemorySecureStore());
    await state.initialise();
    addTearDown(state.conversations.stop);

    await state.channels.refresh();
    expect(state.channels.failure?.kind, FailureKind.serverUnavailable);
  });

  testWidgets('a group whose members did not load says so, says why, and tries again',
      (tester) async {
    var down = true;
    final services = await quietServices(
      client: MockClient((request) async {
        if (request.url.path == '/v1/groups/g1') {
          if (down) return http.Response(_gatewayPage, 502);
          return _json({
            'id': 'g1',
            'members': [
              {'id': 'acc-ann', 'username': 'ann', 'role': 'admin'},
              {'id': 'acc-ben', 'username': 'ben', 'role': 'member'},
            ],
          });
        }
        return _json(const {'contacts': [], 'envelopes': [], 'more': false});
      }),
    );
    final state = AppState(services: services, store: InMemorySecureStore());
    await tester.runAsync(state.initialise);
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(wrap(const GroupInfoScreen(groupId: 'g1'), state));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('The member list could not be loaded.'), findsOneWidget);
    expect(
      find.text('The Privio server is having a problem right now. It is not your connection — please try again later.'),
      findsOneWidget,
    );
    expect(find.textContaining('0 '), findsNothing, reason: 'no count of a list nobody has');

    down = false;
    await tester.tap(find.text('Try again'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('The member list could not be loaded.'), findsNothing);
    expect(find.text('ann'), findsOneWidget);
    expect(find.text('ben'), findsOneWidget);
  });
}
