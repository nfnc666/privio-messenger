import 'package:flutter/foundation.dart';

/// When somebody was last active, as precisely as the server knows it: to the
/// hour.
///
/// The server keeps activity to the hour (migration 044). What it reports is
/// the start of the hour in which somebody was last active, so this never says
/// "online" or "five minutes ago" — the app would be presenting a guess as a
/// fact about somebody else. It says "within the hour", then hours, then days,
/// then the date.
///
/// A fact with a shape, not a sentence: the words differ per language and per
/// screen, and this is produced by a model that knows neither.
/// `l10n/last_seen_text.dart` turns it into words.
@immutable
class LastSeen {
  const LastSeen.unknown() : kind = LastSeenKind.unknown, count = 0, at = null;
  const LastSeen.withinTheHour() : kind = LastSeenKind.withinTheHour, count = 0, at = null;
  const LastSeen.hours(this.count) : kind = LastSeenKind.hours, at = null;
  const LastSeen.days(this.count) : kind = LastSeenKind.days, at = null;
  const LastSeen.on(DateTime this.at) : kind = LastSeenKind.onDate, count = 0;

  /// How long ago [seen] was, in the steps the server's precision allows.
  ///
  /// A moment slightly in the future — this device's clock behind the
  /// server's — counts as within the hour rather than as nothing.
  factory LastSeen.of(DateTime? seen, {DateTime? now}) {
    if (seen == null) return const LastSeen.unknown();
    final ago = (now ?? DateTime.now()).difference(seen);
    if (ago.inHours < 1) return const LastSeen.withinTheHour();
    if (ago.inHours < 24) return LastSeen.hours(ago.inHours);
    if (ago.inDays < 7) return LastSeen.days(ago.inDays);
    return LastSeen.on(seen);
  }

  final LastSeenKind kind;
  final int count;
  final DateTime? at;

  /// True when they share nothing. Not knowing is not the same as knowing it
  /// was long ago, so the row shows nothing rather than a guess.
  bool get isUnknown => kind == LastSeenKind.unknown;
  bool get isWithinTheHour => kind == LastSeenKind.withinTheHour;
  bool get isHours => kind == LastSeenKind.hours;
  bool get isDays => kind == LastSeenKind.days;

  @override
  bool operator ==(Object other) =>
      other is LastSeen && other.kind == kind && other.count == count && other.at == at;

  @override
  int get hashCode => Object.hash(kind, count, at);

  @override
  String toString() => 'LastSeen($kind, $count, $at)';
}

/// Public only because it names [LastSeen.kind]; nothing outside switches on
/// it.
enum LastSeenKind { unknown, withinTheHour, hours, days, onDate }
