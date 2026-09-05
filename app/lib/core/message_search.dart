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
  });

  final String conversationId;
  final String title;
  final bool isGroup;
  final Message message;

  /// Where the query sits inside [Message.body], so the row can show the match
  /// itself rather than the first line of a long message.
  final int matchStart;
  final int matchEnd;
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
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final hits = <SearchHit>[];
    for (final conversation in conversations) {
      for (final message in conversation.messages) {
        // A tombstone has no body, and an attachment's file name is the
        // sender's own — both are already covered by what is or is not in
        // `body`, so there is one thing to match against.
        if (message.kind == MessageKind.deleted) continue;
        // A notice is the app talking about the chat, not something anyone
        // wrote in it. Matching it would put "disappearing messages" in the
        // results for every chat that ever had a timer.
        if (message.isNotice) continue;
        final at = message.body.toLowerCase().indexOf(needle);
        if (at == -1) continue;
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
      }
    }

    hits.sort((a, b) => b.message.sentAt.compareTo(a.message.sentAt));
    return hits.length <= limit ? hits : hits.sublist(0, limit);
  }

  /// The line a result row shows: the match, with enough either side to read
  /// it, and an ellipsis where the message was cut.
  static ({String text, int start, int end}) snippet(SearchHit hit) {
    final body = hit.message.body;
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
