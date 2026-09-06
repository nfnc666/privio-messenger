/// Which build of Privio this is.
///
/// Privio ships from one source tree through four channels, and they differ in
/// exactly two ways: how the app was paid for, and whether the binary is
/// allowed to contain anything that is not free software. Everything else —
/// the protocol, the crypto, the screens — is identical, and that is the
/// point. `libre` is not a cut-down build; it is the same app without the
/// store's plumbing.
enum PrivioDistribution {
  /// F-Droid. Free software only, activated with a license key.
  libre,

  /// The APK downloaded from getprivio.com. Same binary contents as [libre],
  /// different signing and update path.
  direct,

  /// Google Play. Paid for through Play Billing.
  play,

  /// Apple App Store. Paid for through the App Store.
  appStore,
}

/// Build-time facts about this binary.
///
/// Set with `--dart-define=PRIVIO_EDITION=<id>` at build time, alongside the
/// matching Android flavour (`--flavor libre|play`). An unrecognised or
/// missing value falls back to [libre], because the free build is the one
/// someone gets when they clone this repository and run `flutter build`.
class PrivioEdition {
  const PrivioEdition._(
    this.distribution, {
    required this.id,
    required this.name,
    required this.usesLicenseKey,
    required this.pushProvider,
  });

  static const _libre = PrivioEdition._(
    PrivioDistribution.libre,
    id: 'libre',
    name: 'Privio Libre',
    usesLicenseKey: true,
    pushProvider: 'unifiedpush',
  );

  static const _direct = PrivioEdition._(
    PrivioDistribution.direct,
    id: 'direct',
    name: 'Privio',
    usesLicenseKey: true,
    pushProvider: 'unifiedpush',
  );

  static const _play = PrivioEdition._(
    PrivioDistribution.play,
    id: 'play',
    name: 'Privio',
    usesLicenseKey: false,
    pushProvider: 'fcm',
  );

  static const _appStore = PrivioEdition._(
    PrivioDistribution.appStore,
    id: 'appstore',
    name: 'Privio',
    usesLicenseKey: false,
    pushProvider: 'apns',
  );

  static const List<PrivioEdition> all = [_libre, _direct, _play, _appStore];

  /// What this build calls itself in the launcher and on the about screen.
  final String name;

  /// Stable identifier, matching the `--dart-define` value and the Gradle
  /// flavour where there is one.
  final String id;

  final PrivioDistribution distribution;

  /// Whether activation happens with a key bought on the website. The store
  /// builds are paid for in the store instead.
  ///
  /// This decides what the activation screen offers, not who gets served: the
  /// server alone decides that, and it may not require a license at all.
  final bool usesLicenseKey;

  /// The wake-up service this build may talk to, or null for none.
  ///
  /// The free builds use UnifiedPush: the endpoint belongs to a distributor
  /// app the user chose and often runs themselves, so waking the phone costs
  /// neither a proprietary dependency nor a fixed third party. Where no
  /// distributor is installed the app falls back to its own socket, which is
  /// what it did everywhere before.
  ///
  /// Whichever it is, the payload is a wake-up and nothing else.
  final String? pushProvider;

  /// True for the builds that contain nothing but free software, and can
  /// therefore be reproduced from this repository by anyone.
  ///
  /// Two editions qualify and they are **not** the same product. `libre` is
  /// what F-Droid ships and it is called "Privio Libre"; `direct` is the APK
  /// from the website, called "Privio", carrying a licence key and updating
  /// itself outside any store. They share every dependency and every line of
  /// code — the difference is the name, the update path and who signs it.
  ///
  /// Named for what it asserts rather than after one of the two editions,
  /// because `isLibre` returning true for the build called "Privio" was read
  /// as "this is the Libre product" more than once.
  bool get containsOnlyFreeSoftware =>
      distribution == PrivioDistribution.libre || distribution == PrivioDistribution.direct;

  /// True only for the F-Droid product, which is the one allowed to call
  /// itself Libre.
  bool get isLibreProduct => distribution == PrivioDistribution.libre;

  /// True where the binary is allowed to link a proprietary SDK.
  bool get usesProprietaryServices => !containsOnlyFreeSoftware;

  /// Which Android product flavour this edition must be built with.
  ///
  /// Null for the App Store build, which has no Android side at all. The two
  /// free editions have a flavour each rather than sharing one: they contain
  /// the same code but must not carry the same name, and a build that says
  /// "Privio Libre" on the home screen while the Dart side believes it is the
  /// website APK is the sort of mismatch nobody notices until an update fails.
  String? get androidFlavour => switch (distribution) {
        PrivioDistribution.libre => 'libre',
        PrivioDistribution.direct => 'direct',
        PrivioDistribution.play => 'play',
        PrivioDistribution.appStore => null,
      };

  /// Whether this edition can be built for the given platform flavour at all.
  ///
  /// The check exists because the two halves of a build are configured
  /// separately — Gradle picks the flavour, `--dart-define` picks the edition —
  /// and nothing stopped them disagreeing. `--flavor libre
  /// --dart-define=PRIVIO_EDITION=direct` produced an APK named "Privio Libre"
  /// that reported itself as the website build, offered the wrong update path,
  /// and would have been rejected by F-Droid.
  static bool isConsistent({required String flavour, required String editionId}) {
    final edition = tryParse(editionId);
    return edition != null && edition.androidFlavour == flavour;
  }

  static const String licenseSpdxId = 'AGPL-3.0-only';
  static const String licenseName = 'GNU Affero General Public License v3.0';
  static const String sourceUrl = 'https://github.com/nfnc666/privio-libre-open-source-fdroid';

  static const String _configured = String.fromEnvironment('PRIVIO_EDITION');

  /// Whether this binary was compiled in release mode.
  ///
  /// Read once here rather than at every call site, and exposed so a test can
  /// drive both sides of the rule below without building twice.
  static const bool isReleaseBuild = bool.fromEnvironment('dart.vm.product');

  /// The edition this binary was built as.
  static final PrivioEdition current = resolve(_configured, release: isReleaseBuild);

  /// Resolves an edition id, or null if it names nothing.
  static PrivioEdition? tryParse(String id) {
    final wanted = id.trim().toLowerCase();
    for (final edition in all) {
      if (edition.id == wanted) return edition;
    }
    return null;
  }

  /// Resolves an edition id, falling back to Libre for anything unknown.
  ///
  /// Kept for callers that are parsing a value from somewhere other than the
  /// build — a server response, a stored preference — where a wrong answer is
  /// better than an exception. The build's own edition goes through [resolve].
  static PrivioEdition parse(String id) => tryParse(id) ?? _libre;

  /// The edition of *this build*, refusing to guess in a release.
  ///
  /// A debug build with no edition set is somebody running `flutter test` or
  /// `flutter run`, and defaulting to Libre there is convenient and harmless.
  /// A **release** build with no edition, or with one that names nothing, is a
  /// build script that is wrong — and quietly shipping it as Libre is the worst
  /// available outcome: an App Store binary that reports itself as free
  /// software, offers a licence-key screen it should not have, and registers
  /// for a push service it does not contain. It used to do exactly that.
  ///
  /// So a release refuses. The failure is at first touch of [current], which is
  /// during start-up, and it names the value it was given.
  static PrivioEdition resolve(String id, {required bool release}) {
    final found = tryParse(id);
    if (found != null) return found;
    if (!release) return _libre;
    throw StateError(
      'PRIVIO_EDITION was "$id", which is not one of '
      '${all.map((e) => e.id).join(', ')}. A release build must be told which '
      'edition it is; falling back to libre would ship a store binary claiming '
      'to be free software.',
    );
  }

  @override
  String toString() => 'PrivioEdition($id)';
}
