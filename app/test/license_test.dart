import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/edition.dart';
import 'package:privio/core/license_controller.dart';
import 'package:privio/core/license_key.dart';
import 'package:privio/core/secure_store.dart';

PrivioApiClient _client(
  http.Response Function(http.Request request) respond, {
  List<http.Request>? seen,
}) =>
    PrivioApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient((request) async {
        seen?.add(request);
        return respond(request);
      }),
    )..useToken('token');

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('key normalisation', () {
    test('folds case, separators and the Crockford aliases', () {
      // O -> 0, I and L -> 1, U -> V. A key read off a screen and typed by
      // hand has to reach the server as the same 16 symbols it was minted as.
      expect(
        normaliseLicenseKey('privio-oilu-abcd-efgh-jkmn'),
        normaliseLicenseKey('PRIVIO 011V ABCD EFGH JKMN'),
      );
      // Four symbols in, four symbols out: O, I, L and U each fold to one
      // character, so the body stays the 16 symbols it was minted as.
      expect(normaliseLicenseKey('privio-oilu-abcd-efgh-jkmn'), '011VABCDEFGHJKMN');
      expect(normaliseLicenseKey('privio-oilu-abcd-efgh-jkmn').length, licenseKeyBodyLength);
    });

    test('strips the prefix before folding, so its own I and O survive', () {
      // "PRIVIO" contains an I and an O. Folding first would turn the prefix
      // into "PR1V10" and leave two stray symbols in the body.
      expect(normaliseLicenseKey('PRIVIO-2345-6789-ABCD-EFGH').length, licenseKeyBodyLength);
    });

    test('a key without the prefix normalises the same way', () {
      expect(
        normaliseLicenseKey('2345-6789-ABCD-EFGH'),
        normaliseLicenseKey('PRIVIO-2345-6789-ABCD-EFGH'),
      );
    });
  });

  group('shape check', () {
    test('accepts a full key however it was typed', () {
      expect(isWellFormedLicenseKey('privio 2345 6789 abcd efgh'), isTrue);
      expect(isWellFormedLicenseKey('PRIVIO-2345-6789-ABCD-EFGH'), isTrue);
    });

    test('rejects anything that is not 16 symbols', () {
      expect(isWellFormedLicenseKey(''), isFalse);
      expect(isWellFormedLicenseKey('PRIVIO-2345-6789-ABCD-EFG'), isFalse);
      expect(isWellFormedLicenseKey('PRIVIO-2345-6789-ABCD-EFGHJ'), isFalse);
    });
  });

  test('formatting groups the body and puts the prefix back', () {
    expect(formatLicenseKey('23456789abcdefgh'), 'PRIVIO-2345-6789-ABCD-EFGH');
    expect(formatLicenseKey('2345'), 'PRIVIO-2345');
    expect(formatLicenseKey(''), '');
  });

  group('redeeming', () {
    test('an incomplete key is refused before it reaches the server', () async {
      // Redemption is rate limited to five attempts. A typo must not spend one.
      final seen = <http.Request>[];
      final license = LicenseController(
        _client((_) => _json(const {'licensed': true}), seen: seen),
      );

      expect(await license.redeem('PRIVIO-2345'), isFalse);
      expect(seen, isEmpty);
      expect(license.error, contains('not complete'));
    });

    test('a redeemed key leaves the account licensed', () async {
      final seen = <http.Request>[];
      final license = LicenseController(
        _client(
          (_) => _json(const {
            'licensed': true,
            'source': 'key',
            'redeemedAt': '2026-08-28T10:00:00.000Z',
          }),
          seen: seen,
        ),
      );

      expect(await license.redeem('privio 2345 6789 abcd efgh'), isTrue);
      expect(license.state?.licensed, isTrue);
      expect(license.error, isNull);

      // The canonical form goes on the wire, whatever was typed.
      expect(
        jsonDecode(seen.single.body),
        {'licenseKey': 'PRIVIO-2345-6789-ABCD-EFGH'},
      );
    });

    test('a key someone else already used says so, and says it is final', () async {
      final license = LicenseController(
        _client(
          (_) => _json(
            const {'error': 'license_already_redeemed', 'message': 'This key has already been used'},
            409,
          ),
        ),
      );

      expect(await license.redeem('PRIVIO-2345-6789-ABCD-EFGH'), isFalse);
      expect(license.state?.licensed, isNot(true));
      expect(license.error, contains('only be redeemed once'));
    });

    test('an already-licensed account is told its key was not consumed', () async {
      // The server rolls the transaction back, so the key is still worth
      // something — the message must not suggest it was burned.
      final license = LicenseController(
        _client(
          (_) => _json(
            const {'error': 'account_already_licensed', 'message': 'Already licensed'},
            409,
          ),
        ),
      );

      expect(await license.redeem('PRIVIO-2345-6789-ABCD-EFGH'), isFalse);
      expect(license.error, contains('has not been used'));
    });
  });

  group('status', () {
    test('a server that requires no license asks for nothing', () async {
      // Self-hosting: `required: false` has to reach the UI, or the app nags
      // for a key that its own server does not want.
      final license = LicenseController(
        _client((_) => _json(const {'licensed': false, 'required': false})),
      );

      await license.refresh();

      expect(license.state?.enforced, isFalse);
      expect(license.needsActivation, isFalse);
      expect(license.isOffered, isFalse);
    });

    test('unlicensed on a server that requires one needs activation', () async {
      final license = LicenseController(
        _client((_) => _json(const {'licensed': false, 'required': true})),
      );

      await license.refresh();

      expect(license.needsActivation, isTrue);
      expect(license.isOffered, isTrue);
    });

    test('offline is not unlicensed', () async {
      // A failed refresh must never downgrade a paying account to "activate a
      // key" — the last known answer stands until a better one arrives.
      var fail = false;
      final license = LicenseController(
        _client((_) {
          if (fail) throw http.ClientException('offline');
          return _json(const {'licensed': true, 'required': true, 'source': 'key'});
        }),
      );

      await license.refresh();
      expect(license.state?.licensed, isTrue);

      fail = true;
      await license.refresh();
      expect(license.state?.licensed, isTrue);
    });
  });

  group('the key entered before there is an account', () {
    test('is held, then spent the moment an account exists', () async {
      // The launch screen cannot redeem: there is nobody to bind a key to yet.
      // It keeps the key, and the first sign-in cashes it in.
      final store = InMemorySecureStore();
      final seen = <http.Request>[];
      final license = LicenseController(
        _client((_) => _json(const {'licensed': true, 'source': 'key'}), seen: seen),
        store: store,
      );

      expect(await license.hold('privio 2345 6789 abcd efgh'), isTrue);
      expect(await store.readPendingLicenseKey(), 'PRIVIO-2345-6789-ABCD-EFGH');
      expect(seen, isEmpty, reason: 'holding a key talks to nobody');

      expect(await license.redeemPending(), isTrue);
      expect(
        await store.readPendingLicenseKey(),
        isNull,
        reason: 'a spent bearer secret is not worth keeping',
      );
    });

    test('a malformed key never reaches the keystore', () async {
      final store = InMemorySecureStore();
      final license = LicenseController(
        _client((_) => _json(const {'licensed': true})),
        store: store,
      );

      expect(await license.hold('PRIVIO-2345'), isFalse);
      expect(await store.readPendingLicenseKey(), isNull);
      expect(license.error, contains('not complete'));
    });

    test('nothing held means nothing to redeem', () async {
      final seen = <http.Request>[];
      final license = LicenseController(
        _client((_) => _json(const {'licensed': true}), seen: seen),
        store: InMemorySecureStore(),
      );

      expect(await license.redeemPending(), isFalse);
      expect(seen, isEmpty);
    });

    test('a key that can never work again is dropped rather than retried', () async {
      // Redemption is rate limited. Re-sending a key that belongs to someone
      // else on every launch would spend the account's attempts on a key that
      // is gone for good.
      final store = InMemorySecureStore();
      final license = LicenseController(
        _client(
          (_) => _json(
            const {'error': 'license_already_redeemed', 'message': 'used'},
            409,
          ),
        ),
        store: store,
      );

      await license.hold('PRIVIO-2345-6789-ABCD-EFGH');
      expect(await license.redeemPending(), isFalse);
      expect(await store.readPendingLicenseKey(), isNull);
    });

    test('a key that failed on a flat network is kept for the next try', () async {
      final store = InMemorySecureStore();
      final license = LicenseController(
        _client((_) => throw http.ClientException('offline')),
        store: store,
      );

      await license.hold('PRIVIO-2345-6789-ABCD-EFGH');
      expect(await license.redeemPending(), isFalse);
      expect(
        await store.readPendingLicenseKey(),
        'PRIVIO-2345-6789-ABCD-EFGH',
        reason: 'a lost connection must not cost someone their purchase',
      );
    });
  });

  group('the cached status', () {
    test('survives a cold start so the first frame is not a question mark', () async {
      final store = InMemorySecureStore();
      final first = LicenseController(
        _client(
          (_) => _json(const {
            'licensed': true,
            'required': true,
            'source': 'key',
            'maxDevices': 5,
            'devices': 2,
          }),
        ),
        store: store,
      );
      await first.refresh();

      // A second controller over a server that cannot be reached at all.
      final second = LicenseController(
        _client((_) => throw http.ClientException('offline')),
        store: store,
      );
      await second.restore();

      expect(second.state?.licensed, isTrue);
      expect(second.state?.maxDevices, 5);
      expect(second.state?.devices, 2);
    });

    test('a cache that will not parse is thrown away, not crashed on', () async {
      final store = InMemorySecureStore();
      await store.writeLicenseCache('{not json');
      final license = LicenseController(
        _client((_) => _json(const {'licensed': false})),
        store: store,
      );

      await license.restore();

      expect(license.state, isNull);
      expect(await store.readLicenseCache(), isNull);
    });

    test('reports the device allowance the licence was sold with', () async {
      final license = LicenseController(
        _client(
          (_) => _json(const {
            'licensed': true,
            'required': true,
            'maxDevices': 2,
            'devices': 2,
          }),
        ),
      );

      await license.refresh();

      expect(license.state?.atDeviceLimit, isTrue);
    });

    test('a server with no licence endpoint is a server that sells nothing', () async {
      // 404 is an answer, not an error: an older deployment that has never
      // heard of licences must not be shown a key screen that cannot work.
      final license = LicenseController(
        _client(
          (_) => _json(const {'error': 'not_found', 'message': 'no route'}, 404),
        ),
      );

      await license.refresh();

      expect(license.state?.enforced, isFalse);
      expect(license.isOffered, isFalse);
      expect(license.error, isNull);
    });

    test('any other failure leaves the last known answer alone', () async {
      final license = LicenseController(
        _client((_) => _json(const {'error': 'server_error'}, 500)),
      );

      await license.refresh();

      expect(license.state, isNull, reason: 'a 500 says nothing about a licence');
    });

    test('a server that does not report the numbers claims no limit', () async {
      // An older server says nothing about devices. Inventing a limit it does
      // not enforce would be worse than saying nothing.
      final license = LicenseController(
        _client((_) => _json(const {'licensed': true, 'required': true})),
      );

      await license.refresh();

      expect(license.state?.atDeviceLimit, isFalse);
    });
  });

  group('edition', () {
    test('the store builds do not offer a key field', () {
      expect(PrivioEdition.parse('libre').usesLicenseKey, isTrue);
      expect(PrivioEdition.parse('direct').usesLicenseKey, isTrue);
      expect(PrivioEdition.parse('play').usesLicenseKey, isFalse);
      expect(PrivioEdition.parse('appstore').usesLicenseKey, isFalse);
    });

    test('only the free builds claim to be free', () {
      expect(PrivioEdition.parse('libre').isLibre, isTrue);
      expect(PrivioEdition.parse('direct').isLibre, isTrue);
      expect(PrivioEdition.parse('play').usesProprietaryServices, isTrue);
    });

    test('the Libre build talks to no push service', () {
      expect(PrivioEdition.parse('libre').pushProvider, isNull);
      expect(PrivioEdition.parse('play').pushProvider, 'fcm');
    });

    test('an unknown edition falls back to Libre rather than crashing', () {
      // A typo in a build script must not ship an app that claims more than
      // it is, and must not ship one that will not start either.
      expect(PrivioEdition.parse('').id, 'libre');
      expect(PrivioEdition.parse('nonsense').id, 'libre');
      expect(PrivioEdition.parse('LIBRE').id, 'libre');
    });
  });
}
