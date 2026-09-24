import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/failure.dart';
import '../core/mention_resolver.dart';
import '../core/message_text.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../screens/contact_profile_screen.dart';
import '../theme/accent.dart';

/// Opening the profile behind an `@name`.
///
/// One function, called from every place a mention can be drawn, so that the
/// chat, the group, a channel post and a photo caption cannot end up doing
/// three different things with the same tap.
///
/// The name is resolved **now**, not when the message was read, and the profile
/// is opened by the **account id** the server answered with — never by the
/// name, and never by a display name, which anybody may choose and two people
/// may share.
Future<void> openMention(
  BuildContext context,
  String username, {
  /// The account whose one-to-one chat this tap came from, when it came from
  /// one. A mention of that same person then offers to go back to the chat
  /// already underneath rather than opening a second copy of it.
  String? fromChatWith,
}) async {
  final state = PrivioScope.maybeOf(context);
  if (state == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final text = AppText.of(context);

  final result = await MentionResolver(state.services.api).resolve(username);
  if (!context.mounted) return;

  switch (result) {
    case MentionFound(:final accountId):
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ContactProfileScreen(
            accountId: accountId,
            returnToChat: accountId == fromChatWith,
          ),
        ),
      );
    case MentionUnknown():
      messenger.showSnackBar(
        SnackBar(content: Text(const Failure(FailureKind.mentionUnknownUser).words(text))),
      );
    case MentionUnavailable(:final kind):
      messenger.showSnackBar(SnackBar(content: Text(Failure(kind).words(text))));
  }
}

/// The spans an `@name` is drawn as, and the recognizers that make it tappable.
///
/// Held by a widget rather than built inside `build`, because a
/// `TapGestureRecognizer` created during a build is never disposed and keeps
/// its place in the gesture arena — a message list that rebuilds on every
/// arriving message would leak one per mention per rebuild.
class MentionRecognizers {
  MentionRecognizers();

  final Map<int, TapGestureRecognizer> _byStart = {};

  /// Makes a recognizer for the mention starting at [key], replacing whatever
  /// was there.
  TapGestureRecognizer forMention(int key, VoidCallback onTap) {
    _byStart[key]?.dispose();
    return _byStart[key] = TapGestureRecognizer()..onTap = onTap;
  }

  /// Whether anything is held. Lets a caller skip rebuilding when nothing
  /// changed.
  bool get isEmpty => _byStart.isEmpty;

  void clear() {
    for (final recognizer in _byStart.values) {
      recognizer.dispose();
    }
    _byStart.clear();
  }
}

/// How a mention is painted: the account's accent, and nothing else.
///
/// No underline. A mention is a name, and a name with a line under it reads as
/// a web address — which is the one thing this must not be mistaken for, since
/// the two behave completely differently when tapped.
TextStyle mentionStyle(BuildContext context, TextStyle? base) =>
    (base ?? const TextStyle()).copyWith(
      color: context.accents.accent,
      fontWeight: FontWeight.w600,
    );

/// Builds the spans for [runs], drawing mentions as tappable and everything
/// else through [plain].
///
/// [plain] exists because the two callers differ in what a non-mention run is:
/// in a chat bubble it may contain custom emoji pictures, in a channel post it
/// may contain links. Mentions are the part they share, and this is the only
/// copy of it.
List<InlineSpan> mentionSpans({
  required BuildContext context,
  required List<TextRun> runs,
  required MentionRecognizers recognizers,
  required List<InlineSpan> Function(TextRun run) plain,
  required void Function(String username) onTap,
  TextStyle? style,
}) {
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final run in runs) {
    if (run.kind == TextRunKind.mention) {
      final username = run.username!;
      spans.add(
        TextSpan(
          text: run.text,
          style: mentionStyle(context, style),
          recognizer: recognizers.forMention(offset, () => onTap(username)),
        ),
      );
    } else {
      spans.addAll(plain(run));
    }
    offset += run.text.length;
  }
  return spans;
}
