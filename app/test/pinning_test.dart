import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';

Message said(String body, {required int minute}) => Message(
      id: 'm$minute',
      clientId: 'c$minute',
      body: body,
      sentAt: DateTime(2026, 1, 1, 12, minute),
      isMine: false,
    );

InMemoryMessageStore storeWith(Map<String, int> byConversation) {
  final store = InMemoryMessageStore();
  for (final entry in byConversation.entries) {
    store.upsertUser(KnownUser(accountId: entry.key, username: entry.key));
    store.append(entry.key, said('hallo', minute: entry.value));
  }
  return store;
}

void main() {
  test('the list is newest first while nothing is pinned', () {
    final store = storeWith({'anna': 1, 'bob': 5, 'carol': 3});
    expect(store.conversations().map((c) => c.id), ['bob', 'carol', 'anna']);
  });

  test('a pinned chat goes to the top and stays there', () {
    final store = storeWith({'anna': 1, 'bob': 5, 'carol': 3});
    expect(store.setPinned('anna', pinned: true), isTrue);
    expect(store.conversations().map((c) => c.id), ['anna', 'bob', 'carol']);

    // Somebody else writes. The pin outranks recency, which is the point of it.
    store.append('carol', said('noch was', minute: 9));
    expect(store.conversations().map((c) => c.id), ['anna', 'carol', 'bob']);
  });

  test('several pinned chats keep their order among themselves', () {
    final store = storeWith({'anna': 1, 'bob': 5, 'carol': 3});
    store.setPinned('anna', pinned: true);
    store.setPinned('carol', pinned: true);
    expect(store.conversations().map((c) => c.id), ['carol', 'anna', 'bob']);
  });

  test('unpinning puts it back where its last message says it belongs', () {
    final store = storeWith({'anna': 1, 'bob': 5, 'carol': 3});
    store.setPinned('anna', pinned: true);
    expect(store.setPinned('anna', pinned: false), isTrue);
    expect(store.conversations().map((c) => c.id), ['bob', 'carol', 'anna']);
  });

  test('pinning what is already pinned changes nothing', () {
    final store = storeWith({'anna': 1});
    store.setPinned('anna', pinned: true);
    expect(store.setPinned('anna', pinned: true), isFalse);
  });

  test('pinning a conversation that is not there does nothing', () {
    final store = storeWith({'anna': 1});
    expect(store.setPinned('nobody', pinned: true), isFalse);
  });

  test('a pin survives being written to the archive and read back', () async {
    final store = storeWith({'anna': 1, 'bob': 5});
    store.setPinned('anna', pinned: true);

    final archive = EncryptedMessageArchive(
      storage: InMemoryArchiveStorage(),
      keyStore: InMemorySecureStore(),
    );
    await archive.save(store.conversations());

    final restored = InMemoryMessageStore()
      ..restore((await archive.load()).conversations);
    expect(restored.conversationWith('anna')!.pinned, isTrue);
    expect(restored.conversationWith('bob')!.pinned, isFalse);
    expect(restored.conversations().map((c) => c.id), ['anna', 'bob']);
  });

  test('a group can be pinned too', () {
    final store = InMemoryMessageStore()
      ..upsertGroup(const GroupInfo(groupId: 'g1', role: 'member', name: 'Wanderung'))
      ..upsertUser(const KnownUser(accountId: 'anna', username: 'anna'))
      ..append('anna', said('hallo', minute: 9));
    expect(store.setPinned('g1', pinned: true), isTrue);
    expect(store.conversations().first.id, 'g1');
  });
}
