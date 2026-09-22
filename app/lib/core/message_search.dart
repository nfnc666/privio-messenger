import 'package:flutter/foundation.dart';

import '../data/message_store.dart';
import '../models/models.dart';

/// One message that matched a search, and where it lives.
@immutable
class SearchHit {
  const SearchHit({
    required this.conversationId,
    required this.title,
    required this.isGroup,
    required this.message,
    required this.matchStart,
    required this.matchEnd,
    this.inFileName = false,
  });

  final String conversationId;
  final String title;
  final bool isGroup;
  final Message message;

  /// Where the query sits inside the matched text, so the row can show the
  /// match itself rather than the first line of a long message.
  final int matchStart;
  final int matchEnd;

  /// Whether the match is in the attachment's file name rather than in the
  /// body. The offsets index into that name, so a row must know which string
  /// it is holding before it slices one.
  final bool inFileName;

  /// The text the offsets belong to.
  String get matched =>
      inFileName ? message.attachment?.fileName ?? '' : message.body;
}

/// Searching the history.
///
/// It runs here, over messages this device already decrypted, because there is
/// nowhere else it could run: the server holds ciphertext it cannot read, so it
/// could not answer a query even if one were sent — and sending one would tell
/// it what someone is looking for, which is close to telling it what they
/// talked about.
///
/// Split out from the controller so it can be tested as what it is: a pure
/// function over a list of conversations.
abstract final class MessageSearch {
  /// How much of the message to show around the match.
  static const int _window = 48;

  /// Matches in [conversations], newest first, at most [limit].
  ///
  /// Case-insensitive substring matching, which is what a person means by
  /// search here. Nothing is indexed: a history that fits in a phone's memory
  /// is a history a loop can walk, and an index would be a second copy of the
  /// conversation to keep encrypted, in step, and out of a backup.
  static List<SearchHit> run(
    List<Conversation> conversations,
    String query, {
    int limit = 200,
    DateTime? now,
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final asOf = now ?? DateTime.now();
    final hits = <SearchHit>[];
    for (final conversation in conversations) {
      for (final message in conversation.messages) {
        // A tombstone has nothing left in it to match.
        if (message.kind == MessageKind.deleted) continue;
        // A message whose time has run out, checked here rather than trusted to
        // have been swept. The sweep runs every few seconds, and in the gap
        // between expiry and the next pass the message is still in the store —
        // search must not be the one place it surfaces after it was meant to
        // be gone.
        if (message.hasExpiredAt(asOf)) continue;
        // A notice is the app talking about the chat, not something anyone
        // wrote in it. Matching it would put "disappearing messages" in the
        // results for every chat that ever had a timer.
        if (message.isNotice) continue;
        final at = message.body.toLowerCase().indexOf(needle);
        if (at != -1) {
          hits.add(
            SearchHit(
              conversationId: conversation.id,
              title: conversation.title,
              isGroup: conversation.isGroup,
              message: message,
              matchStart: at,
              matchEnd: at + needle.length,
            ),
          );
          continue;
        }

        // The file name. The comment that used to sit at the top of this loop
        // said an attachment's name was "already covered by what is or is not
        // in `body`" — it is not: `body` holds the caption, and a file sent
        // without one has an empty body and a name nobody could search for.
        // Looking for a document by its name is most of what searching a
        // notebook is.
        final fileName = message.attachment?.fileName;
        final inName = fileName == null ? -1 : fileName.toLowerCase().indexOf(needle);
        if (inName == -1) continue;
        hits.add(
          SearchHit(
            conversationId: conversation.id,
            title: conversation.title,
            isGroup: conversation.isGroup,
            message: message,
            matchStart: inName,
            matchEnd: inName + needle.length,
            inFileName: true,
          ),
        );
      }
    }

    hits.sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
    return hits.length <= limit ? hits : hits.sublist(0, limit);
  }

  /// The line a result row shows: the match, with enough either side to read
  /// it, and an ellipsis where the message was cut.
  static ({String text, int start, int end}) snippet(SearchHit hit) {
    final body = hit.matched;
    if (body.length <= _window * 2) {
      return (text: body, start: hit.matchStart, end: hit.matchEnd);
    }

    var from = hit.matchStart - _window ~/ 2;
    if (from < 0) from = 0;
    var to = from + _window * 2;
    if (to > body.length) {
      to = body.length;
      from = to - _window * 2;
    }

    final head = from > 0 ? '…' : '';
    final tail = to < body.length ? '…' : '';
    return (
      text: '$head${body.substring(from, to)}$tail',
      start: hit.matchStart - from + head.length,
      end: hit.matchEnd - from + head.length,
    );
  }
}
