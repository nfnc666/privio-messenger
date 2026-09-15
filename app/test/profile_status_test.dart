import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/failure.dart';
import 'package:privio/core/status_controller.dart';

/// A server that answers whatever the test tells it to, and records what it was
/// asked.
class _Server {
  _Server();

  final List<http.Request> seen = <http.Request>[];

  /// The status the account currently has, as the server would report it.
  Map<String, dynamic>? stored;

  /// How many of the next writes fail the way a dead connection does.
  int failuresToServe = 0;

  /// Held open so a test can decide when a request finishes — which is how the
  /// account-switch race below is made deterministic rather than hopeful.
  Completer<void>? gate;

  PrivioApiClient client() => PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient((request) async {
          seen.add(request);
          final pending = gate;
          if (pending != null) await pending.future;

          if (failuresToServe > 0) {
            failuresToServe -= 1;
            throw http.ClientException('no route to host');
          }

          final path = request.url.path;
          if (request.method == 'GET' && path == '/v1/accounts/me') {
            return _json({'status': stored ?? _none});
          }
          if (request.method == 'PUT' && path == '/v1/accounts/me/status') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final text = (body['text'] as String?)?.trim();
            final emoji = (body['emoji'] as String?)?.trim();
            stored = (text == null || text.isEmpty) && (emoji == null || emoji.isEmpty)
                ? null
                : {
                    'text': text?.isEmpty ?? true ? null : text,
                    'emoji': emoji?.isEmpty ?? true ? null : emoji,
                    'expiresAt': body['expiresAt'],
                    'updatedAt': DateTime.utc(2026).toIso8601String(),
                  };
            return _json({'status': stored ?? _none});
          }
          if (request.method == 'DELETE' && path == '/v1/accounts/me/status') {
            stored = null;
            return _json({'status': _none});
          }
          return http.Response('{}', 404);
        }),
      )..useToken('token');

  static const Map<String, dynamic> _none = {
    'text': null,
    'emoji': null,
    'expiresAt': null,
    'updatedAt': null,
  };

  static http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
}

void main() {
  group('a status is set, changed and removed', () {
    test('setting one stores it and shows it', () async {
      final server = _Server();
      final controller = StatusController(server.client())..adopt('account-a', null);

      expect(controller.status.isSet, isFalse);
      expect(await controller.save(text: 'Writing tests', emoji: '💻'), isTrue);

      expect(controller.status.text, 'Writing tests');
      expect(controller.status.emoji, '💻');
      expect(controller.status.isSet, isTrue);
      expect(controller.failure, isNull);

      final sent = jsonDecode(server.seen.single.body) as Map<String, dynamic>;
      expect(sent['text'], 'Writing tests');
      expect(sent['emoji'], '💻');
    });

    test('changing one replaces it', () async {
      final server = _Server();
      final controller = StatusController(server.client())..adopt('account-a', null);

      await controller.save(text: 'First');
      await controller.save(text: 'Second', emoji: '☕');

      expect(controller.status.text, 'Second');
      expect(controller.status.emoji, '☕');
    });

    test('removing one leaves nothing', () async {
      final server = _Server();
      final controller = StatusController(server.client())..adopt('account-a', null);

      await controller.save(text: 'Here');
      expect(controller.status.isSet, isTrue);

      expect(await controller.remove(), isTrue);
      expect(controller.status.isSet, isFalse);
      expect(controller.status.text, isNull);
      expect(server.stored, isNull);
    });

    test('an empty save is a removal, not a status of whitespace', () async {
      final server = _Server();
      final controller = StatusController(server.client())..adopt('account-a', null);

      await controller.save(text: 'Here');
      await controller.save(text: null, emoji: null);

      expect(controller.status.isSet, isFalse);
      expect(server.stored, isNull);
    });
  });

  group('the draft survives a failure', () {
    test('a failed save reports it, keeps the old value and allows a retry', () async {
      final server = _Server();
      final controller = StatusController(server.client())..adopt('account-a', null);
      await controller.save(text: 'Original');

      server.failuresToServe = 1;
      expect(await controller.save(text: 'New one'), isFalse);

      // The failure is reported as a case, the stored value is untouched, and
      // nothing pretends the save happened.
      expect(controller.failure, isNotNull);
      expect(controller.failure!.kind, FailureKind.statusNotSaved);
      expect(controller.status.text, 'Original');
      expect(controller.saving, isFalse);

      // And the same call again now works — the controller is not wedged.
      expect(await controller.save(text: 'New one'), isTrue);
      expect(controller.status.text, 'New one');
      expect(controller.failure, isNull);
    });

    test('a failed removal does not remove anything', () async {
      final server = _Server();
      final controller = StatusController(server.client())..adopt('account-a', null);
      await controller.save(text: 'Still here');

      server.failuresToServe = 1;
      expect(await controller.remove(), isFalse);

      expect(controller.status.text, 'Still here');
      expect(server.stored, isNotNull);
      expect(controller.failure, isNotNull);
    });
  });

  group('one save at a time', () {
    test('a second save while the first is in flight is refused', () async {
      final server = _Server()..gate = Completer<void>();
      final controller = StatusController(server.client())..adopt('account-a', null);

      final first = controller.save(text: 'One');
      await pumpEventQueue();
      expect(controller.saving, isTrue);

      // The button is disabled on `saving`; this is the tap that gets through
      // anyway. It must not become a second request.
      expect(await controller.save(text: 'Two'), isFalse);
      expect(server.seen.length, 1);

      server.gate!.complete();
      expect(await first, isTrue);
      expect(controller.status.text, 'One');
      expect(server.seen.length, 1);
    });

    test('a removal cannot overlap a save either', () async {
      final server = _Server()..gate = Completer<void>();
      final controller = StatusController(server.client())..adopt('account-a', null);

      final saving = controller.save(text: 'One');
      await pumpEventQueue();
      expect(await controller.remove(), isFalse);

      server.gate!.complete();
      await saving;
      expect(controller.status.text, 'One');
    });
  });

  group('a status belongs to one account', () {
    test('loading a second account does not inherit the first', () async {
      final server = _Server();
      final controller = StatusController(server.client());

      await controller.load('account-a');
      expect(controller.status.isSet, isFalse);
      await controller.save(text: "Alice's line");
      expect(controller.status.text, "Alice's line");

      // The next account. The server has a different answer for it — here,
      // none — and the controller must show that and not what it held.
      server.stored = null;
      await controller.load('account-b');

      expect(controller.accountId, 'account-b');
      expect(controller.status.isSet, isFalse);
      expect(controller.status.text, isNull);
    });

    test('the previous status is dropped before the new read, not after', () async {
      final server = _Server()..stored = {'text': 'Alice', 'emoji': null, 'expiresAt': null, 'updatedAt': null};
      final controller = StatusController(server.client());
      await controller.load('account-a');
      expect(controller.status.text, 'Alice');

      // Nothing answers while the gate is shut, so this is the window in which
      // a slow connection leaves the screen visible. It must not show Alice.
      server.gate = Completer<void>();
      final loading = controller.load('account-b');
      await pumpEventQueue();

      expect(controller.status.isSet, isFalse, reason: 'the old account\'s line is still on screen');
      expect(controller.loaded, isFalse);

      server.gate!.complete();
      await loading;
    });

    test('a save that lands after an account switch changes nothing', () async {
      final server = _Server()..gate = Completer<void>();
      final controller = StatusController(server.client())..adopt('account-a', null);

      // Alice presses save. The request is in flight.
      final inFlight = controller.save(text: "Alice's line");
      await pumpEventQueue();
      expect(controller.saving, isTrue);

      // Before it answers, the device switches to Bob and reads his status.
      server.gate!.complete();
      server.gate = null;
      controller.adopt('account-b', {
        'text': "Bob's line",
        'emoji': null,
        'expiresAt': null,
        'updatedAt': null,
      });

      // Alice's save now completes. It must not write her line onto Bob's
      // screen, must not clear a busy flag Bob never set, and must not report
      // success to anybody.
      expect(await inFlight, isFalse);
      expect(controller.accountId, 'account-b');
      expect(controller.status.text, "Bob's line");
      expect(controller.failure, isNull);
    });

    test('a failed save that lands after a switch does not show its error', () async {
      final server = _Server()
        ..gate = Completer<void>()
        ..failuresToServe = 1;
      final controller = StatusController(server.client())..adopt('account-a', null);

      final inFlight = controller.save(text: "Alice's line");
      await pumpEventQueue();

      controller.adopt('account-b', null);
      server.gate!.complete();

      expect(await inFlight, isFalse);
      // Bob is not shown "your status was not saved" for something Alice did.
      expect(controller.failure, isNull);
      expect(controller.accountId, 'account-b');
    });

    test('signing out forgets everything', () async {
      final server = _Server();
      final controller = StatusController(server.client())..adopt('account-a', null);
      await controller.save(text: 'Here');

      controller.signedOut();

      expect(controller.accountId, isNull);
      expect(controller.status.isSet, isFalse);
      expect(controller.loaded, isFalse);
      expect(controller.failure, isNull);
    });
  });

  group('a status comes back after a restart', () {
    test('a fresh controller reads what the account has', () async {
      final server = _Server();
      final first = StatusController(server.client())..adopt('account-a', null);
      await first.save(text: 'Set before the restart', emoji: '📚');

      // A new process: nothing carried over but the account id and the server.
      final afterRestart = StatusController(server.client());
      await afterRestart.load('account-a');

      expect(afterRestart.status.text, 'Set before the restart');
      expect(afterRestart.status.emoji, '📚');
      expect(afterRestart.loaded, isTrue);
    });

    test('a failed read says so rather than claiming there is no status', () async {
      final server = _Server()..failuresToServe = 1;
      final controller = StatusController(server.client());

      await controller.load('account-a');

      expect(controller.failure, isNotNull);
      // `loaded` stays false, so the row shows nothing rather than "Not set" —
      // which would be a claim the server never made.
      expect(controller.loaded, isFalse);
    });
  });

  group('expiry', () {
    test('a status past its moment is not set', () {
      final expired = ProfileStatus(
        text: 'Back at five',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(expired.isExpired, isTrue);
      expect(expired.isSet, isFalse);
    });

    test('one still within it is', () {
      final live = ProfileStatus(
        text: 'Back at five',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(live.isExpired, isFalse);
      expect(live.isSet, isTrue);
    });

    test('one with no expiry never runs out', () {
      const forever = ProfileStatus(text: 'Hello');
      expect(forever.isExpired, isFalse);
      expect(forever.isSet, isTrue);
    });

    test('the deadline is read against the clock, not cached at parse time', () async {
      // Two milliseconds in the future, so the same object answers differently
      // either side of it. This is what makes a screen left open across the
      // deadline stop showing the line without a round trip.
      final status = ProfileStatus(
        text: 'Almost gone',
        expiresAt: DateTime.now().add(const Duration(milliseconds: 20)),
      );
      expect(status.isSet, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(status.isSet, isFalse);
    });

    test('the expiry is sent as UTC', () async {
      final server = _Server();
      final controller = StatusController(server.client())..adopt('account-a', null);
      final until = DateTime.now().add(const Duration(hours: 1));

      await controller.save(text: 'Back later', expiresAt: until);

      final sent = jsonDecode(server.seen.single.body) as Map<String, dynamic>;
      expect(sent['expiresAt'], until.toUtc().toIso8601String());
      expect(sent['expiresAt'], endsWith('Z'));
    });
  });

  group('parsing what the server sends', () {
    test('a missing status object is no status, not a crash', () {
      expect(ProfileStatus.fromJson(null).isSet, isFalse);
    });

    test('empty strings are no status', () {
      final parsed = ProfileStatus.fromJson(const {'text': '  ', 'emoji': ''});
      expect(parsed.text, isNull);
      expect(parsed.emoji, isNull);
      expect(parsed.isSet, isFalse);
    });

    test('an unparseable expiry does not throw', () {
      final parsed = ProfileStatus.fromJson(const {'text': 'Hello', 'expiresAt': 'not a date'});
      expect(parsed.text, 'Hello');
      expect(parsed.expiresAt, isNull);
      expect(parsed.isSet, isTrue);
    });
  });
}
