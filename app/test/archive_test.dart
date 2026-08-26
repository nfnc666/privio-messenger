import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';

List<Conversation> sampleHistory() {
  final conversation = Conversation(
    user: const KnownUser(accountId: 'acc-alice', username: 'alice', displayName: 'Alice'),
    messages: [
      Message(
        id: '1',
        body: 'Treffen um 19 Uhr am üblichen Ort',
        sentAt: DateTime.utc(2026, 3, 4, 18, 30),
        isMine: false,
      ),
      Message(
        id: '2',
        body: 'Bin da',
        sentAt: DateTime.utc(2026, 3, 4, 18, 31),
        isMine: true,
        state: DeliveryState.read,
      ),
    ],
  )..unreadCount = 1;
  return [conversation];
}

void main() {
  late InMemoryArchiveStorage storage;
  late InMemorySecureStore keys;
  late EncryptedMessageArchive archive;

  setUp(() {
    storage = InMemoryArchiveStorage();
    keys = InMemorySecureStore();
    archive = EncryptedMessageArchive(storage: storage, keyStore: keys);
  });

  test('history survives a round trip through the archive', () async {
    await archive.save(sampleHistory());
    final restored = await archive.load();

    expect(restored, hasLength(1));
    expect(restored.single.user.username, 'alice');
    expect(restored.single.user.displayName, 'Alice');
    expect(restored.single.unreadCount, 1);
    expect(restored.single.messages.map((m) => m.body), [
      'Treffen um 19 Uhr am üblichen Ort',
      'Bin da',
    ]);
    expect(restored.single.messages.last.isMine, isTrue);
    expect(restored.single.messages.last.state, DeliveryState.read);
    expect(
      restored.single.messages.first.sentAt.toUtc(),
      DateTime.utc(2026, 3, 4, 18, 30),
      reason: 'timestamps must not drift across a save',
    );
  });

  test('what sits at rest is ciphertext, not the conversation', () async {
    await archive.save(sampleHistory());

    final atRest = storage.bytes!;
    final asText = utf8.decode(atRest, allowMalformed: true);
    // This is what someone reading the device's storage would find.
    expect(asText, isNot(contains('Treffen')));
    expect(asText, isNot(contains('alice')));
    expect(asText, isNot(contains('Bin da')));
    expect(atRest.first, 1, reason: 'a format version, so the layout can change later');
  });

  test('the key is generated once and kept in the keystore', () async {
    expect(await keys.readArchiveKey(), isNull);
    await archive.save(sampleHistory());

    final stored = await keys.readArchiveKey();
    expect(stored, isNotNull);
    expect(base64Decode(stored!).length, 32, reason: 'AES-256 means a 256-bit key');

    await archive.save(sampleHistory());
    expect(await keys.readArchiveKey(), stored, reason: 'the key is not rotated on every save');
  });

  test('a different key cannot read the archive', () async {
    await archive.save(sampleHistory());

    // Same bytes at rest, someone else's keystore.
    final intruder = EncryptedMessageArchive(
      storage: storage,
      keyStore: InMemorySecureStore(),
    );
    expect(await intruder.load(), isEmpty);
  });

  test('a tampered archive is discarded rather than half-read', () async {
    await archive.save(sampleHistory());
    final corrupted = storage.bytes!;
    corrupted[corrupted.length - 3] ^= 0xFF;
    await storage.write(corrupted);

    // Fresh instance so the cached key is not what saves it.
    final reopened = EncryptedMessageArchive(storage: storage, keyStore: keys);
    expect(await reopened.load(), isEmpty);
  });

  test('an empty device reads back an empty history', () async {
    expect(await archive.load(), isEmpty);
  });

  test('clearing leaves nothing behind', () async {
    await archive.save(sampleHistory());
    expect(storage.bytes, isNotNull);

    await archive.clear();
    expect(storage.bytes, isNull);
    expect(await archive.load(), isEmpty);
  });

  test('the store restores a loaded history in place', () async {
    final store = InMemoryMessageStore()
      ..upsertUser(const KnownUser(accountId: 'stale', username: 'stale'))
      ..append('stale', Message(id: 'x', body: 'old', sentAt: DateTime.now(), isMine: true));

    store.restore(sampleHistory());

    expect(store.conversationWith('stale'), isNull, reason: 'a restore replaces, not merges');
    expect(store.conversationWith('acc-alice')?.messages, hasLength(2));
  });

  test('AES-GCM is used with a fresh nonce for every save', () async {
    await archive.save(sampleHistory());
    final first = storage.bytes!.sublist(1, 13);
    await archive.save(sampleHistory());
    final second = storage.bytes!.sublist(1, 13);

    expect(first, isNot(second), reason: 'reusing a GCM nonce would be catastrophic');
    expect(AesGcm.with256bits().nonceLength, 12);
  });
}
