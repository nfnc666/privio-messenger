import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/failure.dart';
import 'package:privio/core/phone_controller.dart';
import 'package:privio/core/phone_number.dart';

/// A server that answers the phone routes from a little state of its own.
class _Server {
  _Server();

  final List<http.Request> seen = <http.Request>[];

  bool linked = false;
  String? hint;
  bool discoverable = false;
  bool contactSync = false;
  bool smsAvailable = true;
  bool discoveryAvailable = true;

  /// The code the stub "sent", and what the next confirm will accept.
  String code = '123456';

  /// Refusals to serve on the next write, as error codes.
  final List<String> refusals = [];

  /// Accounts that are findable, by blinded value.
  final Map<String, Map<String, dynamic>> findable = {};

  Completer<void>? gate;

  PrivioApiClient client() => PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient((request) async {
          seen.add(request);
          final pending = gate;
          if (pending != null) await pending.future;

          final path = request.url.path;
          if (refusals.isNotEmpty && request.method != 'GET') {
            return _json({'error': refusals.removeAt(0), 'message': 'refused'}, status: 400);
          }

          if (request.method == 'GET' && path == '/v1/phone') return _json(_state());

          if (request.method == 'POST' && path == '/v1/phone/verifications') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final number = body['phone'] as String;
            return _json({
              'hint': '+49 … ${number.substring(number.length - 2)}',
              'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
              'attemptsAllowed': 5,
              'developmentStub': true,
              'code': code,
            });
          }

          if (request.method == 'POST' && path == '/v1/phone') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['code'] != code) {
              return _json({'error': 'wrong_code', 'message': 'no'}, status: 400);
            }
            linked = true;
            hint = '+49 … 89';
            // Verifying always leaves discoverability off.
            discoverable = false;
            return _json(_state());
          }

          if (request.method == 'PUT' && path == '/v1/phone/discoverable') {
            discoverable = (jsonDecode(request.body) as Map<String, dynamic>)['discoverable'] as bool;
            return _json(_state());
          }

          if (request.method == 'PUT' && path == '/v1/phone/contact-sync') {
            contactSync = (jsonDecode(request.body) as Map<String, dynamic>)['enabled'] as bool;
            return _json({'contactSync': contactSync});
          }

          if (request.method == 'DELETE' && path == '/v1/phone') {
            linked = false;
            hint = null;
            discoverable = false;
            return _json({'linked': false});
          }

          if (request.method == 'POST' && path == '/v1/contacts/discover') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final asked = (body['blinded'] as List<dynamic>).cast<String>();
            return _json({
              'matches': [
                for (final value in asked)
                  if (findable[value] != null) {...findable[value]!, 'blinded': value},
              ],
              'budgetRemaining': 1000,
            });
          }

          return _json({'error': 'not_found'}, status: 404);
        }),
      )..useToken('token');

  Map<String, dynamic> _state() => {
        'linked': linked,
        'hint': hint,
        'discoverable': discoverable,
        'contactSync': contactSync,
        'verifiedAt': linked ? DateTime.utc(2026).toIso8601String() : null,
        'smsAvailable': smsAvailable,
        'discoveryAvailable': discoveryAvailable,
      };

  static http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}

void main() {
  group('an account without a number', () {
    test('loads, and is complete', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');

      expect(controller.link.linked, isFalse);
      expect(controller.link.hint, isNull);
      expect(controller.link.discoverable, isFalse);
      expect(controller.failure, isNull);
    });

    test('says so when the server cannot send texts, rather than failing later',
        () async {
      final server = _Server()..smsAvailable = false;
      final controller = PhoneController(server.client());
      await controller.load('account-a');

      expect(controller.link.canVerify, isFalse);
    });
  });

  group('verifying', () {
    test('a number is linked, and is not discoverable yet', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');

      expect(await controller.requestCode('+49 151 23456789'), isTrue);
      expect(controller.stage, PhoneStage.awaitingCode);
      expect(await controller.confirmCode('123456'), isTrue);

      expect(controller.link.linked, isTrue);
      expect(
        controller.link.discoverable,
        isFalse,
        reason: 'attaching a number is not consent to be found by it',
      );
      expect(controller.stage, PhoneStage.idle);
    });

    test('the number goes up once, and only as E.164', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      await controller.requestCode('0049 151 23456789');

      final sent = server.seen.where((r) => r.url.path == '/v1/phone/verifications').single;
      expect(jsonDecode(sent.body)['phone'], '+4915123456789');
    });

    test('a number that does not normalise never reaches the network', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      final before = server.seen.length;

      expect(await controller.requestCode('0151 23456789'), isFalse);
      expect(controller.failure?.kind, FailureKind.phoneInvalid);
      expect(server.seen.length, before, reason: 'no SMS should have been paid for');
    });

    test('a wrong code leaves the account without a number', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      await controller.requestCode('+49 151 23456789');

      expect(await controller.confirmCode('000000'), isFalse);
      expect(controller.failure?.kind, FailureKind.phoneWrongCode);
      expect(controller.link.linked, isFalse);
      expect(controller.stage, PhoneStage.awaitingCode, reason: 'still waiting, not reset');
    });

    test('cancelling leaves nothing behind and links nothing', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      await controller.requestCode('+49 151 23456789');

      controller.cancelVerification();

      expect(controller.stage, PhoneStage.idle);
      expect(controller.pendingHint, isNull);
      expect(controller.link.linked, isFalse);
    });

    test('the development stub is carried through and labelled', () async {
      // It exists so the flow can be worked on without a paid SMS account. The
      // controller only holds it when the server said `developmentStub: true`.
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      await controller.requestCode('+49 151 23456789');

      expect(controller.stubCode, '123456');
    });

    test('each refusal becomes its own case, not English from the wire', () async {
      final cases = {
        'sms_not_configured': FailureKind.phoneSmsUnavailable,
        'code_expired': FailureKind.phoneCodeExpired,
        'too_many_attempts': FailureKind.phoneTooManyAttempts,
        'too_many_sends': FailureKind.phoneTooManySends,
        'resend_too_soon': FailureKind.phoneResendTooSoon,
        'phone_unchanged': FailureKind.phoneUnchanged,
      };
      for (final entry in cases.entries) {
        final server = _Server()..refusals.add(entry.key);
        final controller = PhoneController(server.client());
        await controller.load('account-a');
        await controller.requestCode('+49 151 23456789');
        expect(controller.failure?.kind, entry.value, reason: entry.key);
      }
    });
  });

  group('the two consents', () {
    test('are separate, and both start off', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      await controller.requestCode('+49 151 23456789');
      await controller.confirmCode('123456');

      expect(controller.link.discoverable, isFalse);
      expect(controller.link.contactSync, isFalse);

      await controller.setDiscoverable(true);
      expect(controller.link.discoverable, isTrue);
      expect(
        controller.link.contactSync,
        isFalse,
        reason: 'being findable is not consent to read the address book',
      );

      await controller.setContactSync(true);
      expect(controller.link.contactSync, isTrue);
      expect(controller.link.discoverable, isTrue);
    });

    test('removing the number clears the link but leaves sync as it was',
        () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      await controller.requestCode('+49 151 23456789');
      await controller.confirmCode('123456');
      await controller.setDiscoverable(true);
      await controller.setContactSync(true);

      expect(await controller.removeNumber(), isTrue);

      expect(controller.link.linked, isFalse);
      expect(controller.link.discoverable, isFalse);
      // Syncing contacts does not depend on having a number of one's own, so
      // removing one does not silently switch it off.
      expect(controller.link.contactSync, isTrue);
    });
  });

  group('matching contacts', () {
    test('sends blinded values, never numbers', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');

      await controller.discover(['+49 151 23456789', '+1 202 555 0123']);

      final sent = server.seen.where((r) => r.url.path == '/v1/contacts/discover').single;
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      final blinded = (body['blinded'] as List<dynamic>).cast<String>();

      expect(blinded, hasLength(2));
      expect(sent.body.contains('23456789'), isFalse, reason: 'no number may leave the device');
      expect(sent.body.contains('2025550123'), isFalse);
      expect(blinded, contains(PhoneNumbers.blind('+4915123456789')));
    });

    test('drops entries that are not numbers rather than sending them', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');

      await controller.discover(['Pizza (Mobile)', '', '+49 151 23456789', 'x']);

      final sent = server.seen.where((r) => r.url.path == '/v1/contacts/discover').single;
      expect((jsonDecode(sent.body)['blinded'] as List<dynamic>), hasLength(1));
    });

    test('an address book with nothing usable in it costs no request', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      final before = server.seen.length;

      expect(await controller.discover(['Pizza', 'Mum']), isEmpty);
      expect(server.seen.length, before);
    });

    test('duplicates are asked about once', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');

      await controller.discover(['+4915123456789', '+49 151 23456789', '0049 151 23456789']);

      final sent = server.seen.where((r) => r.url.path == '/v1/contacts/discover').single;
      expect((jsonDecode(sent.body)['blinded'] as List<dynamic>), hasLength(1));
    });

    test('a match comes back with the entry it answers', () async {
      final server = _Server();
      server.findable[PhoneNumbers.blind('+4915123456789')] = {
        'id': 'acc-bob',
        'username': 'bob',
        'displayName': 'Bob',
      };
      final controller = PhoneController(server.client());
      await controller.load('account-a');

      final found = await controller.discover(['+49 151 23456789', '+49 151 00000000']);

      expect(found, hasLength(1));
      expect(found!.single.username, 'bob');
      expect(found.single.blinded, PhoneNumbers.blind('+4915123456789'));
    });
  });

  group('a phone link belongs to an account', () {
    test('a switch empties it', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      await controller.requestCode('+49 151 23456789');
      await controller.confirmCode('123456');
      expect(controller.link.linked, isTrue);

      server
        ..linked = false
        ..hint = null;
      await controller.load('account-b');

      expect(controller.link.linked, isFalse);
      expect(controller.link.hint, isNull);
    });

    test('an answer arriving after a switch is dropped, not applied', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');

      server.gate = Completer<void>();
      final inFlight = controller.load('account-a');

      controller.signedOut();
      server
        ..linked = true
        ..hint = '+49 … 89';
      server.gate!.complete();
      await inFlight;

      expect(
        controller.link.linked,
        isFalse,
        reason: 'one account s number must never appear on another',
      );
    });

    test('signing out clears the verification in flight too', () async {
      final server = _Server();
      final controller = PhoneController(server.client());
      await controller.load('account-a');
      await controller.requestCode('+49 151 23456789');

      controller.signedOut();

      expect(controller.stage, PhoneStage.idle);
      expect(controller.stubCode, isNull);
      expect(controller.pendingHint, isNull);
    });
  });
}
