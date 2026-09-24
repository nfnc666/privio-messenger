import 'package:flutter/foundation.dart';

/// What a run of message text is.
enum TextRunKind {
  /// Ordinary characters. Drawn as they were written.
  plain,

  /// A web address.
  link,

  /// An `@username`.
  mention,
}

/// One run of a message, as the screen will draw it.
@immutable
class TextRun {
  const TextRun(this.kind, this.text, {this.username});

  final TextRunKind kind;

  /// Exactly the characters this run covers in the source, so concatenating
  /// every run's [text] gives the message back unchanged. That is the property
  /// selection and copying depend on.
  final String text;

  /// For a [TextRunKind.mention], the name to resolve: lower-cased, without the
  /// `@`.
  ///
  /// Separate from [text] because the two differ — somebody writing `@Max`
  /// should see what they typed and reach the account stored as `max`.
  /// Usernames are stored lower-case and cannot differ by case alone, so this
  /// is a normalisation and not a guess.
  final String? username;

  @override
  bool operator ==(Object other) =>
      other is TextRun &&
      other.kind == kind &&
      other.text == text &&
      other.username == username;

  @override
  int get hashCode => Object.hash(kind, text, username);

  @override
  String toString() => '${kind.name}($text${username == null ? '' : ' -> $username'})';
}

/// Taking a message apart into the runs a screen draws differently.
///
/// **One tokenizer for links and mentions**, because they compete for the same
/// characters and two passes would disagree about who owns them. `@` inside a
/// URL is part of the URL; a link inside a code block is not a link; and the
/// only way to be sure of that is to decide it in one place, with an order.
///
/// It runs **locally, on plaintext that has already been decrypted**. No text
/// is sent anywhere to find out what is in it, and nothing here asks the server
/// whether a name exists — an unknown `@name` is drawn like any other and
/// resolved only if somebody taps it. A chat full of names must not become a
/// chat full of profile lookups.
abstract final class MessageText {
  /// The same shape the server enforces — `server/src/util/validate.ts`.
  ///
  /// Matched case-insensitively and lower-cased afterwards: the server stores
  /// names in lower case and refuses two that differ only by case, so `@Max`
  /// and `@max` are the same account and writing either should reach it.
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 32;

  /// Web addresses. Deliberately narrow — see `LinkedText`.
  static final RegExp _linkPattern = RegExp(
    r'(?:https?://|www\.)[^\s<>"]+',
    caseSensitive: false,
  );

  /// An `@name` that is not part of something else.
  ///
  /// The lookbehind is the whole rule. `max@example.com` has a word character
  /// before its `@` and is an address, not a mention; `.../@max` has a slash
  /// and belongs to a URL; `@@max` is not a name. Everything that reaches the
  /// body of the pattern is an `@` that starts a word.
  /// The trailing lookahead is the ceiling. Without it a name of thirty-three
  /// characters matches its first thirty-two and links a name nobody has —
  /// too long is not a name, it is not a shorter name.
  static final RegExp _mentionPattern = RegExp(
    r'(?<![A-Za-z0-9_.@/-])@([A-Za-z0-9_.]{3,32})(?![A-Za-z0-9_.])',
  );

  /// Fenced blocks and inline spans, whose contents are quoted rather than
  /// read. Fenced first, so a backtick inside one does not open a span.
  static final RegExp _fencedPattern = RegExp(r'```[\s\S]*?```');
  static final RegExp _inlineCodePattern = RegExp(r'`[^`\n]*`');

  /// Splits [text] into runs.
  ///
  /// [links] and [mentions] say which kinds this caller can draw. A caller that
  /// cannot open a URL asks for `links: false` and gets those characters as
  /// plain text rather than as something that looks tappable and is not.
  ///
  /// Every run is returned in source order and nothing is dropped: joining
  /// their [TextRun.text] reproduces [text] exactly.
  static List<TextRun> split(
    String text, {
    bool links = true,
    bool mentions = true,
  }) {
    if (text.isEmpty) return const [];

    final quoted = _codeRanges(text);
    final found = <_Found>[];

    if (links) {
      for (final match in _linkPattern.allMatches(text)) {
        if (_overlaps(quoted, match.start, match.end)) continue;
        // A URL at the end of a sentence takes the full stop with it unless
        // the trailing punctuation is handed back to the sentence.
        final raw = trimTrailingPunctuation(match.group(0)!);
        if (raw.isEmpty) continue;
        found.add(_Found(match.start, match.start + raw.length, TextRunKind.link, null));
      }
    }

    if (mentions) {
      for (final match in _mentionPattern.allMatches(text)) {
        if (_overlaps(quoted, match.start, match.end)) continue;
        // Inside a URL the `@` belongs to the address. The lookbehind already
        // refuses `/@name`, but a link range is the rule this is really about
        // and it does not depend on which character happens to precede.
        if (links && found.any((f) => f.kind == TextRunKind.link && match.start < f.end && match.start >= f.start)) {
          continue;
        }
        // A name can hold dots but a sentence ends in one. Trimmed the same way
        // a URL's full stop is, and for the same reason.
        var name = match.group(1)!;
        while (name.endsWith('.')) {
          name = name.substring(0, name.length - 1);
        }
        if (name.length < minUsernameLength) continue;
        final end = match.start + 1 + name.length;
        // `@max@example.com` is an address with an unusual local part, not a
        // mention of `max`. An `@` immediately after the name says so.
        if (end < text.length && text[end] == '@') continue;
        found.add(_Found(match.start, end, TextRunKind.mention, name.toLowerCase()));
      }
    }

    if (found.isEmpty) return [TextRun(TextRunKind.plain, text)];

    found.sort((a, b) => a.start.compareTo(b.start));
    final runs = <TextRun>[];
    var cursor = 0;
    for (final item in found) {
      // Two findings cannot both own a character. The earlier one keeps it.
      if (item.start < cursor) continue;
      if (item.start > cursor) {
        runs.add(TextRun(TextRunKind.plain, text.substring(cursor, item.start)));
      }
      runs.add(
        TextRun(item.kind, text.substring(item.start, item.end), username: item.username),
      );
      cursor = item.end;
    }
    if (cursor < text.length) {
      runs.add(TextRun(TextRunKind.plain, text.substring(cursor)));
    }
    return runs;
  }

  /// Whether [text] is a name this app would ever link.
  ///
  /// Used by the composer, which has to decide whether what somebody typed
  /// after an `@` is worth offering suggestions for.
  static bool isUsernameShaped(String name) =>
      RegExp(r'^[a-z0-9_.]{3,32}$').hasMatch(name.toLowerCase());

  /// Trailing punctuation that belongs to the sentence rather than the run.
  ///
  /// Public because `LinkedText` opens what it drew and has to trim the same
  /// characters this did; two copies of this list would eventually differ by
  /// one, and that one would be a link that opened the wrong address.
  static String trimTrailingPunctuation(String url) {
    var end = url.length;
    while (end > 0) {
      final character = url[end - 1];
      if ('.,;:!?"\''.contains(character)) {
        end--;
      } else if (character == ')' && !url.substring(0, end).contains('(')) {
        // Only an unmatched one. `.../Foo_(bar)` is a real address.
        end--;
      } else {
        break;
      }
    }
    return url.substring(0, end);
  }

  /// The ranges whose contents are shown rather than interpreted.
  static List<(int, int)> _codeRanges(String text) {
    if (!text.contains('`')) return const [];
    final ranges = <(int, int)>[];
    for (final match in _fencedPattern.allMatches(text)) {
      ranges.add((match.start, match.end));
    }
    for (final match in _inlineCodePattern.allMatches(text)) {
      if (_overlaps(ranges, match.start, match.end)) continue;
      ranges.add((match.start, match.end));
    }
    return ranges;
  }

  static bool _overlaps(List<(int, int)> ranges, int start, int end) =>
      ranges.any((range) => start < range.$2 && end > range.$1);
}

class _Found {
  const _Found(this.start, this.end, this.kind, this.username);

  final int start;
  final int end;
  final TextRunKind kind;
  final String? username;
}
