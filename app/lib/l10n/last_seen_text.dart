import '../models/last_seen.dart';
import 'app_localizations.dart';
import 'channel_text.dart' show formatDate;

/// When somebody was last active, in words — every place the app says it.
///
/// One file because it is one fact, said three ways: a channel member's line,
/// a contact's, and a device's. Each is to the hour, because that is what the
/// server keeps (migration 044), and none of them says "online" or counts
/// minutes, which would present a guess as a fact.

/// "last seen within the last hour", "last seen 5 hours ago", or nothing at
/// all.
///
/// The date is formatted for the reader's locale rather than as dd.mm.yy: a
/// date is one of the few things every language writes differently, and `intl`
/// already knows how each of them does it.
String presenceText(AppText text, LastSeen presence) {
  if (presence.isUnknown) return '';
  if (presence.isWithinTheHour) return text.presenceWithinHour;
  if (presence.isHours) return text.presenceHoursAgo(presence.count);
  if (presence.isDays) return text.presenceDaysAgo(presence.count);
  return text.presenceOnDate(formatDate(text, presence.at!));
}

/// The short form, for "@bob · last seen {when}": "within the last hour",
/// "5 h ago", "3d ago", or the date. Empty where they do not share it.
String seenWhen(AppText text, LastSeen seen) {
  if (seen.isUnknown) return '';
  if (seen.isWithinTheHour) return text.contactsSeenWithinHour;
  if (seen.isHours) return text.contactsSeenHours(seen.count);
  if (seen.isDays) return text.contactsSeenDays(seen.count);
  return formatDate(text, seen.at!);
}

/// One of your own devices, in the list of them: "Active within the last
/// hour", "Active 5 h ago", "Active yesterday", "Active 12 days ago".
///
/// Coarse on purpose. "Last active: 14:32" on a device you do not recognise
/// invites a precision this list cannot honestly offer — the server records
/// when it last spoke, not when someone last read anything. Never a date: a
/// date would make an old phone look like an appointment.
String deviceActivityText(AppText text, DateTime? lastSeenAt, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final seen = LastSeen.of(lastSeenAt, now: at);
  if (seen.isUnknown) return text.devicesSignedIn;
  if (seen.isWithinTheHour) return text.devicesActiveWithinHour;
  if (seen.isHours) return text.devicesActiveHours(seen.count);
  if (seen.isDays && seen.count == 1) return text.devicesActiveYesterday;
  if (seen.isDays) return text.devicesActiveDays(seen.count);
  return text.devicesActiveDays(at.difference(seen.at!).inDays);
}
