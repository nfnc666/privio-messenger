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

  /// The APK downloaded from privio.com. Same binary contents as [libre],
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
    pushProvider: null,
  );

  static const _direct = PrivioEdition._(
    PrivioDistribution.direct,
    id: 'direct',
    name: 'Privio',
    usesLicenseKey: true,
    pushProvider: null,
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
  /// Null is not a missing feature to be filled in later for [libre]: a push
  /// service is a third party that learns when a device is being messaged, and
  /// on F-Droid it would also be a proprietary dependency. The Libre build
  /// stays on its own socket while it is running, and that is the trade.
  final String? pushProvider;

  /// True for the builds that contain nothing but free software, and can
  /// therefore be reproduced from this repository by anyone.
  bool get isLibre =>
      distribution == PrivioDistribution.libre || distribution == PrivioDistribution.direct;

  /// True where the binary is allowed to link a proprietary SDK.
  bool get usesProprietaryServices => !isLibre;

  static const String licenseSpdxId = 'AGPL-3.0-only';
  static const String licenseName = 'GNU Affero General Public License v3.0';
  static const String sourceUrl = 'https://github.com/privio/privio-messenger';

  static const String _configured =
      String.fromEnvironment('PRIVIO_EDITION', defaultValue: 'libre');

  /// The edition this binary was built as.
  static final PrivioEdition current = parse(_configured);

  /// Resolves an edition id, falling back to Libre for anything unknown.
  ///
  /// Falling back rather than throwing is deliberate: a typo in a build script
  /// must not produce an app that crashes on launch, and claiming *less* than
  /// the truth about a build is the safe direction to be wrong in.
  static PrivioEdition parse(String id) {
    final wanted = id.trim().toLowerCase();
    for (final edition in all) {
      if (edition.id == wanted) return edition;
    }
    return _libre;
  }

  @override
  String toString() => 'PrivioEdition($id)';
}
