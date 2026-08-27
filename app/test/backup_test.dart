import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/data/backup.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/data/recovery_key.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/backup_service.dart';

/// Holds one blob, the way the real endpoint does.
class FakeBackupServer {
  Uint8List? stored;
  int version = 0;

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'PUT' && path == '/v1/backup') {
          stored = Uint8List.fromList(request.bodyBytes);
          version += 1;
          return _json({'stored': true, 'version': version, 'byteSize': stored!.length});
        }
        if (request.method == 'GET' && path == '/v1/backup') {
          if (stored == null) {
            return _json({'error': 'no_backup', 'message': 'No backup stored'}, 404);
          }
          return _json({
            'byteSize': stored!.length,
            'version': version,
            'updatedAt': DateTime.utc(2026, 5, 1, 9).toIso8601String(),
          });
        }
        if (request.method == 'GET' && path == '/v1/backup/content') {
          if (stored == null) {
            return _json({'error': 'no_backup', 'message': 'No backup stored'}, 404);
          }
          return http.Response.bytes(stored!, 200);
        }
        return _json({'error': 'not_found', 'message': path}, 404);
      });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

List<Conversation> sampleHistory() => [
      Conversation.direct(
        const KnownUser(accountId: 'acc-alice', username: 'alice', displayName: 'Alice'),
        messages: [
          Message(
            id: '1',
            body: 'Treffen um 19 Uhr am üblichen Ort',
            sentAt: DateTime.utc(2026, 3, 4, 18, 30),
            isMine: false,
          ),
          Message(
            id: '2',
            body: '',
            sentAt: DateTime.utc(2026, 3, 4, 18, 32),
            isMine: true,
            kind: MessageKind.voice,
            voiceDuration: const Duration(seconds: 6),
            waveform: const [0.3, 0.7],
            attachment: const Attachment(
              mediaId: 'media-9',
              mediaKey: 'SEHR-GEHEIM',
              mediaType: 'audio/mp4',
              byteSize: 4096,
            ),
          ),
        ],
      )..unreadCount = 1,
    ];

({BackupService service, FakeBackupServer server, InMemoryMessageStore store})
    buildService() {
  final server = FakeBackupServer();
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: server.client(),
  )..useToken('token');
  final store = InMemoryMessageStore();
  return (
    service: BackupService(api: api, store: InMemorySecureStore(), messages: store),
    server: server,
    store: store,
  );
}

void main() {
  group('the recovery key', () {
    test('is 256 bits, and survives a round trip through its own text', () {
      final key = RecoveryKey.generate();
      expect(key.bytes, hasLength(32));

      final parsed = RecoveryKey.parse(key.formatted);
      expect(parsed, isNotNull);
      expect(parsed!.bytes, key.bytes);
      expect(parsed, key);
    });

    test('two keys are never the same', () {
      final keys = {for (var i = 0; i < 50; i++) RecoveryKey.generate().formatted};
      expect(keys, hasLength(50));
    });

    test('reads back what a person actually types', () {
      final key = RecoveryKey.generate();
      final written = key.formatted;

      // Lower case, spaces instead of dashes, and the letters people write when
      // they mean digits.
      expect(RecoveryKey.parse(written.toLowerCase()), key);
      expect(RecoveryKey.parse(written.replaceAll('-', ' ')), key);
      expect(RecoveryKey.parse(written.replaceAll('-', '')), key);
      expect(
        RecoveryKey.parse(written.replaceAll('0', 'O').replaceAll('1', 'I')),
        key,
        reason: 'O for 0 is a transcription slip, not a wrong key',
      );
    });

    test('rejects what is not a key rather than half-accepting it', () {
      expect(RecoveryKey.parse(''), isNull);
      expect(RecoveryKey.parse('nicht mein schlüssel'), isNull);
      expect(RecoveryKey.parse('ABCD-EFGH'), isNull, reason: 'too short to be one');
    });

    test('is written in an alphabet with no ambiguous letters', () {
      for (final letter in ['I', 'L', 'O', 'U']) {
        expect(RecoveryKey.alphabet, isNot(contains(letter)));
      }
      expect(RecoveryKey.alphabet, hasLength(32));
    });
  });

  group('the backup itself', () {
    test('round-trips a history, voice messages and all', () async {
      final key = RecoveryKey.generate();
      final sealed = await BackupCodec.seal(sampleHistory(), recovery: key);
      final opened = await BackupCodec.open(sealed, key);

      final conversation = opened.conversations.single;
      expect(conversation.user!.username, 'alice');
      expect(conversation.unreadCount, 1);
      expect(conversation.messages.first.body, 'Treffen um 19 Uhr am üblichen Ort');

      final voice = conversation.messages.last;
      expect(voice.isVoice, isTrue);
      expect(voice.voiceDuration, const Duration(seconds: 6));
      expect(voice.waveform, [0.3, 0.7]);
      expect(voice.attachment!.mediaKey, 'SEHR-GEHEIM');
    });

    test('is ciphertext — nothing in it is readable without the key', () async {
      final sealed = await BackupCodec.seal(
        sampleHistory(),
        recovery: RecoveryKey.generate(),
      );
      final asText = utf8.decode(sealed, allowMalformed: true);

      expect(asText, isNot(contains('Treffen')));
      expect(asText, isNot(contains('alice')));
      expect(asText, isNot(contains('SEHR-GEHEIM')));
      expect(asText, isNot(contains('audio/mp4')));
      expect(sealed.first, 1, reason: 'a format version, so the layout can change later');
    });

    test('the wrong key opens nothing', () async {
      final sealed = await BackupCodec.seal(
        sampleHistory(),
        recovery: RecoveryKey.generate(),
      );
      await expectLater(
        BackupCodec.open(sealed, RecoveryKey.generate()),
        throwsA(anything),
      );
    });

    test('a tampered backup is refused rather than half-read', () async {
      final key = RecoveryKey.generate();
      final sealed = await BackupCodec.seal(sampleHistory(), recovery: key);
      sealed[sealed.length - 4] ^= 0xFF;

      await expectLater(BackupCodec.open(sealed, key), throwsA(anything));
    });

    test('the same history sealed twice is never the same bytes', () async {
      final key = RecoveryKey.generate();
      final first = await BackupCodec.seal(sampleHistory(), recovery: key);
      final second = await BackupCodec.seal(sampleHistory(), recovery: key);
      expect(first, isNot(second), reason: 'a fresh nonce each time');
    });
  });

  group('the backup service', () {
    test('uploads ciphertext and reads it back', () async {
      final built = buildService();
      built.store
        ..upsertUser(const KnownUser(accountId: 'acc-alice', username: 'alice'))
        ..append(
          'acc-alice',
          Message(
            id: '1',
            body: 'Treffen um 19 Uhr',
            sentAt: DateTime.utc(2026, 3, 4),
            isMine: false,
          ),
        );

      expect(await built.service.remote(), isNull, reason: 'nothing there yet');
      await built.service.backUpNow();

      // What the server holds gives nothing away.
      final atRest = utf8.decode(built.server.stored!, allowMalformed: true);
      expect(atRest, isNot(contains('Treffen')));
      expect(atRest, isNot(contains('alice')));

      final remote = await built.service.remote();
      expect(remote, isNotNull);
      expect(remote!.byteSize, built.server.stored!.length);
      expect(await built.service.lastBackupAt(), isNotNull);
    });

    test('restores onto a device that has nothing', () async {
      final source = buildService();
      source.store
        ..upsertUser(const KnownUser(accountId: 'acc-alice', username: 'alice'))
        ..append(
          'acc-alice',
          Message(
            id: '1',
            body: 'Bis Sonntag',
            sentAt: DateTime.utc(2026, 3, 4),
            isMine: false,
          ),
        );
      await source.service.backUpNow();
      final key = await source.service.recoveryKey();

      // A second device, same account, empty.
      final target = buildService();
      target.server.stored = source.server.stored;
      target.server.version = source.server.version;
      expect(target.store.conversations(), isEmpty);

      final restored = await target.service.restoreFromServer(key);
      expect(restored.conversations, hasLength(1));
      expect(target.store.conversationWith('acc-alice')!.messages.single.body, 'Bis Sonntag');

      // And it keeps the key, so the next backup from here uses the same one.
      expect(await target.service.recoveryKey(), key);
    });

    test('a restore with the wrong key changes nothing', () async {
      final source = buildService();
      source.store.upsertUser(const KnownUser(accountId: 'acc-alice', username: 'alice'));
      source.store.append(
        'acc-alice',
        Message(id: '1', body: 'geheim', sentAt: DateTime.utc(2026), isMine: false),
      );
      await source.service.backUpNow();

      final target = buildService();
      target.server.stored = source.server.stored;
      target.store.upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'));
      target.store.append(
        'acc-bob',
        Message(id: '9', body: 'bleibt', sentAt: DateTime.utc(2026), isMine: true),
      );

      await expectLater(
        target.service.restoreFromServer(RecoveryKey.generate()),
        throwsA(anything),
      );
      expect(
        target.store.conversationWith('acc-bob')!.messages.single.body,
        'bleibt',
        reason: 'a failed restore must not eat the history that was there',
      );
    });

    test('keeps the same recovery key across calls', () async {
      final built = buildService();
      final first = await built.service.recoveryKey();
      final second = await built.service.recoveryKey();
      expect(second, first, reason: 'a key that changes is a backup that is lost');
    });

    test('automatic backup respects the interval, and Off means off', () async {
      final built = buildService();
      await built.service.setInterval(BackupInterval.off);
      expect(await built.service.backUpIfDue(), isFalse);
      expect(built.server.stored, isNull);

      await built.service.setInterval(BackupInterval.daily);
      expect(await built.service.backUpIfDue(), isTrue);
      expect(built.server.version, 1);

      // Already done today: the second call is a no-op, not a second upload.
      expect(await built.service.backUpIfDue(), isFalse);
      expect(built.server.version, 1);
    });

    test('the QR payload carries the key and nothing else', () {
      final key = RecoveryKey.generate();
      final payload = BackupService.qrPayload(key);

      expect(payload, startsWith('privio://recovery/'));
      expect(BackupService.parseScanned(payload), key);
      // A key typed in by hand works the same way.
      expect(BackupService.parseScanned(key.formatted), key);
      expect(BackupService.parseScanned('nonsense'), isNull);
    });

    test('the file name says when, not who', () {
      final name = BackupService.fileNameFor(DateTime(2026, 5, 9));
      expect(name, 'privio-backup-20260509.privio');
    });
  });
}
