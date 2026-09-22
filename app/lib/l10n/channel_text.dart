import 'package:intl/intl.dart';

import '../models/channel.dart';
import '../models/models.dart';
import 'app_localizations.dart';

/// The words for a channel permission, in the reader's language.
///
/// [ChannelPermissions.all] holds only keys now: the label and the line under
/// it used to sit beside them in the model, in English, where nothing could
/// translate them.
String permissionLabel(AppText text, String key) => switch (key) {
      'canEditChannel' => text.permissionEditChannel,
      'canPost' => text.permissionPost,
      'canDeletePosts' => text.permissionDeletePosts,
      'canModerateDiscussion' => text.permissionModerate,
      'canManageMembers' => text.permissionManageMembers,
      'canManageInvites' => text.permissionManageInvites,
      'canManageLivestreams' => text.permissionManageLivestreams,
      'canAppointAdmins' => text.permissionAppointAdmins,
      _ => key,
    };

String permissionDetail(AppText text, String key) => switch (key) {
      'canEditChannel' => text.permissionEditChannelDetail,
      'canPost' => text.permissionPostDetail,
      'canDeletePosts' => text.permissionDeletePostsDetail,
      'canModerateDiscussion' => text.permissionModerateDetail,
      'canManageMembers' => text.permissionManageMembersDetail,
      'canManageInvites' => text.permissionManageInvitesDetail,
      'canManageLivestreams' => text.permissionManageLivestreamsDetail,
      'canAppointAdmins' => text.permissionAppointAdminsDetail,
      _ => '',
    };

/// "online", "last seen 20 minutes ago", or nothing at all.
///
/// The date is formatted for the reader's locale rather than as dd.mm.yy: a
/// date is one of the few things every language writes differently, and `intl`
/// already knows how each of them does it.
String presenceText(AppText text, ChannelPresence presence) {
  if (presence.isUnknown) return '';
  if (presence.isOnline) return text.presenceOnline;
  if (presence.isMinutes) return text.presenceMinutesAgo(presence.count);
  if (presence.isHours) return text.presenceHoursAgo(presence.count);
  if (presence.isDays) return text.presenceDaysAgo(presence.count);
  final on = presence.at!;
  return text.presenceOnDate(formatDate(text, on));
}

/// A date, written the way the reader's language writes dates.
///
/// Falls back to the locale-independent form if the locale's date symbols were
/// never loaded — which happens in a test that did not call
/// `initializeDateFormatting`, and must not take a screen down with it.
String formatDate(AppText text, DateTime at) {
  try {
    return DateFormat.yMd(text.localeName).format(at);
  } on Object {
    return DateFormat.yMd().format(at);
  }
}

/// "4 September" — the day and the month, ordered the way the reader's
/// language orders them.
String formatDayAndMonth(AppText text, DateTime at) {
  try {
    return DateFormat.MMMMd(text.localeName).format(at);
  } on Object {
    return DateFormat.MMMMd().format(at);
  }
}

/// The same, with the year, for a day that is not in this one.
String formatDayMonthYear(AppText text, DateTime at) {
  try {
    return DateFormat.yMMMMd(text.localeName).format(at);
  } on Object {
    return DateFormat.yMMMMd().format(at);
  }
}

/// The wording of a report reason, in the reader's language.
///
/// The enum carries only the value the server is told; the sentence is here.
String reportReasonLabel(AppText text, ReportReason reason) =>
    switch (reason) {
      ReportReason.spam => text.reportSpam,
      ReportReason.abuse => text.reportAbuse,
      ReportReason.illegal => text.reportIllegal,
      ReportReason.impersonation => text.reportImpersonation,
      ReportReason.other => text.reportOther,
    };
