import 'package:intl/intl.dart';

import '../models/models.dart';
import 'app_localizations.dart';
import 'notice_text.dart';

/// The last line of a chat row, in the reader's language.
///
/// Everything a person typed — the message, the file name — comes through
/// untouched. Only the app's own words are translated, which is the rule the
/// whole language feature rests on.
String previewWords(AppText text, ChatPreview preview) => switch (preview.kind) {
      ChatPreviewKind.empty => '',
      ChatPreviewKind.savedEmpty => text.savedEmptyPreview,
      ChatPreviewKind.typing => text.chatTyping,
      ChatPreviewKind.deleted => text.chatsPreviewDeleted,
      ChatPreviewKind.body => preview.text ?? '',
      ChatPreviewKind.notice =>
        preview.notice == null ? '' : describeNotice(text, preview.notice!),
      ChatPreviewKind.photo => text.chatsPreviewPhoto,
      ChatPreviewKind.video => text.chatsPreviewVideo,
      ChatPreviewKind.voice => text.chatsPreviewVoice,
      ChatPreviewKind.file => text.chatsPreviewFile,
    };

/// When the last message arrived, written the way the reader's language writes
/// it: 24-hour or am/pm, day-first or month-first, all from `intl`.
String stampWords(AppText text, ChatStamp stamp) => switch (stamp.kind) {
      ChatStampKind.none => '',
      ChatStampKind.yesterday => text.dayYesterday,
      ChatStampKind.time => _format(() => DateFormat.Hm(text.localeName), stamp.at!),
      ChatStampKind.date => _format(() => DateFormat.Md(text.localeName), stamp.at!),
    };

/// Falls back to the locale-independent format rather than throwing: a phone
/// whose date symbols did not load should still show a time.
String _format(DateFormat Function() build, DateTime at) {
  try {
    return build().format(at);
  } on Object {
    return DateFormat.Hm().format(at);
  }
}

/// A date and a time together, the way the reader's language writes both.
///
/// Used by the security activity list, where "yesterday" is not enough: the
/// question somebody brings to that screen is *when exactly* a device was
/// linked, and an answer that says "14:32" with no date cannot be checked
/// against anything.
String formatEventTime(AppText text, DateTime at) {
  final day = _format(() => DateFormat.yMMMd(text.localeName), at);
  final time = _format(() => DateFormat.Hm(text.localeName), at);
  return '$day · $time';
}
