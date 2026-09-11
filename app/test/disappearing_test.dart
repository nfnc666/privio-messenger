import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';
import 'package:privio/core/message_search.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/widgets/disappearing_timer_sheet.dart';

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

  group('when the clock starts', () {
    test('a message that failed to send has no timer running on it', () async {
      // Otherwise the retry deletes itself out from under the person who was
      // about to press it, and takes what they wrote with it.
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)
        ..setDisappearAfter('account-bob', const Duration(seconds: 30));
      messaging.failSends = true;

      await controller.send('account-bob', 'ging nicht raus');

      final failed = store.conversationWith('account-bob')!.messages.last;
      expect(failed.state, DeliveryState.failed);
      expect(failed.expiresAt, isNull);
      expect(
        store.pruneExpired(DateTime.now().add(const Duration(hours: 1))),
        isEmpty,
        reason: 'it is still the sender\'s to retry',
      );
    });

    test('and starts it when the server takes it', () async {
      final store = withBob();
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)
        ..setDisappearAfter('account-bob', const Duration(seconds: 30));

      await controller.send('account-bob', 'ging raus');

      final sent = store.conversationWith('account-bob')!.messages.last;
      expect(sent.state, DeliveryState.sent);
      expect(sent.expiresAt, isNotNull);
      expect(sent.expiresAt!.difference(DateTime.now()).inSeconds, closeTo(30, 2));
    });
  });

  group('what the brief asks to be verified', () {
    test('the sheet offers exactly the durations that were asked for', () {
      expect(DisappearingTimerSheet.options.keys.toList(), [
        'Off', '30 seconds', '1 minute', '5 minutes', '1 hour', '24 hours', '7 days',
      ]);
      expect(DisappearingTimerSheet.options['Off'], isNull);
      expect(DisappearingTimerSheet.options['24 hours'], const Duration(hours: 24));
      expect(DisappearingTimerSheet.options['7 days'], const Duration(days: 7));
    });

    test('the button wears a label short enough to sit beside its icon', () {
      expect(DisappearingTimerSheet.badge(const Duration(seconds: 30)), '30s');
      expect(DisappearingTimerSheet.badge(const Duration(minutes: 1)), '1m');
      expect(DisappearingTimerSheet.badge(const Duration(hours: 24)), '1d');
      expect(DisappearingTimerSheet.badge(const Duration(days: 7)), '7d');
    });

    test('an expired message never reaches search, swept or not', () {
      final store = withBob();
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      store.append(
        'account-bob',
        Message(
          id: 'm1',
          body: 'the secret recipe',
          sentAt: DateTime.now().subtract(const Duration(minutes: 5)),
          isMine: false,
          expiresAt: past,
        ),
      );

      // Deliberately *not* pruned first. The sweep runs every few seconds, and
      // in the gap between expiry and the next pass the message is still in the
      // store — search must not be the one place it surfaces after its time.
      expect(store.conversationWith('account-bob')!.messages, isNotEmpty);
      expect(MessageSearch.run(store.conversations(), 'recipe'), isEmpty);
    });

    test('and a message still running is found', () {
      final store = withBob();
      store.append(
        'account-bob',
        Message(
          id: 'm1',
          body: 'the secret recipe',
          sentAt: DateTime.now(),
          isMine: false,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      expect(MessageSearch.run(store.conversations(), 'recipe'), hasLength(1));
    });

    test('a restart does not bring back what expired while the app was closed',
        () async {
      final store = withBob();
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-me';
      store.append(
        'account-bob',
        Message(
          id: 'gone',
          body: 'only for a moment',
          sentAt: DateTime.now().subtract(const Duration(hours: 2)),
          isMine: true,
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
      store.append(
        'account-bob',
        Message(id: 'stays', body: 'no timer', sentAt: DateTime.now(), isMine: true),
      );
      // Sealed to disk with the expired message still in it, which is the
      // point: the archive is written before the timer runs out, so only the
      // restore can be what drops it.
      await controller.flush();

      // A new run over the same archive: the app was killed, the clock moved
      // on, and what had run out must not come back on the next launch.
      store.clear();
      final restarted = ConversationController(services)..accountId = 'account-me';
      await restarted.restore();

      final bodies = store
          .conversationWith('account-bob')!
          .messages
          .map((m) => m.body)
          .toList();
      expect(bodies, contains('no timer'));
      expect(bodies, isNot(contains('only for a moment')));
    });

    test('turning the timer off stops new messages carrying one', () async {
      final store = withBob();
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-me';

      controller.setDisappearAfter('account-bob', const Duration(minutes: 1));
      expect(controller.disappearAfter('account-bob'), const Duration(minutes: 1));

      controller.setDisappearAfter('account-bob', null);
      expect(controller.disappearAfter('account-bob'), isNull);
      // Two notices, because both changes are announced — silence about a chat
      // that has started or stopped deleting itself is the dangerous case.
      expect(notices(store), hasLength(2));
    });
  });

  group('a change that has to reach the other side', () {
    test('goes out as its own payload, without waiting for a message', () async {
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);

      await controller.setDisappearAfter('account-bob', const Duration(minutes: 5));

      final announcement = messaging.sent.single;
      expect(announcement.isTimerChange, isTrue);
      expect(announcement.expiresInSeconds, 300);
      expect(
        announcement.isControl,
        isTrue,
        reason: 'it is a setting, and must not land as an empty bubble',
      );
    });

    test('and says so again when it is switched off', () async {
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);

      await controller.setDisappearAfter('account-bob', const Duration(minutes: 5));
      await controller.setDisappearAfter('account-bob', null);

      expect(messaging.sent, hasLength(2));
      expect(messaging.sent.last.isTimerChange, isTrue);
      expect(messaging.sent.last.expiresInSeconds, isNull);
    });

    test('a change that could not go out still stands here', () async {
      // The setting protects what this device sends from now on, and it rides
      // inside those messages anyway. Rolling it back because the announcement
      // failed would be the wrong half to undo.
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.failSends = true;

      final changed =
          await controller.setDisappearAfter('account-bob', const Duration(minutes: 5));

      expect(changed, isTrue);
      expect(controller.disappearAfter('account-bob'), const Duration(minutes: 5));
    });

    test('one arriving moves the timer and writes a notice, not a message', () async {
      final store = withBob();
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services);
      messaging.inbox.add(
        IncomingMessage(
          envelopeId: 1,
          senderAccountId: 'account-bob',
          payload: const MessagePayload.timerChange(60),
          receivedAt: DateTime.now(),
        ),
      );

      await controller.drain();

      expect(controller.disappearAfter('account-bob'), const Duration(minutes: 1));
      final messages = store.conversationWith('account-bob')!.messages;
      expect(messages.single.isNotice, isTrue);
      expect(messages.single.body, contains('1 minute'));
    });
  });

  group('a group timer is the group\'s to set', () {
    InMemoryMessageStore withGroup({required String role}) => InMemoryMessageStore()
      ..upsertUser(const KnownUser(accountId: 'account-bob', username: 'bob'))
      ..upsertGroup(GroupInfo(groupId: 'group-1', role: role, name: 'Team'));

    test('an admin may change it', () async {
      final store = withGroup(role: 'admin');
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-me';

      expect(controller.mayChangeDisappearAfter('group-1'), isTrue);
      expect(
        await controller.setDisappearAfter('group-1', const Duration(hours: 1)),
        isTrue,
      );
      expect(messaging.sentToGroup.single.isTimerChange, isTrue);
    });

    test('a member may not, and nothing is written as if they had', () async {
      final store = withGroup(role: 'member');
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-me';

      expect(controller.mayChangeDisappearAfter('group-1'), isFalse);
      expect(
        await controller.setDisappearAfter('group-1', const Duration(hours: 1)),
        isFalse,
      );
      expect(controller.disappearAfter('group-1'), isNull);
      expect(messaging.sentToGroup, isEmpty);
      expect(store.conversationWith('group-1')!.messages, isEmpty);
    });

    test('a change from a member is ignored on arrival, whatever they sent', () async {
      // The check that matters, because the other one is only a screen. A
      // patched client can send this payload; every device that receives it
      // asks the server who is an admin before acting on it.
      final store = withGroup(role: 'admin');
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-me';
      messaging.members = const [
        GroupMember(accountId: 'account-me', username: 'me', role: 'admin'),
        GroupMember(accountId: 'account-bob', username: 'bob', role: 'member'),
      ];
      messaging.inbox.add(
        IncomingMessage(
          envelopeId: 1,
          senderAccountId: 'account-bob',
          groupId: 'group-1',
          payload: const MessagePayload.timerChange(60),
          receivedAt: DateTime.now(),
        ),
      );

      await controller.drain();

      expect(controller.disappearAfter('group-1'), isNull);
      expect(store.conversationWith('group-1')!.messages, isEmpty);
    });

    test('and applied when it comes from an admin', () async {
      final store = withGroup(role: 'member');
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-me';
      messaging.members = const [
        GroupMember(accountId: 'account-bob', username: 'bob', role: 'admin'),
      ];
      messaging.inbox.add(
        IncomingMessage(
          envelopeId: 1,
          senderAccountId: 'account-bob',
          groupId: 'group-1',
          payload: const MessagePayload.timerChange(60),
          receivedAt: DateTime.now(),
        ),
      );

      await controller.drain();

      expect(controller.disappearAfter('group-1'), const Duration(minutes: 1));
      expect(store.conversationWith('group-1')!.messages.single.isNotice, isTrue);
    });

    test('an ordinary group message cannot drift the timer on its own', () async {
      // It used to: every arriving payload carried the sender's number and the
      // receiver adopted it, which handed every member the setting one message
      // at a time — and checking a role per message would be a request to the
      // server for each one.
      final store = withGroup(role: 'member');
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-me';
      messaging.members = const [
        GroupMember(accountId: 'account-bob', username: 'bob', role: 'member'),
      ];
      messaging.inbox.add(
        IncomingMessage(
          envelopeId: 1,
          senderAccountId: 'account-bob',
          groupId: 'group-1',
          payload: const MessagePayload.text('hallo', clientId: 'c1', expiresInSeconds: 30),
          receivedAt: DateTime.now(),
        ),
      );

      await controller.drain();

      expect(controller.disappearAfter('group-1'), isNull);
      final messages = store.conversationWith('group-1')!.messages;
      expect(messages.single.body, 'hallo');
      expect(messages.single.expiresAt, isNull, reason: 'the group has no timer');
    });
  });

  group('a backup is not a way back in', () {
    test('a restored history does not bring expired messages with it', () async {
      // A backup is a snapshot of a moment, and a message that has run out
      // since is still gone: restoring one would undo the whole feature with a
      // single tap, on a copy the sender never agreed to.
      final store = withBob();
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-me';

      // What the backup service does: it replaces the store's contents, then
      // hands them over.
      store.append(
        'account-bob',
        Message(
          id: 'expired',
          body: 'aus dem Backup',
          sentAt: DateTime.now().subtract(const Duration(days: 2)),
          isMine: false,
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );
      store.append(
        'account-bob',
        Message(
          id: 'kept',
          body: 'ohne Timer',
          sentAt: DateTime.now().subtract(const Duration(days: 2)),
          isMine: false,
        ),
      );

      await controller.adoptRestored();

      final bodies =
          store.conversationWith('account-bob')!.messages.map((m) => m.body).toList();
      expect(bodies, ['ohne Timer']);
    });
  });

  group('one account\'s timer is not another\'s', () {
    test('signing in as somebody else starts from their own archive', () async {
      // The timer is a property of a conversation in an account's sealed
      // archive, keyed by account id — so it cannot cross, and this is the test
      // that says so rather than the comment.
      final store = withBob();
      final (services, _) = await buildServices(store);
      final alice = ConversationController(services)..accountId = 'account-alice';
      await alice.setDisappearAfter('account-bob', const Duration(hours: 1));
      await alice.flush();

      store.clear();
      final carol = ConversationController(services)..accountId = 'account-carol';
      await carol.restore();

      expect(
        carol.disappearAfter('account-bob'),
        isNull,
        reason: "carol's archive is empty; alice's is not hers to read",
      );
    });
  });
}
