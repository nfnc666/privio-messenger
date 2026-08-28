/// License key handling, mirroring `server/src/services/licenses.ts`.
///
/// The server is the only thing that decides whether a key is real — this file
/// exists so that a key typed off a screen is folded to the same canonical form
/// on both sides, and so an obviously incomplete key can be caught before it
/// spends one of five redemption attempts.
library;

/// Crockford base32: no I, L, O or U, so a key read aloud or typed on a phone
/// keyboard does not turn into a support ticket.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// 16 symbols — 80 bits.
const int licenseKeyBodyLength = 16;

/// What a key looks like on the website and on paper.
const String licenseKeyFormat = 'PRIVIO-XXXX-XXXX-XXXX-XXXX';

/// Folds the shapes a human can produce onto one canonical form: case,
/// separators, and the characters Crockford treats as aliases.
///
/// The `PRIVIO` prefix is stripped before the aliases are folded, because the
/// prefix contains an I and an O itself.
String normaliseLicenseKey(String input) {
  final cleaned = input.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
  final body = cleaned.startsWith('PRIVIO') ? cleaned.substring('PRIVIO'.length) : cleaned;
  return body.replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1').replaceAll('U', 'V');
}

/// Whether [input] could be a license key at all.
///
/// Deliberately only a shape check. A key that passes this can still be
/// unknown, revoked or already redeemed, and only the server can say which —
/// so nothing here should ever be phrased to the user as "valid".
bool isWellFormedLicenseKey(String input) {
  final body = normaliseLicenseKey(input);
  if (body.length != licenseKeyBodyLength) return false;
  return body.split('').every(_alphabet.contains);
}

/// Renders a key the way it is printed: `PRIVIO-XXXX-XXXX-XXXX-XXXX`.
///
/// Anything that is not yet a full key comes back as the normalised body in
/// groups of four, so the field can format as the user types without jumping
/// around once they reach the last character.
String formatLicenseKey(String input) {
  final body = normaliseLicenseKey(input);
  if (body.isEmpty) return '';
  final groups = <String>[];
  for (var i = 0; i < body.length; i += 4) {
    groups.add(body.substring(i, i + 4 > body.length ? body.length : i + 4));
  }
  return 'PRIVIO-${groups.join('-')}';
}
