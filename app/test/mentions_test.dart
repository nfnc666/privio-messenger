import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/mention_suggestions.dart';
import 'package:privio/core/message_text.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';

/// Where a message stops being characters and starts being something to tap.
///
/// Every case here is a sentence somebody could plausibly write, because the
/// failures this prevents are all of that shape: an address turned into a
/// mention, a full stop swallowed by a name, a link that lost its last
/// character to an `@`.

List<String> mentionsIn(String text) => MessageText.split(text)
    .where((run) => run.kind == TextRunKind.mention)
    .map((run) => run.username!)
    .toList();

String rejoin(String text) => MessageText.split(text).map((run) => run.text).join();

void main() {
  registerSuggestionTests();
  group('what counts as a mention', () {
    test('a plain one in a sentence', () {
      expect(mentionsIn('Schreib bitte @max'), ['max']);
    });

    test('punctuation belongs to the sentence, not to the name', () {
      expect(mentionsIn('Hallo @max!'), ['max']);
      expect(mentionsIn('@max, bist du da?'), ['max']);
      expect(mentionsIn('Frag @max.'), ['max']);
      expect(mentionsIn('(@max)'), ['max']);

      final runs = MessageText.split('Hallo @max!');
      expect(runs.map((r) => r.text).toList(), ['Hallo ', '@max', '!']);
    });

    test('several in one message, in the order they were written', () {
      expect(
        mentionsIn('@max und @lena, fragt bitte @sam'),
        ['max', 'lena', 'sam'],
      );
    });

    test('case is a spelling, not a different account', () {
      // Usernames are stored lower-case and two cannot differ by case alone.
      final runs = MessageText.split('Hallo @Max');
      final mention = runs.firstWhere((r) => r.kind == TextRunKind.mention);
      expect(mention.username, 'max', reason: 'resolved lower-case');
      expect(mention.text, '@Max', reason: 'drawn as it was typed');
    });

    test('dots inside a name are kept, a dot ending a sentence is not', () {
      expect(mentionsIn('@max.mueller kommt'), ['max.mueller']);
      expect(mentionsIn('Das war @max.mueller.'), ['max.mueller']);
    });

    test('too short and too long are not names', () {
      expect(mentionsIn('@ab'), isEmpty);
      expect(mentionsIn('@abc'), ['abc']);
      expect(mentionsIn('@${'a' * 33}'), isEmpty);
      expect(mentionsIn('@${'a' * 32}'), ['a' * 32]);
    });
  });

  group('what is not a mention', () {
    test('an email address', () {
      expect(mentionsIn('Schreib an max@example.com'), isEmpty);
      expect(rejoin('Schreib an max@example.com'), 'Schreib an max@example.com');
    });

    test('an address with an unusual local part', () {
      // `@max@example.com`: the `@` after the name says this is an address.
      expect(mentionsIn('@max@example.com'), isEmpty);
    });

    test('a username inside a URL', () {
      expect(mentionsIn('https://example.com/@max'), isEmpty);
      final runs = MessageText.split('https://example.com/@max');
      expect(runs.single.kind, TextRunKind.link);
    });

    test('anything inside a code span', () {
      expect(mentionsIn('Nimm `@max` wörtlich'), isEmpty);
      expect(mentionsIn('```\ncurl https://x.test -u @max\n```'), isEmpty);
      expect(
        MessageText.split('Nimm `@max` wörtlich').every((r) => r.kind == TextRunKind.plain),
        isTrue,
      );
    });

    test('a link inside a code span stays text', () {
      final runs = MessageText.split('`https://example.com`');
      expect(runs.every((r) => r.kind == TextRunKind.plain), isTrue);
    });

    test('a doubled at-sign', () {
      expect(mentionsIn('@@max'), isEmpty);
    });

    test('an at-sign in the middle of a word', () {
      expect(mentionsIn('foo@max'), isEmpty);
    });
  });

  group('links and mentions in the same message', () {
    test('both are found, and neither takes the other characters', () {
      final runs = MessageText.split('Siehe https://example.com und frag @max');
      expect(
        runs.map((r) => r.kind).toList(),
        [TextRunKind.plain, TextRunKind.link, TextRunKind.plain, TextRunKind.mention],
      );
      expect(runs[1].text, 'https://example.com');
      expect(runs[3].text, '@max');
    });

    test('a caller that cannot open links gets them as text', () {
      final runs = MessageText.split('https://example.com @max', links: false);
      expect(runs.any((r) => r.kind == TextRunKind.link), isFalse);
      expect(mentionsIn('https://example.com @max'), ['max']);
    });
  });

  group('nothing is lost', () {
    const samples = [
      '',
      'nur Text',
      'Hallo @max!',
      '@max @lena @sam',
      'max@example.com und https://example.com/@max',
      '`@max` und @lena',
      'Emoji bleibt: 🎉 @max 🎉',
      '   @max   ',
      '@max\n@lena',
    ];

    for (final sample in samples) {
      test('the runs rejoin to the original: "${sample.replaceAll('\n', ' ')}"', () {
        expect(rejoin(sample), sample);
      });
    }
  });

  group('the shape the composer checks', () {
    test('accepts what the server would', () {
      expect(MessageText.isUsernameShaped('max'), isTrue);
      expect(MessageText.isUsernameShaped('Max'), isTrue, reason: 'lower-cased first');
      expect(MessageText.isUsernameShaped('max.mueller_1'), isTrue);
    });

    test('and refuses what it would not', () {
      expect(MessageText.isUsernameShaped('ab'), isFalse);
      expect(MessageText.isUsernameShaped('a' * 33), isFalse);
      expect(MessageText.isUsernameShaped('max müller'), isFalse);
      expect(MessageText.isUsernameShaped('max-mueller'), isFalse);
    });
  });
}

/// The composer's half: what `@` is being typed, who to offer, and what a pick
/// puts in the field.
void registerSuggestionTests() {
  TextEditingValue typed(String text, {int? caret}) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret ?? text.length),
      );

  Contact contact(String username, {String? display, String? id}) => Contact(
        id: id ?? 'acc-$username',
        username: username,
        displayName: display ?? username,
      );

  GroupMember member(String username, {String? display, String? id}) => GroupMember(
        accountId: id ?? 'acc-$username',
        username: username,
        displayName: display,
        role: 'member',
      );

  group('what the composer thinks is being typed', () {
    test('an @ at the end of the field', () {
      final active = MentionSuggestions.activeQuery(typed('Schreib @ma'));
      expect(active?.query, 'ma');
      expect(active?.start, 8);
    });

    test('an @ with nothing after it yet', () {
      expect(MentionSuggestions.activeQuery(typed('Schreib @'))?.query, '');
    });

    test('nothing, once a space has been typed', () {
      expect(MentionSuggestions.activeQuery(typed('Schreib @max und')), isNull);
    });

    test('nothing, in the middle of an address', () {
      expect(MentionSuggestions.activeQuery(typed('max@examp')), isNull);
    });

    test('nothing, when the caret is somewhere else', () {
      // Replacing a word somebody has moved away from would rewrite text they
      // are not looking at.
      expect(MentionSuggestions.activeQuery(typed('@max hallo', caret: 3)), isNotNull);
      expect(MentionSuggestions.activeQuery(typed('@max hallo', caret: 9)), isNull);
    });
  });

  group('who is offered', () {
    test('contacts and group members together, each once', () {
      final offers = MentionSuggestions.matches(
        'ma',
        contacts: [contact('max')],
        members: [member('max'), member('marta')],
      );
      // Both start with what was typed, so they are ordered by the name a
      // reader sees. The point of the test is that `max` appears once.
      expect(offers.map((c) => c.username), ['marta', 'max']);
    });

    test('a display name matches too, and the username is what is inserted', () {
      final offers = MentionSuggestions.matches(
        'lena',
        contacts: [contact('l.mueller', display: 'Lena Müller')],
      );
      expect(offers.single.username, 'l.mueller');
      expect(offers.single.displayName, 'Lena Müller');
    });

    test('a username match comes before a display-name match', () {
      final offers = MentionSuggestions.matches(
        'max',
        contacts: [
          contact('zoe', display: 'Max von Zoe'),
          contact('max', display: 'Ada'),
        ],
      );
      expect(offers.first.username, 'max');
    });

    test('two people sharing a display name stay two people', () {
      // The thing a mention must never get wrong: the name on screen is not
      // the identity.
      final offers = MentionSuggestions.matches(
        'lena',
        contacts: [
          contact('lena1', display: 'Lena', id: 'acc-one'),
          contact('lena2', display: 'Lena', id: 'acc-two'),
        ],
      );
      expect(offers.map((c) => c.accountId).toSet(), {'acc-one', 'acc-two'});
      expect(offers.map((c) => c.username).toSet(), {'lena1', 'lena2'});
    });

    test('yourself is not offered', () {
      final offers = MentionSuggestions.matches(
        'm',
        contacts: [contact('max', id: 'acc-me'), contact('marta')],
        excludeAccountId: 'acc-me',
      );
      expect(offers.map((c) => c.username), ['marta']);
    });

    test('nobody, when nothing is known — and the name can still be typed', () {
      expect(MentionSuggestions.matches('max'), isEmpty);
      // Which is the point: the tokenizer links it either way.
      expect(mentionsIn('Frag @max'), ['max']);
    });

    test('at most a handful, so the field is not buried', () {
      final many = [for (var i = 0; i < 20; i++) contact('user$i')];
      expect(
        MentionSuggestions.matches('user', contacts: many).length,
        MentionSuggestions.limit,
      );
    });
  });

  group('picking one', () {
    test('puts the whole name in, with a space after it', () {
      final value = typed('Schreib @ma');
      final next = MentionSuggestions.insert(value, 8, 'max');
      expect(next.text, 'Schreib @max ');
      expect(next.selection.baseOffset, 13);
    });

    test('and leaves the rest of the sentence alone', () {
      final value = typed('Schreib @ma bitte', caret: 11);
      final next = MentionSuggestions.insert(value, 8, 'max');
      expect(next.text, 'Schreib @max  bitte');
    });

    test('what it inserts is what the tokenizer then links', () {
      final next = MentionSuggestions.insert(typed('@ma'), 0, 'max.mueller');
      expect(mentionsIn(next.text), ['max.mueller']);
    });
  });
}
