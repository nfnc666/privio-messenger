import 'package:flutter/material.dart' show DateUtils;
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

/// "Today at 18:30", "Tomorrow at 09:00", or the date.
String formatWhenLabel(AppText text, DateTime when) {
  final today = DateUtils.dateOnly(DateTime.now());
  final day = DateUtils.dateOnly(when);
  final hh = when.hour.toString().padLeft(2, '0');
  final mm = when.minute.toString().padLeft(2, '0');
  final clock = '$hh:$mm';
  final difference = day.difference(today).inDays;
  if (difference == 0) return text.feedTodayAt(clock);
  if (difference == 1) return text.feedTomorrowAt(clock);
  return text.feedDateAt(formatDayAndMonth(text, when), clock);
}
