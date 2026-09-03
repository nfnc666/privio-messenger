import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/message_search.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';

Message said(String body, {int minute = 0, bool isMine = false}) => Message(
      id: 'm$minute-$body',
      clientId: 'c$minute',
      body: body,
      sentAt: DateTime(2026, 1, 1, 12, minute),
      isMine: isMine,
    );

InMemoryMessageStore storeWith(Map<String, List<Message>> byConversation) {
  final store = InMemoryMessageStore();
  for (final entry in byConversation.entries) {
    store.upsertUser(KnownUser(accountId: entry.key, username: entry.key));
    for (final message in entry.value) {
      store.append(entry.key, message);
    }
  }
  return store;
}

void main() {
  test('finds a message by a word inside it', () {
    final store = storeWith({
      'bob': [said('Wir treffen uns am Bahnhof', minute: 1)],
      'carol': [said('Bis morgen', minute: 2)],
    });

    final hits = MessageSearch.run(store.conversations(), 'bahnhof');
    expect(hits, hasLength(1));
    expect(hits.single.conversationId, 'bob');
    expect(hits.single.message.body, 'Wir treffen uns am Bahnhof');
  });

  test('matches regardless of case', () {
    final store = storeWith({
      'bob': [said('Der SCHLÜSSEL liegt unter der Matte')],
    });
    expect(MessageSearch.run(store.conversations(), 'schlüssel'), hasLength(1));
    expect(MessageSearch.run(store.conversations(), 'SCHLÜSSEL'), hasLength(1));
  });

  test('searches every conversation, not only the open one', () {
    final store = storeWith({
      'bob': [said('Kaffee?', minute: 1)],
      'carol': [said('Kaffee um vier', minute: 2)],
      'dave': [said('Tee', minute: 3)],
    });

    final hits = MessageSearch.run(store.conversations(), 'kaffee');
    expect(hits.map((h) => h.conversationId).toSet(), {'bob', 'carol'});
  });

  test('newest first, because that is what someone is looking for', () {
    final store = storeWith({
      'bob': [
        said('Termin am Montag', minute: 1),
        said('Termin verschoben', minute: 5),
        said('Termin steht', minute: 3),
      ],
    });

    final hits = MessageSearch.run(store.conversations(), 'termin');
    expect(hits.map((h) => h.message.body), [
      'Termin verschoben',
      'Termin steht',
      'Termin am Montag',
    ]);
  });

  test('an empty query is not a search for everything', () {
    final store = storeWith({
      'bob': [said('irgendwas')],
    });
    expect(MessageSearch.run(store.conversations(), ''), isEmpty);
    expect(MessageSearch.run(store.conversations(), '   '), isEmpty);
  });

  test('a deleted message has nothing to find', () {
    final store = storeWith({
      'bob': [said('Das Passwort ist offen', minute: 1)],
    });
    store.deleteMessage(conversationId: 'bob', clientId: 'c1', tombstone: true);

    expect(
      MessageSearch.run(store.conversations(), 'passwort'),
      isEmpty,
      reason: 'a message taken back must not come back through search',
    );
  });

  test('the result carries where the match is', () {
    final store = storeWith({
      'bob': [said('Treffen wir uns am Bahnhof')],
    });
    final hit = MessageSearch.run(store.conversations(), 'Bahnhof').single;
    expect(hit.message.body.substring(hit.matchStart, hit.matchEnd), 'Bahnhof');
  });

  group('the snippet', () {
    test('is the whole message when it is short', () {
      final store = storeWith({
        'bob': [said('Kurz und gut')],
      });
      final hit = MessageSearch.run(store.conversations(), 'gut').single;
      final snippet = MessageSearch.snippet(hit);
      expect(snippet.text, 'Kurz und gut');
      expect(snippet.text.substring(snippet.start, snippet.end), 'gut');
    });

    test('is cut around the match in a long one', () {
      final body = '${'a' * 300} Bahnhof ${'b' * 300}';
      final store = storeWith({
        'bob': [said(body)],
      });
      final hit = MessageSearch.run(store.conversations(), 'bahnhof').single;
      final snippet = MessageSearch.snippet(hit);

      expect(snippet.text.length, lessThan(body.length));
      expect(snippet.text, startsWith('…'));
      expect(snippet.text, endsWith('…'));
      expect(
        snippet.text.substring(snippet.start, snippet.end),
        'Bahnhof',
        reason: 'the offsets have to survive the cut, or the wrong word lights up',
      );
    });

    test('keeps its offsets when the match is at the very start', () {
      final body = 'Bahnhof ${'b' * 300}';
      final store = storeWith({
        'bob': [said(body)],
      });
      final hit = MessageSearch.run(store.conversations(), 'bahnhof').single;
      final snippet = MessageSearch.snippet(hit);
      expect(snippet.text, startsWith('Bahnhof'));
      expect(snippet.text.substring(snippet.start, snippet.end), 'Bahnhof');
    });

    test('keeps its offsets when the match is at the very end', () {
      final body = '${'a' * 300} Bahnhof';
      final store = storeWith({
        'bob': [said(body)],
      });
      final hit = MessageSearch.run(store.conversations(), 'bahnhof').single;
      final snippet = MessageSearch.snippet(hit);
      expect(snippet.text, endsWith('Bahnhof'));
      expect(snippet.text.substring(snippet.start, snippet.end), 'Bahnhof');
    });
  });

  test('a very common word does not return the entire history', () {
    final store = storeWith({
      'bob': [for (var i = 0; i < 500; i++) said('ja $i', minute: i)],
    });
    expect(MessageSearch.run(store.conversations(), 'ja'), hasLength(200));
  });
}
