import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/license_controller.dart';

/// Builds a controller over a client that answers with [body] and [status].
({LicenseController license, List<http.BaseRequest> seen}) harness({
  required Object body,
  int status = 200,
}) {
  final seen = <http.BaseRequest>[];
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient((request) async {
      seen.add(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  )..useToken('token');

  return (license: LicenseController(api), seen: seen);
}

void main() {
  group('license status', () {
    test('reads what the server says', () async {
      final h = harness(
        body: const {
          'licensed': true,
          'required': true,
          'source': 'key',
          'redeemedAt': '2026-05-25T10:00:00.000Z',
        },
      );

      await h.license.refresh();

      expect(h.license.licensed, isTrue);
      expect(h.license.status!.requiredByServer, isTrue);
      expect(h.license.status!.source, 'key');
      expect(h.license.status!.redeemedAt, isNotNull);
      expect(h.license.shouldPrompt, isFalse, reason: 'nothing left to do');
      expect(h.seen.single.url.path, '/v1/licenses/me');
    });

    test('asks for a key only where the server sells access', () async {
      final selfHosted = harness(body: const {'licensed': false, 'required': false});
      await selfHosted.license.refresh();

      expect(selfHosted.license.status!.settled, isTrue);
      expect(
        selfHosted.license.shouldPrompt,
        isFalse,
        reason: 'a licence for your own server would mean nothing',
      );

      final hosted = harness(body: const {'licensed': false, 'required': true});
      await hosted.license.refresh();

      expect(hosted.license.shouldPrompt, isTrue);
    });

    test('treats a server without the endpoint as one that does not require a license', () async {
      final h = harness(
        body: const {'error': 'not_found', 'message': 'No such endpoint'},
        status: 404,
      );

      await h.license.refresh();

      expect(h.license.status!.requiredByServer, isFalse);
      expect(h.license.error, isNull, reason: 'an older server is not a failure to report');
    });

    test('never claims a license the server did not confirm', () async {
      final h = harness(body: const {'error': 'internal_error', 'message': 'boom'}, status: 500);

      await h.license.refresh();

      expect(h.license.licensed, isFalse);
      expect(h.license.error, isNotNull);
    });
  });

  group('redeeming', () {
    test('sends the key and takes the answer as final', () async {
      final h = harness(
        body: const {'licensed': true, 'source': 'key', 'redeemedAt': '2026-05-25T10:00:00.000Z'},
      );

      final activated = await h.license.redeem('PRIVIO-A1B2-C3D4-E5F6-G7H8');

      expect(activated, isTrue);
      expect(h.license.licensed, isTrue);

      final request = h.seen.single as http.Request;
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/licenses/redeem');
      expect(jsonDecode(request.body), {'licenseKey': 'PRIVIO-A1B2-C3D4-E5F6-G7H8'});
    });

    test('does not call the server with an empty field', () async {
      final h = harness(body: const {'licensed': true});

      expect(await h.license.redeem('   '), isFalse);
      expect(h.seen, isEmpty);
      expect(h.license.error, 'Enter your license key.');
    });

    test('explains each refusal in words the user can act on', () async {
      const cases = {
        'license_not_found': 'does not exist',
        'license_already_redeemed': 'already been used',
        'license_revoked': 'revoked',
        'account_already_licensed': 'already has an active license',
        'rate_limited': 'Too many attempts',
      };

      for (final entry in cases.entries) {
        final h = harness(
          body: {'error': entry.key, 'message': 'raw server wording'},
          status: 409,
        );

        expect(await h.license.redeem('PRIVIO-AAAA-AAAA-AAAA-AAAA'), isFalse);
        expect(h.license.error, contains(entry.value), reason: entry.key);
        expect(h.license.licensed, isFalse);
      }
    });

    test('a rejected key leaves the account unlicensed rather than assuming', () async {
      final h = harness(body: const {'licensed': false}, status: 200);

      expect(await h.license.redeem('PRIVIO-AAAA-AAAA-AAAA-AAAA'), isFalse);
      expect(h.license.licensed, isFalse);
    });

    test('clears the busy flag even when the call throws', () async {
      final api = PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient((_) async => throw const SocketExceptionStub()),
      );
      final license = LicenseController(api);

      expect(await license.redeem('PRIVIO-AAAA-AAAA-AAAA-AAAA'), isFalse);
      expect(license.busy, isFalse);
      expect(license.error, contains('Could not reach Privio'));
    });
  });

  group('formatting', () {
    test('groups a key the way it is printed', () {
      expect(
        formatLicenseKey('privio a1b2c3d4e5f6g7h8'),
        'PRIVIO-A1B2-C3D4-E5F6-G7H8',
      );
    });

    test('accepts a key pasted without the prefix', () {
      expect(formatLicenseKey('a1b2c3d4e5f6g7h8'), 'PRIVIO-A1B2-C3D4-E5F6-G7H8');
    });

    test('does not run past four groups', () {
      expect(
        formatLicenseKey('PRIVIO-A1B2-C3D4-E5F6-G7H8-EXTRA'),
        'PRIVIO-A1B2-C3D4-E5F6-G7H8',
      );
    });

    test('leaves an empty field empty', () {
      expect(formatLicenseKey(''), '');
    });

    test('formats a partial key as it is typed', () {
      expect(formatLicenseKey('A1B'), 'PRIVIO-A1B');
      expect(formatLicenseKey('A1B2C'), 'PRIVIO-A1B2-C');
    });
  });
}

/// A stand-in for a transport failure; the controller only cares that it is not
/// an [ApiException].
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
