import '../models/models.dart';
import 'app_localizations.dart';

/// Turning a stored [SystemNotice] into a sentence, in the reader's language.
///
/// This is the other half of storing notices as events: the writer records what
/// happened, and this builds the words at the moment they are drawn. Two people
/// in the same chat with the app set to different languages each see the notice
/// in their own — from one stored fact, not two.
String describeNotice(AppText text, SystemNotice notice) {
  // Null is this account. Every language has its own word for it, and the
  // account's own name would read wrong in all of them.
  final who = notice.who ?? text.noticeYou;
  return switch (notice.kind) {
    NoticeKind.timerSet => text.noticeTimerSetBy(
        who,
        describeDuration(text, notice.duration ?? Duration.zero),
      ),
    NoticeKind.timerOff => text.noticeTimerOffBy(who),
    NoticeKind.unreadable => notice.who == null
        ? text.noticeUnreadable(notice.count ?? 1)
        : text.noticeUnreadableFrom(notice.count ?? 1, notice.who!),
  };
}

/// How a timer reads in a sentence, in the reader's language.
///
/// The same largest-whole-unit rule the English version always used, with the
/// plural forms left to ICU: "1 Stunde" and "2 Stunden" are not a suffix apart
/// in every language, and picking the wording in Dart would have hard-coded
/// English's idea of what a plural is.
String describeDuration(AppText text, Duration timer) {
  if (timer.inDays >= 7 && timer.inDays % 7 == 0) {
    return text.durationWeeks(timer.inDays ~/ 7);
  }
  if (timer.inHours >= 24 && timer.inHours % 24 == 0) {
    return text.durationDays(timer.inDays);
  }
  if (timer.inMinutes >= 60 && timer.inMinutes % 60 == 0) {
    return text.durationHours(timer.inHours);
  }
  if (timer.inSeconds >= 60 && timer.inSeconds % 60 == 0) {
    return text.durationMinutes(timer.inMinutes);
  }
  return text.durationSeconds(timer.inSeconds);
}
