import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/phone_number.dart';

/// Normalising and blinding, pinned against the server's half.
///
/// The vector at the bottom is the load-bearing one: if the two
/// implementations ever disagree, nothing matches and the failure looks like
/// "contact discovery finds nobody" rather than like a hashing bug. So it is
/// asserted here and again in `server/test/phone.test.ts`, against the same
/// number and the same expected string.
void main() {
  group('normalising what people type', () {
    test('accepts the shapes people actually write', () {
      for (final written in [
        '+49 151 23456789',
        '+49-151-23456789',
        '+49 (151) 23456789',
        '0049 151 23456789',
        '+4915123456789',
        '  +4915123456789  ',
      ]) {
        expect(PhoneNumbers.normalise(written)?.e164, '+4915123456789', reason: written);
      }
    });

    test('refuses a number with no country rather than guessing one', () {
      // Guessing would quietly attach somebody to a number in a country they
      // have never been to.
      expect(PhoneNumbers.normalise('0151 23456789'), isNull);
      expect(PhoneNumbers.normalise('151 23456789'), isNull);
      expect(PhoneNumbers.normalise('(0151) 2345678'), isNull);
    });

    test('refuses nonsense', () {
      for (final bad in ['', '   ', 'hello', '+', '+49', '12345', '+999999123', '+49abc']) {
        expect(PhoneNumbers.normalise(bad), isNull, reason: '"$bad"');
      }
    });

    test('the hint is a country and two digits, and nothing more', () {
      final hint = PhoneNumbers.normalise('+1 202 555 0123')!.hint;
      expect(hint, '+1 … 23');
      expect(hint.contains('5550'), isFalse);
      expect(hint.contains('202'), isFalse);
    });

    test('a longer calling code wins over a shorter prefix of it', () {
      // +1242 is the Bahamas and +1 is North America. Matching +1 first would
      // put every Bahamian number in the wrong country.
      expect(PhoneNumbers.normalise('+1242 1234567')!.hint, startsWith('+1242'));
      expect(PhoneNumbers.normalise('+1 2021234567')!.hint, startsWith('+1 '));
    });
  });

  group('blinding', () {
    test('is stable for the same number', () {
      expect(
        PhoneNumbers.blind('+4915123456789'),
        PhoneNumbers.blind('+4915123456789'),
      );
    });

    test('differs for different numbers', () {
      expect(
        PhoneNumbers.blind('+4915123456789'),
        isNot(PhoneNumbers.blind('+4915123456780')),
      );
    });

    test('is 32 bytes, which is what the server will accept', () {
      // The route refuses anything that is not exactly a SHA-256, so that a
      // client cannot send a plaintext number and have it silently work.
      expect(PhoneNumbers.blind('+4915123456789').length, 44); // 32 bytes, base64
    });

    test('matches the server, byte for byte', () {
      // HMAC-SHA256("privio.contact-discovery.v1", "+4915123456789"), base64.
      // The same assertion exists in server/test/phone.test.ts. If one side is
      // ever changed without the other, one of the two goes red rather than
      // discovery quietly finding nobody.
      expect(
        PhoneNumbers.blind('+4915123456789'),
        'S8FSbBRRbtPyuNx83jrw3rU0g5BqVqrtctNJhuZuHVw=',
      );
    });
  });
}
