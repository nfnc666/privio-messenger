/// The name a person chooses for themselves, cleaned the way the server
/// cleans it.
///
/// Two copies of one rule, and that is deliberate rather than an oversight:
/// the server's copy is the one that decides what is stored, because it is the
/// only one an attacker cannot skip. This copy exists so that the field can
/// count what the person is typing and say "that is too long" while they can
/// still do something about it — rather than sending 60 characters and getting
/// a rejection back.
///
/// `server/src/services/display_name.ts` is the other half. If one changes,
/// both do; `app/test/profile_name_test.dart` pins the shared cases.
library;

import 'package:flutter/widgets.dart' show Characters;

/// Fifty of what a person would count.
const int displayNameLimit = 50;

/// Invisible characters, minus the ones that make emoji and scripts work.
///
/// Kept: the zero-width joiner and non-joiner, which hold an emoji family
/// together and separate letters in Persian and Hindi, and the variation
/// selectors that choose between the text and emoji shape of a character.
///
/// Removed: controls, the soft hyphen, the bidi marks, overrides and isolates,
/// the invisible-operator block, the zero-width space and the byte order mark.
/// A right-to-left override in a name reorders the line it is drawn in —
/// including the `@username` beside it.
// Raw strings on purpose: these escapes are read by the regular-expression
// engine rather than by Dart, so this file stays plain ASCII. A source file
// carrying a literal right-to-left override would reorder itself in a diff.
final RegExp _invisible = RegExp(
  r'[\u0000-\u001F\u007F-\u009F\u00AD\u061C\u200B\u200E\u200F'
  r'\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
);

final RegExp _whitespace = RegExp(
  r'[ \t\n\r\u000B\u000C\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]+',
);

/// What a display name can be wrong about. There is only one thing, because
/// everything else is either fixed silently or allowed.
enum DisplayNameProblem { tooLong }

/// The cleaned name, or null for "no name" — which is a real answer: an
/// account without one is drawn as its `@username`.
String? cleanDisplayName(String value) {
  final collapsed = value.replaceAll(_invisible, '').replaceAll(_whitespace, ' ').trim();
  return collapsed.isEmpty ? null : collapsed;
}

/// How long a name is to the person who typed it.
///
/// Grapheme clusters, not UTF-16 code units: one family emoji is one character
/// to a reader and eleven to `String.length`, and a limit measured the second
/// way would refuse a name that looks short.
int visibleLength(String value) => Characters(value).length;

/// The problem with this name, or null if there is none.
DisplayNameProblem? displayNameProblem(String value) {
  final cleaned = cleanDisplayName(value);
  if (cleaned == null) return null;
  return visibleLength(cleaned) > displayNameLimit ? DisplayNameProblem.tooLong : null;
}
