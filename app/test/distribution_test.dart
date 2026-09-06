import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/build_info.dart';
import 'package:privio/core/edition.dart';

/// The four distributions, asserted rather than described.
///
/// Every row of this is something a build script can get wrong in a way that
/// only shows up after somebody has installed the result: a store binary that
/// says it is free software, an F-Droid build that registers for Firebase, a
/// website APK labelled "Privio Libre" that cannot be updated from the website.
void main() {
  group('the distribution matrix', () {
    const expected = {
      'libre': (
        name: 'Privio Libre',
        push: 'unifiedpush',
        key: true,
        free: true,
        flavour: 'libre',
      ),
      'direct': (
        name: 'Privio',
        push: 'unifiedpush',
        key: true,
        free: true,
        flavour: 'direct',
      ),
      'play': (name: 'Privio', push: 'fcm', key: false, free: false, flavour: 'play'),
      'appstore': (name: 'Privio', push: 'apns', key: false, free: false, flavour: null),
    };

    for (final entry in expected.entries) {
      test('${entry.key} is named, pushed and paid for as agreed', () {
        final edition = PrivioEdition.parse(entry.key);
        expect(edition.id, entry.key);
        expect(edition.name, entry.value.name);
        expect(edition.pushProvider, entry.value.push);
        expect(edition.usesLicenseKey, entry.value.key);
        expect(edition.containsOnlyFreeSoftware, entry.value.free);
        expect(edition.androidFlavour, entry.value.flavour);
      });
    }

    test('every edition is covered, so a new one cannot slip through untested', () {
      expect(
        PrivioEdition.all.map((e) => e.id).toSet(),
        expected.keys.toSet(),
      );
    });

    test('only F-Droid ships the product called Libre', () {
      // The distinction that was missing: `direct` contains nothing
      // proprietary and is still not the Libre product.
      expect(PrivioEdition.parse('libre').isLibreProduct, isTrue);
      expect(PrivioEdition.parse('direct').isLibreProduct, isFalse);
      expect(PrivioEdition.parse('direct').containsOnlyFreeSoftware, isTrue);
      expect(PrivioEdition.parse('direct').name, isNot(contains('Libre')));
    });

    test('the two free editions are the same app under different names', () {
      final libre = PrivioEdition.parse('libre');
      final direct = PrivioEdition.parse('direct');
      expect(direct.pushProvider, libre.pushProvider);
      expect(direct.usesLicenseKey, libre.usesLicenseKey);
      expect(direct.usesProprietaryServices, libre.usesProprietaryServices);
      expect(direct.name, isNot(libre.name));
    });

    test('no free edition may use a proprietary push service', () {
      // The guarantee F-Droid is given, and the reason `direct` can be built
      // from the same source without a Google account.
      for (final edition in PrivioEdition.all.where((e) => e.containsOnlyFreeSoftware)) {
        expect(edition.pushProvider, 'unifiedpush', reason: edition.id);
        expect(edition.usesProprietaryServices, isFalse, reason: edition.id);
      }
    });

    test('a store build is never shown a licence key field', () {
      // It was paid for when it was installed. Asking for a key as well would
      // be charging twice for the same thing.
      for (final id in ['play', 'appstore']) {
        expect(PrivioEdition.parse(id).usesLicenseKey, isFalse, reason: id);
      }
    });
  });

  group('refusing a build that does not know what it is', () {
    test('a release with no edition set fails rather than shipping as Libre', () {
      // The old behaviour: an App Store binary with a typo'd build script
      // silently reported itself as free software, offered a key screen it
      // should not have, and registered for a push service it did not contain.
      expect(
        () => PrivioEdition.resolve('', release: true),
        throwsA(isA<StateError>()),
      );
      expect(
        () => PrivioEdition.resolve('apstore', release: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('apstore'), contains('libre')),
          ),
        ),
      );
    });

    test('a debug build still defaults, so tests and flutter run keep working', () {
      expect(PrivioEdition.resolve('', release: false).id, 'libre');
      expect(PrivioEdition.resolve('nonsense', release: false).id, 'libre');
    });

    test('a release with a real edition resolves normally', () {
      for (final edition in PrivioEdition.all) {
        expect(PrivioEdition.resolve(edition.id, release: true).id, edition.id);
      }
      // And tolerates how a build script might actually write it.
      expect(PrivioEdition.resolve('  AppStore ', release: true).id, 'appstore');
    });
  });

  group('refusing a flavour and an edition that disagree', () {
    test('the matching pairs are accepted', () {
      for (final edition in PrivioEdition.all) {
        final flavour = edition.androidFlavour;
        if (flavour == null) continue;
        expect(
          PrivioEdition.isConsistent(flavour: flavour, editionId: edition.id),
          isTrue,
          reason: edition.id,
        );
      }
    });

    test('the combination that shipped the wrong product is refused', () {
      // `--flavor libre --dart-define=PRIVIO_EDITION=play` was an ordinary
      // command that produced an APK named "Privio Libre", containing no
      // Firebase, whose Dart side registered for FCM.
      expect(PrivioEdition.isConsistent(flavour: 'libre', editionId: 'play'), isFalse);
      expect(PrivioEdition.isConsistent(flavour: 'libre', editionId: 'direct'), isFalse);
      expect(PrivioEdition.isConsistent(flavour: 'direct', editionId: 'libre'), isFalse);
      expect(PrivioEdition.isConsistent(flavour: 'play', editionId: 'libre'), isFalse);
    });

    test('the App Store edition has no Android flavour to be built with', () {
      expect(PrivioEdition.parse('appstore').androidFlavour, isNull);
      for (final flavour in ['libre', 'direct', 'play']) {
        expect(
          PrivioEdition.isConsistent(flavour: flavour, editionId: 'appstore'),
          isFalse,
          reason: flavour,
        );
      }
    });

    test('an unknown edition is never consistent with anything', () {
      expect(PrivioEdition.isConsistent(flavour: 'libre', editionId: ''), isFalse);
      expect(PrivioEdition.isConsistent(flavour: 'libre', editionId: 'libree'), isFalse);
    });
  });

  group('build provenance', () {
    test('a build with no commit says so rather than inventing one', () {
      // In a local build the define is unset. The summary has to be honest
      // about that: a plausible-looking hash that matches nothing is worse than
      // the word "local".
      expect(BuildInfo.commit, isEmpty, reason: 'not set when running tests');
      expect(BuildInfo.isTraceable, isFalse);
      expect(BuildInfo.summary, endsWith('local'));
    });

    test('the summary names the version, the edition and where it came from', () {
      // The three things a bug report needs and none of the things it must not
      // carry: no path, no username, no server address.
      expect(BuildInfo.summary, contains(BuildInfo.version));
      expect(BuildInfo.summary, contains(PrivioEdition.current.id));
      expect(BuildInfo.summary.split('+'), hasLength(3));
    });
  });
}
