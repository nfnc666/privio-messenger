import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/message_store.dart';
import '../models/models.dart';
import 'message_text.dart';

/// Somebody a composer can offer while an `@` is being typed.
@immutable
class MentionCandidate {
  const MentionCandidate({
    required this.accountId,
    required this.username,
    required this.displayName,
    this.avatarSeed = 0,
    this.avatarBytes,
  });

  final String accountId;
  final String username;

  /// What to draw as the name. The display name when there is one, and the
  /// username when there is not — the row still has to say who this is.
  final String displayName;

  final int avatarSeed;
  final Uint8List? avatarBytes;

  @override
  bool operator ==(Object other) =>
      other is MentionCandidate && other.accountId == accountId;

  @override
  int get hashCode => accountId.hashCode;
}

/// The `@` being typed, and who to offer for it.
///
/// **There is no lookup here and no request.** Suggestions come from two lists
/// this account already holds: its own address book, and the members of the
/// group it is writing in — which the server decided it may see. Nothing
/// queries a name that has not been typed in full, because a box that answers
/// "who starts with ma" is a tool for reading off the user list, and this app
/// does not have one.
///
/// A name can always be typed out by hand. The suggestions are a convenience,
/// never the only way in — which is what keeps somebody able to mention a
/// person who is in neither list.
abstract final class MentionSuggestions {
  /// How many rows a composer shows at once.
  static const int limit = 6;

  /// The `@word` the caret is inside, or null.
  ///
  /// Only when the caret sits at the end of it: offering names for a word
  /// somebody has moved away from would replace text they are not looking at.
  static ({int start, String query})? activeQuery(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final caret = selection.baseOffset;
    if (caret < 0 || caret > value.text.length) return null;

    final text = value.text;
    var index = caret - 1;
    while (index >= 0) {
      final character = text[index];
      if (character == '@') break;
      // A name has no spaces and no punctuation; hitting either means the
      // caret is not inside one.
      if (!RegExp(r'[A-Za-z0-9_.]').hasMatch(character)) return null;
      index--;
    }
    if (index < 0) return null;
    // The same delimiter rule the tokenizer uses: an `@` in the middle of a
    // word is an address, not the start of a name.
    if (index > 0 && RegExp(r'[A-Za-z0-9_.@/-]').hasMatch(text[index - 1])) {
      return null;
    }
    final query = text.substring(index + 1, caret);
    if (query.length > MessageText.maxUsernameLength) return null;
    return (start: index, query: query.toLowerCase());
  }

  /// Who to offer for [query], from the lists this account already has.
  ///
  /// Matched on the username **and** on the display name, because somebody
  /// typing `@lena` may be thinking of the name they see rather than the one
  /// they have to send. The username is what gets inserted either way.
  static List<MentionCandidate> matches(
    String query, {
    List<Contact> contacts = const [],
    List<GroupMember> members = const [],
    String? excludeAccountId,
  }) {
    final byId = <String, MentionCandidate>{};

    void offer(MentionCandidate candidate) {
      if (candidate.accountId == excludeAccountId) return;
      if (candidate.username == 'unknown') return;
      // A contact wins over a group member with the same id: it carries the
      // avatar this device has already fetched.
      byId.putIfAbsent(candidate.accountId, () => candidate);
    }

    for (final contact in contacts) {
      offer(
        MentionCandidate(
          accountId: contact.id,
          username: contact.username,
          displayName: contact.displayName.isEmpty ? contact.username : contact.displayName,
          avatarSeed: contact.avatarSeed,
          avatarBytes: contact.avatarBytes,
        ),
      );
    }
    for (final member in members) {
      offer(
        MentionCandidate(
          accountId: member.accountId,
          username: member.username,
          displayName: (member.displayName?.isNotEmpty ?? false)
              ? member.displayName!
              : member.username,
        ),
      );
    }

    final needle = query.toLowerCase();
    final hits = byId.values.where((candidate) {
      if (needle.isEmpty) return true;
      return candidate.username.toLowerCase().startsWith(needle) ||
          candidate.displayName.toLowerCase().contains(needle);
    }).toList();

    hits.sort((a, b) {
      // Whoever matches the username from its first character comes first: it
      // is the thing being typed.
      final aPrefix = a.username.toLowerCase().startsWith(needle);
      final bPrefix = b.username.toLowerCase().startsWith(needle);
      if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return hits.take(limit).toList();
  }

  /// Puts [username] in, in place of the `@word` that starts at [start].
  ///
  /// The whole name and a trailing space, so the next word does not become
  /// part of it, and the caret after both.
  static TextEditingValue insert(
    TextEditingValue value,
    int start,
    String username,
  ) {
    final caret = value.selection.baseOffset;
    final inserted = '@$username ';
    final text = value.text.replaceRange(start, caret, inserted);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
  }
}
