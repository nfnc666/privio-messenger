import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';
import 'package:privio/services/messaging_service.dart';

import 'deletion_test.dart' show buildServices;

/// A message arriving from Bob, carrying whatever timer his device is running.
IncomingMessage arriving({
  required String clientId,
  int? expiresInSeconds,
  String body = 'hallo',
  int envelopeId = 1,
}) =>
    IncomingMessage(
      envelopeId: envelopeId,
      senderAccountId: 'account-bob',
      payload: MessagePayload.text(
        body,
        clientId: clientId,
        expiresInSeconds: expiresInSeconds,
      ),
      receivedAt: DateTime.now(),
    );

InMemoryMessageStore withBob() => InMemoryMessageStore()
  ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'));

List<Message> notices(InMemoryMessageStore store) =>
    store.conversationWith('account-bob')!.messages.where((m) => m.isNotice).toList();

void main() {
  group('the timer itself', () {
    test('reads back the way a person would say it', () {
      expect(ConversationController.describeTimer(const Duration(seconds: 30)), '30 seconds');
      expect(ConversationController.describeTimer(const Duration(minutes: 5)), '5 minutes');
      expect(ConversationController.describeTimer(const Duration(hours: 1)), '1 hour');
      expect(ConversationController.describeTimer(const Duration(days: 1)), '1 day');
      expect(ConversationController.describeTimer(const Duration(days: 7)), '1 week');
      expect(ConversationController.describeTimer(const Duration(days: 14)), '2 weeks');
      expect(ConversationController.describeTimer(const Duration(minutes: 90)), '90 minutes');
    });
  });

  group('a chat that starts deleting itself says so', () {
    test('setting a timer writes a line into the chat', () async {
      final store = withBob();
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services);

      controller.setDisappearAfter('account-bob', const Duration(hours: 1));

      expect(notices(store).single.body, 'You set disappearing messages to 1 hour.');
    });

    test('turning it off says that too, rather than going quiet', () async {
      final store = withBob();
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)
        ..setDisappearAfter('account-bob', const Duration(hours: 1));

      controller.setDisappearAfter('account-bob', null);

      expect(notices(store).last.body, 'You turned disappearing messages off.');
    });

    test('setting the same timer again writes nothing', () async {
      final store = withBob();
      final (services, _) = await buildServices(store);
      ConversationController(services)
        ..setDisappearAfter('account-bob', const Duration(hours: 1))
        ..setDisappearAfter('account-bob', const Duration(hours: 1));

      expect(notices(store), hasLength(1));
    });

    test('a timer arriving from the other side is announced, not adopted in silence', () async {
      // The case this exists for: someone keeps writing without knowing that
      // what they write now deletes itself.
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox.add(arriving(clientId: 'c1', expiresInSeconds: 300));

      await controller.drain();

      expect(notices(store).single.body, 'bob set disappearing messages to 5 minutes.');
      expect(controller.disappearAfter('account-bob'), const Duration(minutes: 5));
    });

    test('a notice is not a message anyone has to read', () async {
      final store = withBob();
      final (services, _) = await buildServices(store);
      ConversationController(services).setDisappearAfter('account-bob', const Duration(hours: 1));

      expect(store.conversationWith('account-bob')!.unreadCount, 0);
    });

    test('the notice outlives the messages it describes', () async {
      // A record that deletes itself under the rule it announces leaves a
      // history nobody can account for.
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox.add(arriving(clientId: 'c1', expiresInSeconds: 30));
      await controller.drain();

      final gone = store.pruneExpired(DateTime.now().add(const Duration(minutes: 1)));

      expect(gone.single.body, 'hallo');
      expect(store.conversationWith('account-bob')!.messages.single.isNotice, isTrue);
    });
  });

  group('what expiry actually removes', () {
    test('an expired message takes its decrypted file with it', () async {
      // The bubble disappearing while the photo stays decrypted in memory is
      // the version of this feature that does not work: the file would still be
      // one tap away in the gallery for the rest of the session.
      //
      // Tested through the door rather than through a test hook: the blob is
      // served once and then withdrawn, so a second read that succeeds could
      // only have come from the cache.
      final store = withBob();
      final sealed = await AttachmentCipher.seal(Uint8List.fromList(List.filled(64, 7)));
      var serving = true;
      final (services, _) = await buildServices(
        store,
        client: MockClient((request) async {
          if (serving && request.url.path.startsWith('/v1/media/')) {
            return http.Response.bytes(sealed.bytes, 200);
          }
          return http.Response(
            '{"error":"gone","message":"gone"}',
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final controller = ConversationController(services);

      final attachment = Attachment(
        mediaId: 'media-1',
        mediaKey: base64Encode(sealed.key),
        mediaType: 'image/jpeg',
        byteSize: sealed.plainLength,
      );
      store.append(
        'account-bob',
        Message(
          id: 'envelope-1',
          clientId: 'c1',
          body: '',
          sentAt: DateTime.now(),
          isMine: false,
          kind: MessageKind.photo,
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
          attachment: attachment,
        ),
      );

      expect(await controller.attachmentBytes(attachment), isNotNull, reason: 'opened once');
      serving = false;
      // Still cached, so the withdrawal alone proves nothing yet.
      expect(await controller.attachmentBytes(attachment), isNotNull);

      controller.pruneExpired();

      expect(store.conversationWith('account-bob')!.messages, isEmpty);
      expect(
        await controller.attachmentBytes(attachment),
        isNull,
        reason: 'the plaintext must not survive the message',
      );
    });
  });
}
