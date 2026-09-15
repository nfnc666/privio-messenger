import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

/// Phone numbers, normalised and blinded exactly as the server does it.
///
/// The two implementations have to agree character for character or nothing
/// ever matches, so both are pinned against the same vector — here in
/// `phone_test.dart` and on the server in `phone.test.ts`.
///
/// What the blinding is worth is written out in `server/src/services/phone.ts`
/// and in `docs/phone-contacts.md`, and it is deliberately modest: the context
/// key below is **public**, because it ships in this app, so a blind is a value
/// anybody can brute-force back to a number. It stops a plaintext address book
/// leaving the device; it is not anonymity and this file does not call it that.
@immutable
class PhoneNumber {
  const PhoneNumber({required this.e164, required this.hint});

  final String e164;

  /// The calling code and the last two digits: "+49 … 87". What a settings
  /// screen shows so somebody recognises which of their numbers is attached.
  final String hint;

  @override
  bool operator ==(Object other) => other is PhoneNumber && other.e164 == e164;

  @override
  int get hashCode => e164.hashCode;
}

abstract final class PhoneNumbers {
  /// The public key numbers are blinded under. Matches `DISCOVERY_CONTEXT` in
  /// `server/src/services/phone.ts`; both sides must use the same string.
  static const String discoveryContext = 'privio.contact-discovery.v1';

  /// Calling codes, longest first so `+1` cannot swallow `+1242`.
  ///
  /// The same list the server holds, and for the same reason: it splits a
  /// number into country and rest, and refuses obvious nonsense before an SMS
  /// is paid for. It is not a claim that a number is in service — the code that
  /// arrives by text is what proves that.
  static final List<String> _callingCodes = [
    '1242','1246','1264','1268','1284','1340','1345','1441','1473','1649','1664','1670','1671',
    '1684','1721','1758','1767','1784','1809','1829','1849','1868','1869','1876','1939',
    '212','213','216','218','220','221','222','223','224','225','226','227','228','229',
    '230','231','232','233','234','235','236','237','238','239','240','241','242','243','244',
    '245','246','247','248','249','250','251','252','253','254','255','256','257','258','260',
    '261','262','263','264','265','266','267','268','269','290','291','297','298','299',
    '350','351','352','353','354','355','356','357','358','359',
    '370','371','372','373','374','375','376','377','378','379','380','381','382','383','385',
    '386','387','389','420','421','423',
    '500','501','502','503','504','505','506','507','508','509',
    '590','591','592','593','594','595','596','597','598','599',
    '670','672','673','674','675','676','677','678','679','680','681','682','683','685','686',
    '687','688','689','690','691','692',
    '850','852','853','855','856','870','880','886',
    '960','961','962','963','964','965','966','967','968','970','971','972','973','974','975',
    '976','977','992','993','994','995','996','998',
    '20','27','30','31','32','33','34','36','39','40','41','43','44','45','46','47','48','49',
    '51','52','53','54','55','56','57','58','60','61','62','63','64','65','66',
    '81','82','84','86','90','91','92','93','94','95','98',
    '7','1',
  ]..sort((a, b) => b.length.compareTo(a.length));

  /// A few countries offered at the top of the picker, by calling code.
  ///
  /// A short list rather than every country on earth: the field accepts a typed
  /// `+` and a code, so the picker is a convenience and a long scroll would be
  /// a worse one.
  static const List<({String code, String name, String flag})> commonCountries = [
    (code: '49', name: 'Deutschland', flag: '🇩🇪'),
    (code: '43', name: 'Österreich', flag: '🇦🇹'),
    (code: '41', name: 'Schweiz', flag: '🇨🇭'),
    (code: '44', name: 'United Kingdom', flag: '🇬🇧'),
    (code: '1', name: 'USA / Canada', flag: '🇺🇸'),
    (code: '33', name: 'France', flag: '🇫🇷'),
    (code: '39', name: 'Italia', flag: '🇮🇹'),
    (code: '34', name: 'España', flag: '🇪🇸'),
    (code: '31', name: 'Nederland', flag: '🇳🇱'),
    (code: '48', name: 'Polska', flag: '🇵🇱'),
    (code: '351', name: 'Portugal', flag: '🇵🇹'),
    (code: '90', name: 'Türkiye', flag: '🇹🇷'),
  ];

  /// Turns what somebody typed into E.164, or null.
  ///
  /// Never guesses a country: a number with no calling code is refused rather
  /// than assumed to be local, because guessing would quietly attach somebody
  /// to a number in a country they have never been to.
  static PhoneNumber? normalise(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final withPlus = trimmed.startsWith('00') ? '+${trimmed.substring(2)}' : trimmed;
    if (!withPlus.startsWith('+')) return null;

    final digits = withPlus.substring(1).replaceAll(RegExp(r'[\s\-().]'), '');
    if (!RegExp(r'^[0-9]{7,15}$').hasMatch(digits)) return null;

    final code = _callingCodes.cast<String?>().firstWhere(
          (candidate) => digits.startsWith(candidate!),
          orElse: () => null,
        );
    if (code == null) return null;
    if (digits.length - code.length < 4) return null;

    return PhoneNumber(
      e164: '+$digits',
      hint: '+$code … ${digits.substring(digits.length - 2)}',
    );
  }

  /// What the server is sent: the number under the public context key.
  ///
  /// HMAC-SHA256 from `package:crypto`, which is the Dart team's own
  /// implementation — nothing here is a primitive this project wrote.
  static String blind(String e164) {
    final mac = crypto.Hmac(crypto.sha256, utf8.encode(discoveryContext));
    return base64.encode(mac.convert(utf8.encode(e164)).bytes);
  }
}
