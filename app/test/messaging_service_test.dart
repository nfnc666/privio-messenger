import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:image/image.dart' as img;
import 'package:privio/data/message_store.dart';
import 'package:privio/media/avatar.dart';
import 'package:privio/media/voice.dart';

import 'support/fake_server.dart';
import 'support/fake_voice.dart';

void main() {
  late FakeServer server;
  late Participant alice;
  late Participant bob;

  setUp(() async {
    server = FakeServer();
    alice = Participant('alice', 'account-alice', 1);
    bob = Participant('bob', 'account-bob', 1);
    await alice.join(server);
    await bob.join(server);
  });

  test('a message travels end to end and the server only ever holds ciphertext', () async {
    await alice.messaging.sendToUser('bob', 'Bis später!');

    expect(server.envelopes, hasLength(1));
    expect(
      utf8.decode(base64Decode(server.envelopes.single['content'] as String), allowMalformed: true),
      isNot(contains('später')),
      reason: 'this is exactly what the server database would hold',
    );

    final received = await bob.messaging.receive();
    expect(received.failures, isEmpty);
    expect(received.messages.single.body, 'Bis später!');
    expect(received.messages.single.senderAccountId, alice.accountId);
  });

  test('envelopes are acknowledged only after they decrypt', () async {
    await alice.messaging.sendToUser('bob', 'eins');
    expect(server.envelopes, hasLength(1));

    await bob.messaging.receive();
    expect(server.envelopes, isEmpty, reason: 'acknowledged after decryption');

    final second = await bob.messaging.receive();
    expect(second.messages, isEmpty, reason: 'nothing is redelivered');
  });

  test('an envelope pushed and polled at once is opened once, not twice', () async {
    await alice.messaging.sendToUser('bob', 'nur einmal');
    // Exactly what happens on a live device: the socket pushes the envelope
    // while the fallback poll is fetching everything not yet acknowledged.
    final pushed = [...server.envelopes];

    final push = bob.messaging.decryptEnvelopes(pushed);
    final poll = bob.messaging.receive();
    final results = await Future.wait([push, poll]);

    final opened = [for (final result in results) ...result.messages];
    final failed = [for (final result in results) ...result.failures];
    expect(opened.single.body, 'nur einmal');
    expect(
      failed,
      isEmpty,
      reason: 'the second copy is a redelivery, not a message that would not open',
    );
  });

  test('a redelivered envelope is acknowledged rather than reported', () async {
    await alice.messaging.sendToUser('bob', 'zweimal zugestellt');
    final pushed = [...server.envelopes];

    await bob.messaging.decryptEnvelopes(pushed);
    final again = await bob.messaging.decryptEnvelopes(pushed);

    expect(again.messages, isEmpty);
    expect(again.failures, isEmpty);
    expect(
      again.highestHandled,
      pushed.single['id'],
      reason: 'still acknowledged, or the server keeps offering it forever',
    );
  });

  test('a stale device list is refetched and the send retried once', () async {
    server.mismatchesToServe = 1;

    await alice.messaging.sendToUser('bob', 'trotzdem angekommen');

    expect(
      server.sendAttempts,
      2,
      reason: 'one rejection, one successful retry — alice has a single device '
          'here, so no copy is sent to herself',
    );
    final received = await bob.messaging.receive();
    expect(received.messages.single.body, 'trotzdem angekommen');
  });

  test('a mismatch that survives a refetch is reported, not retried forever', () async {
    // Two in a row is not a race any more — it is a bug or an attack, and the
    // caller has to see it rather than the client looping.
    server.mismatchesToServe = 2;

    await expectLater(
      alice.messaging.sendToUser('bob', 'geht nicht'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'device_mismatch')),
    );
    expect(server.sendAttempts, 2, reason: 'exactly one retry, then it gives up');
  });

  test('a tampered envelope is reported, not silently dropped', () async {
    await alice.messaging.sendToUser('bob', 'Überweisung 100 Euro');

    final content = base64Decode(server.envelopes.single['content'] as String);
    content[content.length - 5] ^= 0xFF;
    server.envelopes.single['content'] = base64Encode(content);

    final received = await bob.messaging.receive();
    expect(received.messages, isEmpty);
    expect(received.failures, hasLength(1));
    expect(server.envelopes, isEmpty, reason: 'a poison envelope must not block the queue');
  });

  group('a second device on the same account', () {
    late Participant laptop;

    setUp(() async {
      // Same account, a different device index — what signing in twice does.
      laptop = Participant('alice', 'account-alice', 2);
      await laptop.join(server);
    });

    test('gets a copy of what the first device sent', () async {
      await alice.messaging.sendToUser('bob', 'von meinem Telefon');

      // Bob got the message itself.
      final forBob = await bob.messaging.receive();
      expect(forBob.messages.single.body, 'von meinem Telefon');

      // The laptop got a copy, marked as a copy rather than as a message from
      // somebody — filing it as incoming would show this account writing to
      // itself.
      final forLaptop = await laptop.messaging.receive();
      final payload = forLaptop.messages.single.payload;
      expect(payload.isSync, isTrue);
      expect(payload.isControl, isTrue, reason: 'it is never a bubble on its own');
      expect(payload.sync!.inner.body, 'von meinem Telefon');
      expect(payload.sync!.conversationId, bob.accountId);
      expect(payload.sync!.isGroup, isFalse);
    });

    test('the sending device does not get its own copy', () async {
      await alice.messaging.sendToUser('bob', 'einmal reicht');

      final backToSender = await alice.messaging.receive();
      expect(
        backToSender.messages,
        isEmpty,
        reason: 'a device that already has the message does not need it again',
      );
    });

    test('an account with one device sends no copy at all', () async {
      // Bob has a single device: there is nobody to sync to, and asking is a
      // request that should not be made.
      final before = server.envelopes.length;
      await bob.messaging.sendToUser('alice', 'nur ein Geraet');
      final envelopes = server.envelopes.length - before;

      // Two devices of alice's, and nothing addressed back to bob.
      expect(envelopes, 2);
      final toBob = server.envelopes.where(
        (e) => e['recipientDeviceId'] == bob.deviceId,
      );
      expect(toBob, isEmpty);
    });

    test('a group message needs no copy: the fan-out already reaches it', () async {
      final group = await alice.messaging.createGroup('Team', [bob.accountId]);
      final before = server.envelopes.length;
      await alice.messaging.sendToGroup(group.groupId, 'an alle');

      // Every member device except the sending one, which includes the laptop.
      final sent = server.envelopes.skip(before).toList();
      expect(
        sent.any((e) => e['recipientDeviceId'] == laptop.deviceId),
        isTrue,
        reason: 'the group route already excludes only the device that sent',
      );
      expect(
        sent.any((e) => e['recipientDeviceId'] == alice.deviceId),
        isFalse,
      );
    });

    test('the copy carries an attachment by reference, not by uploading twice', () async {
      await alice.messaging.sendAttachment(
        'bob',
        file: Uint8List.fromList(List.filled(64, 7)),
        fileName: 'note.bin',
      );
      final uploads = server.media.length;

      final forLaptop = await laptop.messaging.receive();
      final inner = forLaptop.messages.single.payload.sync!.inner;

      expect(uploads, 1, reason: 'one upload, two messages pointing at it');
      expect(inner.isMedia, isTrue);
      expect(inner.mediaId, isNotNull);
      expect(
        inner.mediaToken,
        isNotNull,
        reason: 'without the capability the laptop could not open its own file',
      );
    });
  });

  test('a conversation continues in both directions', () async {
    await alice.messaging.sendToUser('bob', 'Hallo');
    await bob.messaging.receive();

    await bob.messaging.sendToUser('alice', 'Hallo zurück');
    final atAlice = await alice.messaging.receive();
    expect(atAlice.messages.single.body, 'Hallo zurück');

    await alice.messaging.sendToUser('bob', 'Und noch eine');
    final atBob = await bob.messaging.receive();
    expect(atBob.messages.single.body, 'Und noch eine');
  });

  test('prekeys are topped up when the pool runs low', () async {
    // Three were published and the low-water mark is far above that.
    final remaining = await alice.messaging.maintainPreKeys();
    expect(remaining, PrivioCrypto.preKeyBatchSize);

    // Ids must not collide with the ones already on the server.
    final device = server.accounts['alice']!.devices.single;
    final ids = device.preKeys.map((k) => k['keyId'] as int).toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'no reused prekey ids');
  });

  test('the signed prekey is left alone while it is still fresh', () async {
    final device = server.accounts['alice']!.devices.single;
    final published = device.signedPreKey['publicKey'];

    expect(await alice.messaging.rotateSignedPreKeyIfDue(), isFalse);
    expect(device.signedPreKey['publicKey'], published);
  });

  test('and replaced on the server once it has been on offer too long', () async {
    final device = server.accounts['alice']!.devices.single;
    final before = device.signedPreKey['publicKey'];

    final due = DateTime.now().add(
      PrivioCrypto.signedPreKeyLifetime + const Duration(minutes: 1),
    );
    expect(await alice.messaging.rotateSignedPreKeyIfDue(now: due), isTrue);

    expect(
      device.signedPreKey['publicKey'],
      isNot(before),
      reason: 'the key strangers seal to is the one that had to change',
    );

    // Still openable: the device kept the old one, because a bundle fetched
    // before the rotation may only now be turning into a message.
    expect(await alice.crypto.store.loadSignedPreKeys(), hasLength(2));
  });

  test('a message sealed to the previous signed prekey still opens', () async {
    // Bob fetches Alice's bundle, and only then does she rotate.
    final bundle = DeviceBundle.fromJson(
      server.accounts['alice']!.devices.single.bundle(),
    );
    await alice.messaging.rotateSignedPreKeyIfDue(
      now: DateTime.now().add(
        PrivioCrypto.signedPreKeyLifetime + const Duration(minutes: 1),
      ),
    );

    final sealed = await bob.crypto.sealForDevices(
      accountId: alice.accountId,
      devices: [bundle],
      plaintext: 'Im Tunnel geschrieben',
    );
    final opened = await alice.crypto.openEnvelope(
      senderAccountId: bob.accountId,
      senderDeviceIndex: bob.deviceIndex,
      type: sealed.single.type,
      content: sealed.single.content,
    );
    expect(opened, 'Im Tunnel geschrieben');
  });
  test('a photo arrives with its metadata stripped', () async {
    final photo = File('test/fixtures/photo_with_exif.jpg').readAsBytesSync();
    // The fixture really does carry a camera model, a serial number and GPS.
    expect(utf8.decode(photo, allowMalformed: true), contains('ACME Ultra 12 Pro'));

    final report = await alice.messaging.sendAttachment(
      'bob',
      file: photo,
      fileName: 'urlaub.jpg',
    );
    expect(report.report.removed, contains('EXIF / XMP (camera, GPS, timestamps)'));

    // The sender gets back where the file went, so its own bubble can show the
    // file rather than an empty box. Nothing else fills that in: a message of
    // one's own never comes back from the server.
    expect(report.mediaId, isNotEmpty);
    expect(report.mediaKey, isNotEmpty);
    expect(report.fileName, 'urlaub.jpg');
    expect(report.mediaType, 'image/jpeg');
    expect(report.byteSize, greaterThan(0));

    // What the server now holds must give nothing away.
    final stored = server.media.values.single;
    final storedText = utf8.decode(stored, allowMalformed: true);
    expect(storedText, isNot(contains('ACME')));
    expect(storedText, isNot(contains('urlaub.jpg')));
    expect(
      utf8.decode(
        base64Decode(server.envelopes.single['content'] as String),
        allowMalformed: true,
      ),
      isNot(contains('urlaub.jpg')),
    );

    final received = await bob.messaging.receive();
    final payload = received.messages.single.payload;
    expect(payload.isMedia, isTrue);
    expect(payload.fileName, 'urlaub.jpg', reason: 'the name rides inside the sealed message');
    expect(payload.mediaType, 'image/jpeg');

    final opened = await bob.messaging.openAttachment(payload);
    final openedText = utf8.decode(opened, allowMalformed: true);
    expect(openedText, isNot(contains('ACME')), reason: 'no camera or serial number');
    expect(openedText, isNot(contains('SN-4711-XYZ')));
    expect(opened.sublist(0, 2), [0xFF, 0xD8], reason: 'still a usable JPEG');
  });

  test('upload size is a bucket, never the file’s real size', () async {
    // Files of different real sizes that land in the same bucket become
    // indistinguishable; the exact size is never on the wire.
    for (final length in [40, 100, 200]) {
      await alice.messaging.sendAttachment(
        'bob',
        file: Uint8List.fromList(List.filled(length, 7)),
        fileName: 'datei-$length.bin',
      );
    }

    final sizes = server.media.values.map((bytes) => bytes.length).toSet();
    expect(sizes, hasLength(1), reason: '40, 100 and 200 bytes all look the same');
    expect(sizes.single, isNot(anyOf(40, 100, 200)));

    // A larger file steps to the next bucket rather than revealing its length:
    // an observer learns the size only to within a factor of two.
    await alice.messaging.sendAttachment(
      'bob',
      file: Uint8List.fromList(List.filled(300, 9)),
      fileName: 'groesser.bin',
    );
    final withLarger = server.media.values.map((bytes) => bytes.length).toSet();
    expect(withLarger, hasLength(2));
    expect(withLarger.reduce((a, b) => a > b ? a : b), isNot(300));
  });

  test('a file the server tampered with will not open', () async {
    final payloadSource = await alice.messaging.sendAttachment(
      'bob',
      file: File('test/fixtures/image_with_text.png').readAsBytesSync(),
      fileName: 'bild.png',
    );
    expect(payloadSource.report.recognised, isTrue);

    final id = server.media.keys.single;
    final tampered = [...server.media[id]!];
    tampered[tampered.length ~/ 2] ^= 0xFF;
    server.media[id] = tampered;

    final received = await bob.messaging.receive();
    await expectLater(
      bob.messaging.openAttachment(received.messages.single.payload),
      throwsA(isA<Exception>()),
      reason: 'a modified file must fail rather than be shown as genuine',
    );
  });
  test('a profile picture reaches a contact and nobody else', () async {
    // What a phone would hand over: a wide photo with camera tags.
    final source = img.encodeJpg(img.Image(width: 900, height: 600), quality: 90);
    final prepared = AvatarImage.prepare(Uint8List.fromList(source))!;

    final mediaId = await alice.messaging.uploadAvatar(prepared);
    expect(server.avatars[alice.deviceId], mediaId);

    // The server now holds the picture. It must not be a picture to the server.
    final stored = Uint8List.fromList(server.media[mediaId]!);
    expect(stored.sublist(0, 3), isNot([0xFF, 0xD8, 0xFF]));
    expect(utf8.decode(stored, allowMalformed: true), isNot(contains('JFIF')));

    // A contact who has been sent the profile key can open it.
    final profileKey = await alice.crypto.profileKey();
    final opened = await bob.messaging.openAvatar(mediaId, profileKey);
    expect(opened, prepared);
    expect(img.decodeImage(opened)?.width, AvatarImage.size);

    // Someone who has not cannot.
    await expectLater(
      bob.messaging.openAvatar(mediaId, await bob.crypto.profileKey()),
      throwsA(isA<Exception>()),
    );
  });

  test('the profile key travels with an ordinary message', () async {
    await alice.messaging.sendToUser('bob', 'hallo');

    // Read the wire bytes first: receiving acknowledges, which deletes them.
    final onTheWire = utf8.decode(
      base64Decode(server.envelopes.single['content'] as String),
      allowMalformed: true,
    );

    final received = await bob.messaging.receive();
    final key = received.messages.single.payload.profileKey;

    expect(key, isNotNull, reason: 'this is how a contact comes to see your picture');
    expect(base64Decode(key!), await alice.crypto.profileKey());

    // And it was inside the sealed payload, not next to it.
    expect(onTheWire, isNot(contains(key)));
  });
  test('the server stores a group it cannot name', () async {
    final group = await alice.messaging.createGroup('Familie', [bob.accountId]);

    expect(group.name, 'Familie');
    expect(group.groupKey, isNotNull);

    // What the server holds is the sealed name and no key for it.
    final stored = server.groups[group.groupId]!['encryptedMetadata'] as String;
    expect(
      utf8.decode(base64Decode(stored), allowMalformed: true),
      isNot(contains('Familie')),
    );
  });

  test('a member with the key reads the name; without it, they do not', () async {
    final group = await alice.messaging.createGroup('Projekt X', [bob.accountId]);

    // Bob lists groups before the key has reached him.
    final store = InMemoryMessageStore();
    final beforeKey = await bob.messaging.listGroups(store);
    expect(beforeKey.single.groupId, group.groupId);
    expect(beforeKey.single.name, isNull, reason: 'no key, no name');

    // Once he has it, the same listing opens.
    store.upsertGroup(
      GroupInfo(
        groupId: group.groupId,
        role: 'member',
        groupKey: group.groupKey,
      ),
    );
    final afterKey = await bob.messaging.listGroups(store);
    expect(afterKey.single.name, 'Projekt X');
  });

  test('a group message reaches every member device, sealed per device', () async {
    final group = await alice.messaging.createGroup('Team', [bob.accountId]);
    final delivered = await alice.messaging.sendToGroup(
      group.groupId,
      'Morgen um neun',
      groupKey: group.groupKey,
    );

    expect(delivered, 1, reason: 'Bob has one device');
    final envelope = server.envelopes.single;
    expect(envelope['groupId'], group.groupId);
    expect(
      utf8.decode(base64Decode(envelope['content'] as String), allowMalformed: true),
      isNot(contains('Morgen')),
    );

    final received = await bob.messaging.receive();
    expect(received.messages.single.body, 'Morgen um neun');
    expect(received.messages.single.groupId, group.groupId);
  });

  test('the group key travels on the group’s messages', () async {
    final group = await alice.messaging.createGroup('Verein', [bob.accountId]);
    await alice.messaging.sendToGroup(group.groupId, 'hallo', groupKey: group.groupKey);

    final received = await bob.messaging.receive();
    expect(received.messages.single.payload.groupKey, group.groupKey);
  });

  test('a group message from a stranger’s device does not decrypt', () async {
    final group = await alice.messaging.createGroup('Privat', [bob.accountId]);
    await alice.messaging.sendToGroup(group.groupId, 'geheim', groupKey: group.groupKey);

    final mallory = Participant('mallory', 'account-mallory', 1);
    await mallory.join(server);

    // Point the envelope at Mallory's device: holding the ciphertext is not
    // membership.
    server.envelopes.single['recipientDeviceId'] = mallory.deviceId;
    final received = await mallory.messaging.receive();
    expect(received.messages, isEmpty);
    expect(received.failures, hasLength(1));
  });
  test('a photo sent to a group is uploaded once and scrubbed once', () async {
    final group = await alice.messaging.createGroup('Wandergruppe', [bob.accountId]);
    final photo = File('test/fixtures/photo_with_exif.jpg').readAsBytesSync();

    final report = await alice.messaging.sendGroupAttachment(
      group.groupId,
      file: photo,
      fileName: 'gipfel.jpg',
      groupKey: group.groupKey,
    );
    expect(report.report.removed, contains('EXIF / XMP (camera, GPS, timestamps)'));

    // One upload, however many members: only the pointer is fanned out.
    expect(server.media.length, 1);
    final storedText = utf8.decode(server.media.values.single, allowMalformed: true);
    expect(storedText, isNot(contains('ACME')));
    expect(storedText, isNot(contains('gipfel.jpg')));

    final envelope = server.envelopes.single;
    expect(envelope['groupId'], group.groupId);
    expect(
      utf8.decode(base64Decode(envelope['content'] as String), allowMalformed: true),
      isNot(contains('gipfel.jpg')),
      reason: 'the file name rides inside the sealed payload',
    );

    final received = await bob.messaging.receive();
    final payload = received.messages.single.payload;
    expect(received.messages.single.groupId, group.groupId);
    expect(payload.isMedia, isTrue);
    expect(payload.fileName, 'gipfel.jpg');
    expect(payload.groupKey, group.groupKey, reason: 'a new member still learns the name key');

    final opened = await bob.messaging.openAttachment(payload);
    expect(utf8.decode(opened, allowMalformed: true), isNot(contains('SN-4711-XYZ')));
    expect(opened.sublist(0, 2), [0xFF, 0xD8], reason: 'still a usable JPEG');
  });

  group('receipts and typing', () {
    test('a receipt goes over the wire sealed, and is not a message', () async {
      await alice.messaging.sendToUser('bob', 'hallo');
      final received = await bob.messaging.receive();
      final clientId = received.messages.single.payload.clientId;

      await bob.messaging.sendReceipt(
        username: 'alice',
        clientIds: [clientId ?? 'c1'],
        kind: 'read',
      );

      // The server sees an envelope like any other, and can read none of it.
      final envelope = server.envelopes.last;
      expect(
        utf8.decode(base64Decode(envelope['content'] as String), allowMalformed: true),
        isNot(contains('read')),
      );

      final back = await alice.messaging.receive();
      final payload = back.messages.single.payload;
      expect(payload.isReceipt, isTrue);
      expect(payload.receiptKind, 'read');
      expect(payload.isControl, isTrue, reason: 'never shown in a conversation');
    });

    test('a typing notice carries a timestamp and no content', () async {
      await alice.messaging.sendTyping('bob');

      final envelope = server.envelopes.single;
      final asText = utf8.decode(
        base64Decode(envelope['content'] as String),
        allowMalformed: true,
      );
      expect(asText, isNot(contains('typing')));

      final received = await bob.messaging.receive();
      final payload = received.messages.single.payload;
      expect(payload.isTyping, isTrue);
      expect(payload.typingAt, greaterThan(0));
      expect(payload.body, isEmpty);
    });

    test('an empty receipt is not sent at all', () async {
      await alice.messaging.sendReceipt(username: 'bob', clientIds: [], kind: 'read');
      expect(server.envelopes, isEmpty);
    });
  });

  group('voice messages', () {
    test('are sealed before upload, and the server stores audio it cannot play', () async {
      final recorder = FakeVoiceRecorder(duration: const Duration(seconds: 7));
      await recorder.start();
      final recording = await recorder.stop();

      await alice.messaging.sendVoice(
        username: 'bob',
        recording: recording,
        clientId: 'client-1',
      );

      // What the server holds is not the recording.
      final stored = server.media.values.single;
      expect(stored, isNot(recording.bytes));
      expect(stored.length, isNot(recording.bytes.length), reason: 'padded, not passed through');

      // And the envelope says nothing about it either.
      final envelope = utf8.decode(
        base64Decode(server.envelopes.single['content'] as String),
        allowMalformed: true,
      );
      expect(envelope, isNot(contains('audio/mp4')));
    });

    test('carry their duration and waveform inside the sealed payload', () async {
      final recorder = FakeVoiceRecorder(duration: const Duration(seconds: 12));
      await recorder.start();
      final recording = await recorder.stop();

      await alice.messaging.sendVoice(
        username: 'bob',
        recording: recording,
        clientId: 'client-2',
      );

      final received = await bob.messaging.receive();
      final payload = received.messages.single.payload;
      expect(payload.isVoice, isTrue);
      expect(payload.voiceDuration, const Duration(seconds: 12));
      expect(payload.waveform, hasLength(VoiceLimits.waveformBars));
      expect(payload.clientId, 'client-2');

      final opened = await bob.messaging.openAttachment(payload);
      expect(opened, recording.bytes, reason: 'the recording survives the round trip intact');
    });

    test('a tampered recording will not open', () async {
      final recorder = FakeVoiceRecorder();
      await recorder.start();
      final recording = await recorder.stop();
      await alice.messaging.sendVoice(
        username: 'bob',
        recording: recording,
        clientId: 'client-3',
      );

      final id = server.media.keys.single;
      final tampered = Uint8List.fromList(server.media[id]!);
      tampered[tampered.length - 3] ^= 0xFF;
      server.media[id] = tampered;

      final received = await bob.messaging.receive();
      expect(
        () => bob.messaging.openAttachment(received.messages.single.payload),
        throwsA(anything),
        reason: 'a modified recording must fail loudly, not play something else',
      );
    });

    test('a retry after a lost answer does not arrive twice', () async {
      final recorder = FakeVoiceRecorder();
      await recorder.start();
      final recording = await recorder.stop();

      // The first attempt queues the envelopes and then the connection dies.
      server.failuresAfterQueueing = 1;
      await expectLater(
        alice.messaging.sendVoice(
          username: 'bob',
          recording: recording,
          clientId: 'client-retry',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(server.envelopes, hasLength(1));

      // The retry carries the same client id, so the server recognises it.
      await alice.messaging.sendVoice(
        username: 'bob',
        recording: recording,
        clientId: 'client-retry',
      );
      expect(server.envelopes, hasLength(1), reason: 'no second copy was queued');

      final received = await bob.messaging.receive();
      expect(received.messages, hasLength(1));
    });

    test('a disappearing timer travels with the message, not with the server', () async {
      final recorder = FakeVoiceRecorder();
      await recorder.start();
      final recording = await recorder.stop();

      await alice.messaging.sendVoice(
        username: 'bob',
        recording: recording,
        clientId: 'client-4',
        expiresInSeconds: 30,
      );

      // Nothing about the timer is visible from outside the envelope: it is
      // not a column on the row, and the row's bytes do not read as the
      // payload. Searching that ciphertext for "30" would be the wrong test —
      // two given characters turn up in a few hundred random bytes often
      // enough to fail a run for no reason.
      final row = server.envelopes.single;
      expect(row.keys, isNot(contains('expiresAt')));
      expect(row.keys, isNot(contains('expiresInSeconds')));
      final envelope = utf8.decode(
        base64Decode(row['content'] as String),
        allowMalformed: true,
      );
      expect(envelope, isNot(contains('client-4')));
      expect(envelope, isNot(contains('expiresInSeconds')));

      final received = await bob.messaging.receive();
      expect(received.messages.single.payload.expiresInSeconds, 30);
    });

    test('a voice message to a group is uploaded once', () async {
      final group = await alice.messaging.createGroup('Chor', [bob.accountId]);
      final recorder = FakeVoiceRecorder();
      await recorder.start();
      final recording = await recorder.stop();

      await alice.messaging.sendVoiceToGroup(
        groupId: group.groupId,
        recording: recording,
        clientId: 'client-5',
        groupKey: group.groupKey,
      );

      expect(server.media, hasLength(1));
      final received = await bob.messaging.receive();
      expect(received.messages.single.payload.isVoice, isTrue);
      expect(received.messages.single.groupId, group.groupId);
    });
  });

  test('a group send does not burn a prekey when a session already exists', () async {
    final group = await alice.messaging.createGroup('Sparsam', [bob.accountId]);
    final before = server.accounts['bob']!.devices.single.preKeys.length;

    // First send has no session and legitimately fetches a bundle.
    await alice.messaging.sendToGroup(group.groupId, 'eins', groupKey: group.groupKey);
    final afterFirst = server.accounts['bob']!.devices.single.preKeys.length;
    expect(afterFirst, before - 1);

    // The second reuses the session rather than draining the pool.
    await alice.messaging.sendToGroup(group.groupId, 'zwei', groupKey: group.groupKey);
    expect(server.accounts['bob']!.devices.single.preKeys.length, afterFirst);
  });
}
