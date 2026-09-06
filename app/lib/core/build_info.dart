import 'edition.dart';

/// What this binary is, so an artifact can be traced back to what made it.
///
/// A version number alone does not identify a build: the same version can be
/// compiled from different commits, for different editions, against different
/// servers. When somebody reports that the F-Droid build of 0.1.0 does
/// something the website APK does not, the answer has to be findable.
///
/// Everything here is injected at build time and defaults to a value that is
/// obviously a default. Nothing is guessed: an empty commit reads as "unknown",
/// not as a plausible-looking hash.
class BuildInfo {
  const BuildInfo._();

  /// Semantic version, matching `pubspec.yaml`.
  static const String version = String.fromEnvironment(
    'PRIVIO_VERSION',
    defaultValue: '0.1.0',
  );

  /// The commit this was built from. Set by CI; empty in a local build.
  static const String commit = String.fromEnvironment('PRIVIO_COMMIT');

  /// Which edition, from the same value the rest of the app reads.
  static String get edition => PrivioEdition.current.id;

  /// Short, stable, and safe to show on an about screen or paste into a bug
  /// report. Carries no path, no username and no server address.
  static String get summary {
    final where = commit.isEmpty ? 'local' : commit.substring(0, commit.length.clamp(0, 12));
    return '$version+$edition+$where';
  }

  /// True when this build can be traced to a specific commit.
  ///
  /// A release that cannot is a release nobody can reproduce or bisect, which
  /// is worth being able to assert rather than hope.
  static bool get isTraceable => commit.length >= 7;
}
