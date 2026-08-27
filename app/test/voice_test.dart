import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/data/outbox.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/media/voice.dart';
import 'package:privio/media/voice_recorder.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/models/models.dart';

import 'support/fake_voice.dart';

void main() {
  group('recording lifecycle', () {
    test('runs start, pause, resume and stop', () async {
      final recorder = FakeVoiceRecorder(duration: const Duration(seconds: 4));

      expect(recorder.isRecording, isFalse);
      await recorder.start();
      expect(recorder.isRecording, isTrue);

      await recorder.pause();
      expect(recorder.isPaused, isTrue);
      await recorder.resume();
      expect(recorder.isPaused, isFalse);

      final recording = await recorder.stop();
      expect(recorder.isRecording, isFalse);
      expect(recording.duration, const Duration(seconds: 4));
      expect(recording.mediaType, startsWith('audio/'));
    });

    test('cancelling throws the recording away', () async {
      final recorder = FakeVoiceRecorder();
      await recorder.start();
      await recorder.cancel();

      expect(recorder.isRecording, isFalse);
      expect(recorder.discarded, isTrue, reason: 'the working file is not kept');
      // Nothing to stop any more.
      expect(recorder.stop, throwsA(isA<VoiceRecorderException>()));
    });

    test('a refused microphone fails as a permission problem, not a crash', () async {
      final recorder = FakeVoiceRecorder(permitted: false);
      expect(await recorder.ensurePermission(), isFalse);
      await expectLater(
        recorder.start(),
        throwsA(
          isA<VoiceRecorderException>().having(
            (e) => e.reason,
            'reason',
            VoiceRecorderFailure.permissionDenied,
          ),
        ),
      );
    });

    test('a tap rather than a hold is refused as too short', () async {
      final recorder = FakeVoiceRecorder(duration: const Duration(milliseconds: 120));
      await recorder.start();
      await expectLater(
        recorder.stop(),
        throwsA(
          isA<VoiceRecorderException>()
              .having((e) => e.reason, 'reason', VoiceRecorderFailure.tooShort),
        ),
      );
    });

    test('a recording over the size limit is refused before it is sent', () async {
      final recorder = FakeVoiceRecorder(
        bytes: Uint8List(VoiceLimits.maxBytes + 1),
        duration: const Duration(seconds: 10),
      );
      await recorder.start();
      await expectLater(
        recorder.stop(),
        throwsA(
          isA<VoiceRecorderException>()
              .having((e) => e.reason, 'reason', VoiceRecorderFailure.tooLarge),
        ),
      );
    });
  });

  group('waveform', () {
    test('is reduced to a fixed number of bars, whatever was sampled', () {
      for (final sampleCount in [3, 50, 400]) {
        final bars = compressWaveform(
          List<double>.generate(sampleCount, (i) => (i % 7) / 7),
        );
        expect(bars, hasLength(VoiceLimits.waveformBars));
        expect(bars.every((bar) => bar >= 0 && bar <= 1), isTrue);
      }
    });

    test('normalises, so a quiet recording still looks like speech', () {
      final quiet = compressWaveform(List<double>.generate(100, (i) => (i % 5) / 500));
      expect(quiet.reduce((a, b) => a > b ? a : b), closeTo(1, 0.001));
    });

    test('silence stays silent rather than being amplified into noise', () {
      final silence = compressWaveform(List<double>.filled(100, 0));
      expect(silence.every((bar) => bar == 0), isTrue);
    });
  });

  group('encryption', () {
    test('a recording is unreadable without its key, and intact with it', () async {
      final recorder = FakeVoiceRecorder();
      await recorder.start();
      final recording = await recorder.stop();

      final sealed = await AttachmentCipher.seal(
        recording.bytes,
        declaredType: recording.mediaType,
      );

      expect(sealed.bytes, isNot(recording.bytes));
      final wrongKey = Uint8List(32);
      await expectLater(
        AttachmentCipher.open(sealed.bytes, wrongKey),
        throwsA(anything),
      );
      expect(await AttachmentCipher.open(sealed.bytes, sealed.key), recording.bytes);
    });

    test('two recordings of the same audio seal differently', () async {
      final recorder = FakeVoiceRecorder();
      await recorder.start();
      final recording = await recorder.stop();

      final first = await AttachmentCipher.seal(recording.bytes);
      final second = await AttachmentCipher.seal(recording.bytes);
      expect(first.bytes, isNot(second.bytes));
      expect(first.key, isNot(second.key), reason: 'a fresh random key each time');
    });
  });

  group('the outbox', () {
    PendingSend pendingOf({String clientId = 'c1', String? mediaId}) => PendingSend(
          clientId: clientId,
          conversationId: 'account-bob',
          isGroup: false,
          username: 'bob',
          mediaType: 'audio/mp4',
          sealedBytes: Uint8List.fromList([1, 2, 3, 4]),
          mediaKey: 'a2V5',
          plainLength: 4,
          durationMs: 3000,
          waveform: const [0.1, 0.9],
          mediaId: mediaId,
          expiresInSeconds: 30,
        );

    test('survives being written and read back', () {
      final restored = PendingSend.fromJson(pendingOf(mediaId: 'media-1').toJson());
      expect(restored.clientId, 'c1');
      expect(restored.username, 'bob');
      expect(restored.mediaId, 'media-1');
      expect(restored.sealedBytes, [1, 2, 3, 4]);
      expect(restored.expiresInSeconds, 30);
      expect(restored.duration, const Duration(seconds: 3));
    });

    test('what it persists is ciphertext, never the recording', () async {
      final recorder = FakeVoiceRecorder();
      await recorder.start();
      final recording = await recorder.stop();
      final sealed = await AttachmentCipher.seal(recording.bytes);

      final pending = PendingSend(
        clientId: 'c2',
        conversationId: 'account-bob',
        isGroup: false,
        username: 'bob',
        mediaType: 'audio/mp4',
        sealedBytes: sealed.bytes,
        mediaKey: 'irrelevant',
        plainLength: sealed.plainLength,
        durationMs: 1000,
        waveform: const [],
      );

      final written = pending.toJson()['sealedBytes'] as String;
      expect(written, isNot(contains(String.fromCharCodes(recording.bytes.take(8)))));
      expect(PendingSend.fromJson(pending.toJson()).sealedBytes, sealed.bytes);
    });

    test('a queue entry remembers its upload, so a retry does not repeat it', () {
      final pending = pendingOf();
      expect(pending.mediaId, isNull);
      expect(pending.copyWith(mediaId: 'media-9').mediaId, 'media-9');
      expect(pending.copyWith(attempts: 3).attempts, 3);
      expect(pending.copyWith(attempts: 3).mediaId, isNull);
    });
  });

  group('disappearing messages', () {
    Message voiceAt(DateTime expiresAt) => Message(
          id: 'm1',
          body: '',
          sentAt: DateTime(2026),
          isMine: false,
          kind: MessageKind.voice,
          voiceDuration: const Duration(seconds: 5),
          expiresAt: expiresAt,
        );

    test('a message with no timer never expires', () {
      final message = Message(
        id: 'm0',
        body: 'bleibt',
        sentAt: _fixedDate,
        isMine: false,
      );
      expect(message.hasExpiredAt(DateTime(2099)), isFalse);
    });

    test('expires exactly when its time is up', () {
      final message = voiceAt(DateTime(2026, 1, 1, 12));
      expect(message.hasExpiredAt(DateTime(2026, 1, 1, 11, 59, 59)), isFalse);
      expect(message.hasExpiredAt(DateTime(2026, 1, 1, 12)), isTrue);
      expect(message.hasExpiredAt(DateTime(2026, 1, 1, 12, 0, 1)), isTrue);
    });

    test('the store drops what has run out and keeps the rest', () {
      final store = InMemoryMessageStore()
        ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));

      store
        ..append('account-bob', voiceAt(DateTime(2026, 1, 1, 12)))
        ..append(
          'account-bob',
          Message(id: 'm2', body: 'bleibt', sentAt: _fixedDate, isMine: false),
        );
      expect(store.conversationWith('account-bob')!.messages, hasLength(2));

      final removed = store.pruneExpired(DateTime(2026, 1, 1, 13));
      expect(removed, 1);
      final left = store.conversationWith('account-bob')!.messages;
      expect(left, hasLength(1));
      expect(left.single.body, 'bleibt');
    });

    test('the timer survives a restart, along with the voice message itself', () async {
      final storage = InMemoryArchiveStorage();
      final archive = EncryptedMessageArchive(
        storage: storage,
        keyStore: InMemorySecureStore(),
      );

      final conversation = Conversation.direct(
        const KnownUser(accountId: 'account-bob', username: 'bob'),
        messages: [
          Message(
            id: 'v1',
            clientId: 'client-v1',
            body: '',
            sentAt: DateTime(2026, 3, 1, 9, 30),
            isMine: true,
            kind: MessageKind.voice,
            state: DeliveryState.sent,
            voiceDuration: const Duration(seconds: 9),
            waveform: const [0.2, 0.8, 0.4],
            expiresAt: DateTime(2026, 3, 1, 9, 31),
            attachment: const Attachment(
              mediaId: 'media-1',
              mediaKey: 'a2V5',
              mediaType: 'audio/mp4',
              byteSize: 4096,
            ),
          ),
        ],
      )..disappearAfter = const Duration(seconds: 30);

      await archive.save([conversation]);

      // What sits at rest is ciphertext, waveform and all.
      final atRest = String.fromCharCodes(storage.bytes!);
      expect(atRest, isNot(contains('audio/mp4')));
      expect(atRest, isNot(contains('client-v1')));

      final restored = (await archive.load()).conversations.single;
      final message = restored.messages.single;
      expect(restored.disappearAfter, const Duration(seconds: 30));
      expect(message.isVoice, isTrue);
      expect(message.voiceDuration, const Duration(seconds: 9));
      expect(message.waveform, [0.2, 0.8, 0.4]);
      expect(message.expiresAt, DateTime(2026, 3, 1, 9, 31));
      expect(message.attachment!.mediaId, 'media-1');
    });

    test('the outbox is written and read back with the history', () async {
      final archive = EncryptedMessageArchive(
        storage: InMemoryArchiveStorage(),
        keyStore: InMemorySecureStore(),
      );
      await archive.save(
        [],
        outbox: [
          PendingSend(
            clientId: 'queued-1',
            conversationId: 'account-bob',
            isGroup: false,
            username: 'bob',
            mediaType: 'audio/mp4',
            sealedBytes: Uint8List.fromList([9, 9, 9]),
            mediaKey: 'a2V5',
            plainLength: 3,
            durationMs: 2000,
            waveform: const [0.5],
          ),
        ],
      );

      final contents = await archive.load();
      expect(contents.outbox.single.clientId, 'queued-1');
      expect(contents.outbox.single.sealedBytes, [9, 9, 9]);
    });
  });

  group('duplicate delivery', () {
    test('the same message arriving twice is filed once', () {
      final store = InMemoryMessageStore()
        ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));

      final message = Message(
        id: 'envelope-1',
        clientId: 'client-dup',
        body: 'einmal',
        sentAt: _fixedDate,
        isMine: false,
      );
      final again = Message(
        id: 'envelope-2',
        clientId: 'client-dup',
        body: 'einmal',
        sentAt: _fixedDate,
        isMine: false,
      );

      store
        ..append('account-bob', message)
        ..append('account-bob', again);

      expect(store.conversationWith('account-bob')!.messages, hasLength(1));
    });
  });
}

final DateTime _fixedDate = DateTime(2026);
