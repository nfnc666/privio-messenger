import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/contacts/address_book.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/phone_number.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/phone_contacts_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';

import 'support/fake_voice.dart';

/// Matching the address book against Privio accounts.
///
/// The claim these tests exist to hold is the one in `docs/phone-contacts.md`:
/// **the address book never leaves the device.** Numbers are blinded here and
/// only the blinds are sent — so the central test is not "does a match work"
/// but "is a plaintext number anywhere in what was sent", and it asserts on the
/// raw request body rather than on anything the client claims about it.
class _Server {
  /// Every request body this server was sent, verbatim.
  final List<String> bodies = [];

  /// Blinded numbers that should answer with a match, by blind.
  final Map<String, Map<String, dynamic>> matches = {};

  /// What `/v1/phone` reports about the account.
  Map<String, dynamic> link = {
    'linked': true,
    'hint': '+49 … 87',
    'discoverable': true,
    'contactSync': true,
    'smsAvailable': true,
    'discoveryAvailable': true,
  };

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'POST' &&
            (path == '/v1/accounts' || path == '/v1/sessions')) {
          final username =
              (jsonDecode(request.body) as Map<String, dynamic>)['username'] as String;
          return _json({
            'token': 'token-$username',
            'accountId': 'acc-$username',
            'username': username,
            'deviceId': 'device-1',
          }, path == '/v1/accounts' ? 201 : 200);
        }

        if (path == '/v1/phone') {
          if (request.method == 'PATCH') {
            bodies.add(request.body);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            link = {...link, ...body};
          }
          return _json(link);
        }

        if (path == '/v1/contacts/discover') {
          bodies.add(request.body);
          final blinded =
              ((jsonDecode(request.body) as Map<String, dynamic>)['blinded'] as List<dynamic>)
                  .cast<String>();
          return _json({
            'matches': [
              for (final blind in blinded)
                if (matches.containsKey(blind)) {'blinded': blind, ...matches[blind]!},
            ],
          });
        }

        if (path == '/v1/keys/count') return _json(const {'remaining': 50});
        return _json(const {'contacts': [], 'envelopes': [], 'more': false, 'channels': []});
      });

  static http.Response _json(Object body, [int code = 200]) =>
      http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
}

/// An address book that records whether it was ever asked.
///
/// "Was it asked" is the assertion for the consent rule: an app that reads the
/// address book before being told it may is doing the one thing this feature
/// must not do, and only the source itself can prove it was left alone.
class _FakeAddressBook implements AddressBook {
  _FakeAddressBook(this._answer);

  final AddressBookRead _answer;
  int reads = 0;

  @override
  Future<AddressBookRead> read() async {
    reads++;
    return _answer;
  }
}

Future<PrivioServices> _services(_Server server, AddressBook book) async {
  final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: server.client());
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  return PrivioServices(
    api: api,
    crypto: crypto,
    messaging: messaging,
    channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
    recorder: FakeVoiceRecorder(),
    player: FakeVoicePlayer(),
    addressBook: book,
    backup: BackupService(
      api: api,
      store: InMemorySecureStore(),
      messages: InMemoryMessageStore(),
    ),
    store: InMemoryMessageStore(),
    secureStore: InMemorySecureStore(),
  );
}

Future<AppState> _signedIn(_Server server, AddressBook book) async {
  final state = AppState(services: await _services(server, book), store: InMemorySecureStore());
  await state.initialise();
  await state.signIn(username: 'alice', password: 'correct-horse');
  return state;
}

Widget _screen(AppState state) => PrivioScope(
      notifier: state,
      child: MaterialApp(
        theme: PrivioTheme.dark(),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: const PhoneContactsScreen(),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pumpAndSettle();
}

/// Brings something below the fold into view.
///
/// The results are appended under a screenful of switches and paragraphs, and a
/// ListView does not build what is off screen — so a finder that skips offstage
/// widgets reports "not there" for something that is simply further down.
Future<void> _reveal(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );

void main() {
  group('the consent comes first', () {
    testWidgets('with the switch off there is no button, and nothing is read',
        (tester) async {
      final server = _Server()..link = {..._Server().link, 'contactSync': false};
      final book = _FakeAddressBook(const AddressBookNumbers(['+49 151 23456789']));
      final state = await tester.runAsync(() => _signedIn(server, book)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(_screen(state));
      await _settle(tester);

      expect(find.text('Match my contacts now'), findsNothing);
      expect(book.reads, 0, reason: 'the address book was touched without consent');
    });

    testWidgets('turning the switch on still reads nothing by itself',
        (tester) async {
      // The switch is consent, not an action. Reading on the flip would mean
      // the address book was opened by a toggle rather than by a decision to
      // match, and on iOS it would spend the one permission prompt.
      final server = _Server()..link = {..._Server().link, 'contactSync': false};
      final book = _FakeAddressBook(const AddressBookNumbers(['+49 151 23456789']));
      final state = await tester.runAsync(() => _signedIn(server, book)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(_screen(state));
      await _settle(tester);

      await tester.tap(find.byType(Switch).last);
      await _settle(tester);

      expect(find.text('Match my contacts now'), findsOneWidget);
      expect(book.reads, 0, reason: 'a toggle must not open the address book');
    });
  });

  group('what is sent', () {
    testWidgets('only blinded values — never a phone number', (tester) async {
      // The claim the whole feature rests on, asserted against the raw body.
      const numbers = ['+49 151 23456789', '+1 (555) 010-9999', 'Pizza Napoli'];
      final server = _Server();
      final book = _FakeAddressBook(const AddressBookNumbers(numbers));
      final state = await tester.runAsync(() => _signedIn(server, book)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(_screen(state));
      await _settle(tester);
      await tester.tap(find.text('Match my contacts now'));
      await _settle(tester);

      final sent = server.bodies.join('\n');
      expect(sent, contains('blinded'));
      for (final number in numbers) {
        expect(sent, isNot(contains(number)), reason: '$number went to the server');
      }
      // Not only as typed: the normalised form must not be in there either.
      expect(sent, isNot(contains('+4915123456789')));
      expect(sent, isNot(contains('15123456789')));
      // What *is* there is the blind, and it is the one the server would
      // compute for that number.
      expect(sent, contains(PhoneNumbers.blind('+4915123456789')));
    });

    testWidgets('an entry that is not a number is dropped before sending',
        (tester) async {
      final server = _Server();
      final book = _FakeAddressBook(
        const AddressBookNumbers(['Pizza Napoli', 'not a number at all', '+4915123456789']),
      );
      final state = await tester.runAsync(() => _signedIn(server, book)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(_screen(state));
      await _settle(tester);
      await tester.tap(find.text('Match my contacts now'));
      await _settle(tester);

      final discover = server.bodies.where((body) => body.contains('blinded')).single;
      final blinded =
          ((jsonDecode(discover) as Map<String, dynamic>)['blinded'] as List<dynamic>);
      expect(blinded, hasLength(1), reason: 'rubbish costs a slot of the daily budget');
    });
  });

  group('what comes back', () {
    testWidgets('a match is offered, and adding it says so', (tester) async {
      final server = _Server()
        ..matches[PhoneNumbers.blind('+4915123456789')] = {
          'id': 'acc-bob',
          'username': 'bob',
          'displayName': 'Bob Baker',
        };
      final book = _FakeAddressBook(const AddressBookNumbers(['+4915123456789']));
      final state = await tester.runAsync(() => _signedIn(server, book)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(_screen(state));
      await _settle(tester);
      await tester.tap(find.text('Match my contacts now'));
      await _settle(tester);

      await _reveal(tester, find.text('Bob Baker'));
      expect(find.text('Bob Baker'), findsOneWidget);
      expect(find.text('@bob'), findsOneWidget);
      // The section caption, which `SettingsSection` upper-cases as it does
      // every other one on this screen.
      expect(find.text('1 CONTACT ON PRIVIO'), findsOneWidget);
    });

    testWidgets('nobody found says so rather than showing an empty box',
        (tester) async {
      final server = _Server();
      final book = _FakeAddressBook(const AddressBookNumbers(['+4915123456789']));
      final state = await tester.runAsync(() => _signedIn(server, book)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(_screen(state));
      await _settle(tester);
      await tester.tap(find.text('Match my contacts now'));
      await _settle(tester);

      await _reveal(tester, find.textContaining('Nobody in your address book'));
      expect(find.textContaining('Nobody in your address book'), findsOneWidget);
    });

    testWidgets('a refusal is a sentence, and nothing is sent', (tester) async {
      final server = _Server();
      final book = _FakeAddressBook(const AddressBookDenied());
      final state = await tester.runAsync(() => _signedIn(server, book)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(_screen(state));
      await _settle(tester);
      await tester.tap(find.text('Match my contacts now'));
      await _settle(tester);

      expect(book.reads, 1);
      expect(
        server.bodies.where((body) => body.contains('blinded')),
        isEmpty,
        reason: 'a refusal must not still send something',
      );
      expect(find.textContaining('address book'), findsWidgets);
    });

    testWidgets('withdrawing the consent takes the results with it',
        (tester) async {
      final server = _Server()
        ..matches[PhoneNumbers.blind('+4915123456789')] = {
          'id': 'acc-bob',
          'username': 'bob',
          'displayName': 'Bob Baker',
        };
      final book = _FakeAddressBook(const AddressBookNumbers(['+4915123456789']));
      final state = await tester.runAsync(() => _signedIn(server, book)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(_screen(state));
      await _settle(tester);
      await tester.tap(find.text('Match my contacts now'));
      await _settle(tester);
      await _reveal(tester, find.text('Bob Baker'));
      expect(find.text('Bob Baker'), findsOneWidget);

      await _reveal(tester, find.byType(Switch).last);
      await tester.tap(find.byType(Switch).last);
      await _settle(tester);

      expect(find.text('Bob Baker'), findsNothing);
      expect(find.text('Match my contacts now'), findsNothing);
    });
  });

  group('the deployment', () {
    testWidgets('with no discovery key the row says so rather than failing',
        (tester) async {
      final server = _Server()
        ..link = {..._Server().link, 'discoveryAvailable': false};
      final book = _FakeAddressBook(const AddressBookNumbers(['+4915123456789']));
      final state = await tester.runAsync(() => _signedIn(server, book)) as AppState;
      addTearDown(state.conversations.stop);

      await tester.pumpWidget(_screen(state));
      await _settle(tester);

      expect(find.text('Match my contacts now'), findsOneWidget);
      await tester.tap(find.text('Match my contacts now'));
      await _settle(tester);

      // The row is there and disabled, so the tap does nothing at all — it does
      // not open the address book on a server that could not match anyway.
      expect(book.reads, 0);
    });
  });

  group('the channel', () {
    test('a platform with no address book reads as unsupported, not denied',
        () async {
      // The two need different sentences: only one of them should send somebody
      // to a settings app for a permission that is not the problem.
      expect(await const NoAddressBook().read(), isA<AddressBookUnsupported>());
    });
  });
}
