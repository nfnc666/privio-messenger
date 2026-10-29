import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/failure.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/screen_shield_controller.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/backup.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/data/recovery_key.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/media/photo_source.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/security/screen_shield.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/widgets/message_bubble.dart';
import 'package:privio/widgets/photo_preview_sheet.dart';
import 'package:privio/widgets/view_once_viewer.dart';

import 'deletion_test.dart' show storeWith;
import 'photo_send_test.dart' show jpeg, prepared;
import 'screen_shield_test.dart' show FakeShield;
import 'support/fake_server.dart';
import 'support/fake_voice.dart';
import 'voice_outbox_test.dart' as outbox show buildServices;
import 'widget_test.dart' show wrap;

/// A photo the recipient can open once. What it promises, and what each part
/// below holds it to:
///
/// * an older build cannot show it, because it is a type such a build reads
///   as text;
/// * the sender keeps no key, on any of its devices;
/// * the recipient's key is dropped, and written down dropped, before the
///   picture is shown, and the account's other devices are told;
/// * nothing copies it: not Saved, not a backup, not a forged copy from
///   somebody pretending to be this account's other device.

const _older = '📷 Update Privio to open it.';

MessagePayload _once({String clientId = 'v1', String key = 'a2V5', String? body}) => MessagePayload.media(
      mediaId: 'media-1',
      mediaKey: key,
      mediaToken: 'token-1',
      mediaType: 'image/jpeg',
      byteSize: 1234,
      fileName: 'photo-1.jpg',
      body: body ?? _older,
      clientId: clientId,
      viewOnce: true,
    );

IncomingMessage _arriving(
  MessagePayload payload, {
  String from = 'account-bob',
  int envelope = 7,
  String? groupId,
}) =>
    IncomingMessage(
      envelopeId: envelope,
      senderAccountId: from,
      // As it arrives: read off the wire, which is where the text for older
      // builds is dropped.
      payload: MessagePayload.decode(payload.encode()),
      receivedAt: DateTime.now(),
      groupId: groupId,
    );

IncomingMessage _fromMyOtherDevice(MessagePayload inner, {String conversationId = 'account-bob', int envelope = 8}) =>
    _arriving(
      MessagePayload.sync(SyncEnvelope(conversationId: conversationId, isGroup: false, payload: inner.encode())),
      from: 'account-alice',
      envelope: envelope,
    );

/// Receives what a test puts in front of it, opens attachments to a fixed
/// picture, and remembers what it told this account's other devices.
class OnceMessaging extends MessagingService {
  OnceMessaging({required super.api, required super.crypto});

  final List<IncomingMessage> inbox = [];
  final List<MessagePayload> sent = [];
  final List<({String conversationId, bool isGroup, MessagePayload payload})> told = [];
  final Uint8List picture = Uint8List.fromList(List.generate(64, (i) => i));
  int fetches = 0;
  bool failFetch = false;

  /// Holds a fetch open until completed, for two taps at once.
  Completer<void>? gate;

  @override
  Future<Uint8List> openAttachment(MessagePayload payload) async {
    fetches += 1;
    await gate?.future;
    if (failFetch) throw ApiException(503, 'unavailable', 'no route to host');
    return picture;
  }

  @override
  Future<void> tellOwnDevices({
    required String conversationId,
    required bool isGroup,
    required MessagePayload payload,
  }) async =>
      told.add((conversationId: conversationId, isGroup: isGroup, payload: payload));

  @override
  Future<int> sendPayload(String username, MessagePayload payload) async {
    sent.add(payload);
    return 1;
  }

  @override
  Future<ReceiveResult> receive({int limit = 100}) async {
    final batch = [...inbox];
    inbox.clear();
    return ReceiveResult(batch, const [], false);
  }
}

Future<(PrivioServices, OnceMessaging, InMemoryArchiveStorage)> _receiving(InMemoryMessageStore store) async {
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(
      (request) async => http.Response(
        jsonEncode({'error': 'not_found', 'message': request.url.path}),
        404,
        headers: {'content-type': 'application/json'},
      ),
    ),
  )..useToken('token');
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = OnceMessaging(api: api, crypto: crypto);
  final secureStore = InMemorySecureStore();
  final storage = InMemoryArchiveStorage();
  return (
    PrivioServices(
      api: api,
      crypto: crypto,
      messaging: messaging,
      channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
      recorder: FakeVoiceRecorder(),
      player: FakeVoicePlayer(),
      store: store,
      secureStore: secureStore,
      backup: BackupService(api: api, store: secureStore, messages: store),
      archive: EncryptedMessageArchive(storage: storage, keyStore: InMemorySecureStore()),
    ),
    messaging,
    storage,
  );
}

Future<(ConversationController, InMemoryMessageStore, OnceMessaging, PrivioServices)> _withOneArrived({
  MessagePayload? payload,
}) async {
  final store = storeWith([]);
  final (services, messaging, _) = await _receiving(store);
  final controller = ConversationController(services)..accountId = 'account-alice';
  addTearDown(controller.stop);
  messaging.inbox.add(_arriving(payload ?? _once()));
  await controller.drain();
  return (controller, store, messaging, services);
}

Message _single(InMemoryMessageStore store, [String conversationId = 'account-bob']) =>
    store.conversationWith(conversationId)!.messages.single;

void main() {
  group('on the wire', () {
    test('is its own type, so an older build shows the text and never the picture', () {
      final json = jsonDecode(_once().encode()) as Map<String, dynamic>;
      expect(json['t'], 'once');
      expect(json['b'], _older);
      expect(json['k'], 'a2V5');

      // What any build does with a type it does not know: the text, nothing else.
      final unknown = MessagePayload.decode(jsonEncode({...json, 't': 'from-a-later-build'}));
      expect(unknown.isMedia, isFalse);
      expect(unknown.body, _older);

      final read = MessagePayload.decode(_once().encode());
      expect(read.viewOnce, isTrue);
      expect(read.isMedia, isTrue);
      expect(read.mediaKey, 'a2V5');
      expect(read.body, isEmpty, reason: 'the text for older builds was shown as a caption');
    });

    test('anything but a photo under this type is nothing to open', () {
      final json = jsonDecode(_once().encode()) as Map<String, dynamic>;
      final video = MessagePayload.decode(jsonEncode({...json, 'm': 'video/mp4'}));
      expect(video.viewOnce, isTrue);
      expect(video.isMedia, isFalse);
      expect(video.mediaKey, isNull);
    });

    test('attaching the profile key keeps it a photo to be viewed once', () {
      final keyed = _once().withProfileKey('cHJvZmlsZQ==');
      expect(keyed.viewOnce, isTrue);
      expect(keyed.mediaKey, 'a2V5');
      expect(keyed.body, _older);
      expect((jsonDecode(keyed.encode()) as Map)['t'], 'once');
    });

    test('the copy for the sender’s own devices has nothing to open it with', () {
      final copy = _once().withoutViewOnceKey();
      final json = jsonDecode(copy.encode()) as Map<String, dynamic>;
      expect(json['t'], 'once');
      expect(json.keys, isNot(contains('id')));
      expect(json.keys, isNot(contains('k')));
      expect(json.keys, isNot(contains('tk')));
      final read = MessagePayload.decode(copy.encode());
      expect(read.viewOnce, isTrue);
      expect(read.isMedia, isFalse);
      expect(read.clientId, 'v1');
    });
  });

  group('between devices', () {
    late FakeServer server;
    late Participant alice;
    late Participant laptop;
    late Participant bob;

    setUp(() async {
      server = FakeServer();
      alice = Participant('alice', 'account-alice', 1);
      laptop = Participant('alice', 'account-alice', 2);
      bob = Participant('bob', 'account-bob', 1);
      await alice.join(server);
      await laptop.join(server);
      await bob.join(server);
    });

    test('reaches the recipient with its key, and the sender’s other device without', () async {
      await alice.messaging.sendPayload('bob', _once());

      final forBob = (await bob.messaging.receive()).messages.single.payload;
      expect(forBob.viewOnce, isTrue);
      expect(forBob.mediaKey, 'a2V5');

      final copy = (await laptop.messaging.receive()).messages.single.payload.sync!.inner;
      expect(copy.viewOnce, isTrue);
      expect(copy.mediaKey, isNull, reason: 'the sender’s other device could open it');
      expect(copy.mediaId, isNull);
    });

    test('“opened” reaches this account’s other devices, and nobody else', () async {
      await alice.messaging.tellOwnDevices(
        conversationId: 'account-bob',
        isGroup: false,
        payload: const MessagePayload.receipt(receiptIds: ['v1'], receiptKind: MessagePayload.openedReceipt),
      );

      final copy = (await laptop.messaging.receive()).messages.single.payload.sync!;
      expect(copy.conversationId, 'account-bob');
      expect(copy.inner.receiptKind, MessagePayload.openedReceipt);
      expect(copy.inner.receiptIds, ['v1']);
      expect((await bob.messaging.receive()).messages, isEmpty, reason: 'the sender learned it was opened');
    });

    test('in a group too: the fan-out reaches the sender’s other device without the key', () async {
      final group = await alice.messaging.createGroup('Team', [bob.accountId]);
      await alice.messaging.sendPayloadToGroup(group.groupId, _once());

      final forBob = (await bob.messaging.receive()).messages.single.payload;
      expect(forBob.mediaKey, 'a2V5');
      final forLaptop = (await laptop.messaging.receive()).messages.single.payload;
      expect(forLaptop.viewOnce, isTrue);
      expect(forLaptop.mediaKey, isNull);
    });
  });

  group('sending', () {
    test('goes without a caption, and the sender keeps nothing to open it with', () async {
      final (services, messaging, _, _) = await outbox.buildServices();
      final controller = ConversationController(services)..accountId = 'account-alice';

      await controller.sendPhotos(
        'account-bob',
        await prepared([jpeg()]),
        caption: 'nicht mitschicken',
        viewOnce: true,
        olderBuildsText: _older,
      );

      final sent = messaging.sent.single;
      expect(sent.viewOnce, isTrue);
      expect(sent.mediaKey, isNotNull, reason: 'the recipient could not open it');
      expect(sent.body, _older);

      final message = services.store.conversationWith('account-bob')!.messages.single;
      expect(message.viewOnce, isTrue);
      expect(message.state, DeliveryState.sent);
      expect(message.attachment, isNull, reason: 'the sender kept the key');
      expect(message.body, isEmpty, reason: 'a caption stays after the picture has gone');
      expect(controller.queuedCount, 0);

      // And not in what was written down either.
      await controller.flush();
      final reopened = ConversationController(services);
      services.store.removeConversation('account-bob');
      await reopened.restore();
      final restored = services.store.conversationWith('account-bob')!.messages.single;
      expect(restored.viewOnce, isTrue);
      expect(restored.attachment, isNull);
    });

    test('waiting for the network, it stays one to be viewed once, across a restart', () async {
      final (services, messaging, server, _) = await outbox.buildServices();
      final controller = ConversationController(services)..accountId = 'account-alice';
      server.online = false;

      await controller.sendPhotos('account-bob', await prepared([jpeg()]), viewOnce: true, olderBuildsText: _older);
      await controller.flush();

      final reopened = ConversationController(services)..accountId = 'account-alice';
      await reopened.restore();
      server.online = true;
      await reopened.flushOutbox();

      expect(messaging.sent.single.viewOnce, isTrue);
      expect(messaging.sent.single.body, _older);
      expect(services.store.conversationWith('account-bob')!.messages.single.attachment, isNull);
    });

    test('never into Saved', () async {
      final (services, messaging, _, _) = await outbox.buildServices();
      final controller = ConversationController(services)..accountId = 'account-alice';
      controller.ensureSaved(username: 'alice');

      await controller.sendPhotos('account-alice', await prepared([jpeg()]), viewOnce: true);

      expect(messaging.sent, isEmpty);
      expect(services.store.conversationWith('account-alice')!.messages, isEmpty);
    });
  });

  group('receiving', () {
    test('arrives unopened, with its key, and nothing is fetched until it is opened', () async {
      final (_, store, messaging, _) = await _withOneArrived();

      final message = _single(store);
      expect(message.viewOnce, isTrue);
      expect(message.kind, MessageKind.photo);
      expect(message.canOpenOnce, isTrue);
      expect(message.body, isEmpty);
      expect(messaging.fetches, 0);
    });

    test('opens once: the key is gone, and written down gone, before the picture is handed over', () async {
      final (controller, store, messaging, services) = await _withOneArrived();
      final message = _single(store);

      final bytes = await controller.openViewOnce('account-bob', message.id);
      expect(bytes, messaging.picture);
      expect(_single(store).attachment, isNull);
      expect(_single(store).viewOnce, isTrue);

      // Already in the archive: nothing waited for the viewer to close.
      store.removeConversation('account-bob');
      await ConversationController(services).restore();
      expect(_single(store).attachment, isNull, reason: 'a restart would open it again');

      expect(await controller.openViewOnce('account-bob', message.id), isNull);
      expect(messaging.fetches, 1);
    });

    test('tells this account’s other devices, and nobody else', () async {
      final (controller, store, messaging, _) = await _withOneArrived();
      await controller.openViewOnce('account-bob', _single(store).id);
      await pumpEventQueue();

      final told = messaging.told.single;
      expect(told.conversationId, 'account-bob');
      expect(told.payload.receiptKind, MessagePayload.openedReceipt);
      expect(told.payload.receiptIds, ['v1']);
      expect(messaging.sent.where((p) => p.receiptKind == MessagePayload.openedReceipt), isEmpty,
          reason: 'the sender was told it was opened');
    });

    test('a fetch that fails leaves it unopened, to be tried again', () async {
      final (controller, store, messaging, _) = await _withOneArrived();
      messaging.failFetch = true;

      expect(await controller.openViewOnce('account-bob', _single(store).id), isNull);
      expect(_single(store).canOpenOnce, isTrue);
      expect(messaging.told, isEmpty);
    });

    test('two taps at once show it once', () async {
      final (controller, store, messaging, _) = await _withOneArrived();
      final id = _single(store).id;
      messaging.gate = Completer<void>();

      final first = controller.openViewOnce('account-bob', id);
      final second = controller.openViewOnce('account-bob', id);
      messaging.gate!.complete();
      final results = await Future.wait([first, second]);

      expect(results.whereType<Uint8List>(), hasLength(1));
    });

    test('opened on another of this account’s devices, it cannot be opened here', () async {
      final (controller, store, messaging, _) = await _withOneArrived();
      // An ordinary photo, named in the same receipt: it keeps its key.
      messaging.inbox.add(_arriving(
        const MessagePayload.media(
          mediaId: 'media-2',
          mediaKey: 'b3JkaW5hcnk=',
          mediaType: 'image/jpeg',
          byteSize: 99,
          clientId: 'p1',
        ),
        envelope: 30,
      ));
      await controller.drain();
      messaging.inbox.add(_fromMyOtherDevice(
        const MessagePayload.receipt(receiptIds: ['v1', 'p1'], receiptKind: MessagePayload.openedReceipt),
      ));
      await controller.drain();

      final messages = store.conversationWith('account-bob')!.messages;
      final once = messages.firstWhere((m) => m.clientId == 'v1');
      expect(once.attachment, isNull);
      expect(await controller.openViewOnce('account-bob', once.id), isNull);
      expect(messages.firstWhere((m) => m.clientId == 'p1').attachment, isNotNull);
    });

    test('one’s own is never opened, even with a key on it', () async {
      final store = storeWith([
        Message(
          id: 'c1',
          clientId: 'c1',
          body: '',
          sentAt: DateTime(2026),
          isMine: true,
          kind: MessageKind.photo,
          viewOnce: true,
          attachment: const Attachment(mediaId: 'm', mediaKey: 'a2V5', mediaType: 'image/jpeg', byteSize: 1),
        ),
      ]);
      final (services, messaging, _) = await _receiving(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      expect(await controller.openViewOnce('account-bob', 'c1'), isNull);
      expect(messaging.fetches, 0);
    });

    test('one this account sent from another device is filed without a key, even if one came', () async {
      final store = storeWith([]);
      final (services, messaging, _) = await _receiving(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      messaging.inbox.add(_fromMyOtherDevice(_once(clientId: 'v9')));
      await controller.drain();

      final message = _single(store);
      expect(message.isMine, isTrue);
      expect(message.viewOnce, isTrue);
      expect(message.attachment, isNull);

      // And the copy as it really arrives, with nothing to open, is a photo too.
      messaging.inbox.add(_fromMyOtherDevice(_once(clientId: 'v10').withoutViewOnceKey(), envelope: 9));
      await controller.drain();
      final stub = store.conversationWith('account-bob')!.messages.firstWhere((m) => m.clientId == 'v10');
      expect(stub.kind, MessageKind.photo);
      expect(stub.body, isEmpty);
    });

    test('in a group, one this account sent from another device is not openable here', () async {
      final store = storeWith([])..upsertGroup(const GroupInfo(groupId: 'group-1', role: 'member', memberCount: 3));
      final (services, messaging, _) = await _receiving(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      messaging.inbox
        ..add(_arriving(_once(clientId: 'g1'), from: 'account-alice', groupId: 'group-1', envelope: 11))
        ..add(_arriving(_once(clientId: 'g2'), groupId: 'group-1', envelope: 12));
      await controller.drain();

      final messages = store.conversationWith('group-1')!.messages;
      expect(messages.firstWhere((m) => m.clientId == 'g1').attachment, isNull);
      expect(messages.firstWhere((m) => m.clientId == 'g2').canOpenOnce, isTrue,
          reason: 'somebody else’s photo in the group should still open');
    });

    test('cannot be saved', () async {
      final (controller, store, _, _) = await _withOneArrived();
      controller.ensureSaved(username: 'alice');

      expect(await controller.saveToSaved(_single(store)), FailureKind.savedViewOnceRefused);
      expect(store.conversationWith('account-alice')!.messages, isEmpty);
    });

    test('a backup leaves its key out; this device keeps it until it is opened', () async {
      final (_, store, _, _) = await _withOneArrived();
      final conversations = store.conversations();

      final local = ArchiveCodec.decode(ArchiveCodec.encode(conversations));
      expect(local.single.messages.single.canOpenOnce, isTrue);

      final backup = ArchiveCodec.decode(ArchiveCodec.encode(conversations, forBackup: true));
      expect(backup.single.messages.single.viewOnce, isTrue);
      expect(backup.single.messages.single.attachment, isNull);
      expect(jsonEncode(ArchiveCodec.encode(conversations, forBackup: true)), isNot(contains('a2V5')));

      // And the backup itself goes that way.
      final recovery = RecoveryKey.generate();
      final restored = await BackupCodec.open(await BackupCodec.seal(conversations, recovery: recovery), recovery);
      expect(restored.conversations.single.messages.single.attachment, isNull);
    });
  });

  group('copies from this account’s other devices', () {
    test('are taken from this account only', () async {
      final store = storeWith([
        Message(id: 'mine-1', clientId: 'm1', body: 'meins', sentAt: DateTime(2026), isMine: true),
      ]);
      final (services, messaging, _) = await _receiving(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      messaging.inbox.add(_arriving(_once()));
      await controller.drain();

      // Bob, dressed up as a copy from Alice's laptop.
      MessagePayload copy(MessagePayload inner) => MessagePayload.sync(
            SyncEnvelope(conversationId: 'account-bob', isGroup: false, payload: inner.encode()),
          );
      messaging.inbox
        ..add(_arriving(copy(const MessagePayload.receipt(
          receiptIds: ['v1'],
          receiptKind: MessagePayload.openedReceipt,
        )), envelope: 20))
        ..add(_arriving(copy(const MessagePayload.text('in deinem Namen', clientId: 'x1')), envelope: 21))
        ..add(_arriving(copy(const MessagePayload.deletion('m1')), envelope: 22));
      await controller.drain();

      final messages = store.conversationWith('account-bob')!.messages;
      expect(messages.firstWhere((m) => m.clientId == 'v1').canOpenOnce, isTrue);
      expect(messages.where((m) => m.clientId == 'x1'), isEmpty, reason: 'filed as written by this account');
      expect(messages.firstWhere((m) => m.clientId == 'm1').kind, isNot(MessageKind.deleted));
    });
  });

  group('on screen', () {
    Message received({bool opened = false}) => Message(
          id: 'envelope-7',
          clientId: 'v1',
          body: '',
          sentAt: DateTime(2026, 10, 29, 9),
          isMine: false,
          kind: MessageKind.photo,
          viewOnce: true,
          attachment: opened
              ? null
              : const Attachment(mediaId: 'media-1', mediaKey: 'a2V5', mediaType: 'image/jpeg', byteSize: 1234),
        );

    Widget bubble(Message message, {VoidCallback? onOpen}) => MaterialApp(
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: Scaffold(body: MessageBubble(message: message, onOpenOnce: onOpen)),
        );

    testWidgets('unopened, it says to tap and draws no picture; a tap opens it', (tester) async {
      var opened = 0;
      await tester.pumpWidget(bubble(received(), onOpen: () => opened += 1));

      expect(find.text('Photo · view once'), findsOneWidget);
      expect(find.text('Tap to view. It is gone afterwards.'), findsOneWidget);
      expect(find.byType(Image), findsNothing, reason: 'a preview is a second viewing');
      await tester.tap(find.byKey(const Key('view-once-envelope-7')));
      expect(opened, 1);
    });

    testWidgets('opened, it says so and offers nothing', (tester) async {
      await tester.pumpWidget(bubble(received(opened: true), onOpen: () {}));
      expect(find.text('Opened'), findsOneWidget);
      expect(find.byKey(const Key('view-once-envelope-7')), findsNothing);
    });

    testWidgets('one’s own says it cannot be opened here either', (tester) async {
      final mine = Message(
        id: 'c1',
        clientId: 'c1',
        body: '',
        sentAt: DateTime(2026, 10, 29, 9),
        isMine: true,
        kind: MessageKind.photo,
        state: DeliveryState.delivered,
        viewOnce: true,
      );
      await tester.pumpWidget(bubble(mine, onOpen: () {}));
      expect(find.text('You cannot open it either.'), findsOneWidget);
      expect(find.byKey(const Key('view-once-c1')), findsNothing);
    });

    testWidgets('the preview’s switch takes the caption away and sends it to be viewed once', (tester) async {
      final photos = await tester.runAsync(() => prepared([jpeg()]));
      PhotoPreviewResult? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await PhotoPreviewSheet.open(context, photos: photos!, allowViewOnce: true),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Bildtext');
      await tester.tap(find.byKey(const Key('photo-view-once')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('No caption on a photo viewed once'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      final send = result! as PhotoPreviewSend;
      expect(send.viewOnce, isTrue);
      expect(send.caption, isEmpty);
    });

    testWidgets('the preview offers no switch where it is not allowed', (tester) async {
      final photos = await tester.runAsync(() => prepared([jpeg()]));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: PhotoPreviewSheet(photos: photos!),
      ));
      expect(find.byKey(const Key('photo-view-once')), findsNothing);
    });

    testWidgets('the viewer protects the screen while open, says what that is worth, and lets go', (tester) async {
      final platform = FakeShield(ScreenShieldCapability.blocking);
      final shield = ScreenShieldController(platform, InMemorySecureStore());
      final bytes = (await tester.runAsync(() async => jpeg()))!;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => ViewOnceViewer(bytes: bytes, shield: shield)),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(platform.applied.last, isTrue);
      expect(
        find.textContaining('Screenshots and screen recordings are blocked while this is open.'),
        findsOneWidget,
      );
      expect(find.textContaining('A camera pointed at the screen is not.'), findsOneWidget);

      Navigator.of(tester.element(find.byType(ViewOnceViewer))).pop();
      await tester.pumpAndSettle();
      expect(platform.applied.last, isFalse, reason: 'the account never asked for it');
    });

    testWidgets('closing the viewer leaves protection on where the account asked for it', (tester) async {
      final platform = FakeShield(ScreenShieldCapability.blocking);
      final shield = ScreenShieldController(platform, InMemorySecureStore());
      await tester.runAsync(() async {
        await shield.load('account-alice');
        await shield.setEnabled(true);
        await shield.hold();
        await shield.release();
      });
      expect(platform.applied.last, isTrue);
    });

    testWidgets('held, it stays on whatever the account does, and the next account starts clean',
        (tester) async {
      final platform = FakeShield(ScreenShieldCapability.blocking);
      final shield = ScreenShieldController(platform, InMemorySecureStore());
      await tester.runAsync(() async {
        await shield.load('account-alice');
        await shield.hold();
        await shield.setEnabled(true);
        await shield.setEnabled(false);
        expect(platform.applied.last, isTrue, reason: 'switched off under a photo being viewed');
        await shield.load('account-alice');
        expect(platform.applied.last, isTrue, reason: 'a reload switched it off under a photo');

        // Signed out with the viewer still up: the next account's first
        // viewing must end in the state that account chose.
        await shield.signedOut();
        await shield.load('account-carol');
        await shield.hold();
        await shield.release();
        expect(platform.applied.last, isFalse);
      });
    });

    testWidgets('on an iPhone, a recording while it is held covers the screen', (tester) async {
      final platform = FakeShield(ScreenShieldCapability.detecting);
      final shield = ScreenShieldController(platform, InMemorySecureStore());
      await tester.runAsync(() async {
        await shield.load('account-alice');
        await shield.hold();
      });
      platform.reportCapture(true);
      expect(shield.shouldCover, isTrue);
    });

    testWidgets('on a phone that cannot block a screenshot, it says so', (tester) async {
      final shield = ScreenShieldController(FakeShield(ScreenShieldCapability.detecting), InMemorySecureStore());
      await tester.runAsync(() => shield.load('account-alice'));
      final bytes = (await tester.runAsync(() async => jpeg()))!;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: ViewOnceViewer(bytes: bytes, shield: shield),
      ));
      expect(find.textContaining('This phone cannot block a screenshot.'), findsOneWidget);
    });
  });

  group('in the chat', () {
    Future<AppState> chatWithAPhoto(WidgetTester tester) async {
      final picture = (await tester.runAsync(() async => jpeg()))!;
      final sealed = (await tester.runAsync(() => AttachmentCipher.seal(picture, declaredType: 'image/jpeg')))!;
      final api = PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient((request) async {
          if (request.url.path == '/v1/media/media-1') return http.Response.bytes(sealed.bytes, 200);
          return http.Response(
            jsonEncode({'contacts': <Object>[], 'envelopes': <Object>[], 'more': false, 'remaining': 100}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final services = (await tester.runAsync(() async {
        final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
        final messaging = MessagingService(api: api, crypto: crypto);
        return PrivioServices(
          api: api,
          crypto: crypto,
          messaging: messaging,
          channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
          recorder: FakeVoiceRecorder(),
          player: FakeVoicePlayer(),
          backup: BackupService(api: api, store: InMemorySecureStore(), messages: InMemoryMessageStore()),
          store: InMemoryMessageStore(),
          secureStore: InMemorySecureStore(),
        );
      }))!;
      final state = AppState(services: services, store: InMemorySecureStore());
      await tester.runAsync(state.initialise);
      state.conversations.accountId = 'acc-alice';
      services.store
        ..upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'))
        ..append(
          'acc-bob',
          Message(id: 'envelope-6', clientId: 't1', body: 'schau mal', sentAt: DateTime(2026, 10, 29, 8), isMine: false),
        )
        ..append(
          'acc-bob',
          Message(
            id: 'envelope-7',
            clientId: 'v1',
            body: '',
            sentAt: DateTime(2026, 10, 29, 9),
            isMine: false,
            kind: MessageKind.photo,
            viewOnce: true,
            attachment: Attachment(
              mediaId: 'media-1',
              mediaKey: base64Encode(sealed.key),
              mediaToken: 'token-1',
              mediaType: 'image/jpeg',
              byteSize: sealed.plainLength,
            ),
          ),
        );
      addTearDown(state.conversations.stop);
      return state;
    }

    testWidgets('a tap opens it, and afterwards the chat says it was opened', (tester) async {
      final state = await chatWithAPhoto(tester);
      await tester.pumpWidget(wrap(const ChatScreen(accountId: 'acc-bob', title: 'bob'), state));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('view-once-envelope-7')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.byType(ViewOnceViewer), findsOneWidget);

      Navigator.of(tester.element(find.byType(ViewOnceViewer))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Opened'), findsOneWidget);
      expect(find.byKey(const Key('view-once-envelope-7')), findsNothing);
    });

    Future<(AppState, OnceMessaging)> chatToSendFrom(WidgetTester tester) async {
      final picture = (await tester.runAsync(() async => jpeg()))!;
      final api = PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient((request) async {
          if (request.method == 'POST' && request.url.path == '/v1/media') {
            return http.Response(jsonEncode({'id': 'media-9', 'token': 'token-9'}), 201,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(
            jsonEncode({'contacts': <Object>[], 'envelopes': <Object>[], 'more': false, 'remaining': 100}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..useToken('token');
      final (services, messaging) = (await tester.runAsync(() async {
        final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
        final messaging = OnceMessaging(api: api, crypto: crypto);
        return (
          PrivioServices(
            api: api,
            crypto: crypto,
            messaging: messaging,
            channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
            recorder: FakeVoiceRecorder(),
            player: FakeVoicePlayer(),
            photos: _OnePhoto(picture),
            backup: BackupService(api: api, store: InMemorySecureStore(), messages: InMemoryMessageStore()),
            store: InMemoryMessageStore(),
            secureStore: InMemorySecureStore(),
          ),
          messaging,
        );
      }))!;
      final state = AppState(services: services, store: InMemorySecureStore());
      await tester.runAsync(state.initialise);
      state.conversations
        ..accountId = 'acc-alice'
        ..ensureSaved(username: 'alice');
      services.store.upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'));
      addTearDown(state.conversations.stop);
      return (state, messaging);
    }

    Future<void> choosePhotos(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photos'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();
    }

    testWidgets('chosen in the preview, it goes to be viewed once, with the text for older builds',
        (tester) async {
      final (state, messaging) = await chatToSendFrom(tester);
      await tester.pumpWidget(wrap(const ChatScreen(accountId: 'acc-bob', title: 'bob'), state));
      await tester.pump(const Duration(seconds: 1));
      await choosePhotos(tester);

      await tester.tap(find.byKey(const Key('photo-view-once')));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();

      final sent = messaging.sent.single;
      expect(sent.viewOnce, isTrue);
      expect(sent.body, '📷 A photo that can be viewed once. Update Privio to open it.');
      expect(find.text('You cannot open it either.'), findsOneWidget);
    });

    testWidgets('Saved does not offer it', (tester) async {
      final (state, _) = await chatToSendFrom(tester);
      await tester.pumpWidget(wrap(const ChatScreen(accountId: 'acc-alice', title: 'alice'), state));
      await tester.pump(const Duration(seconds: 1));
      await choosePhotos(tester);

      expect(find.byType(PhotoPreviewSheet), findsOneWidget);
      expect(find.byKey(const Key('photo-view-once')), findsNothing);
    });

    testWidgets('holding it down offers no Save', (tester) async {
      final state = await chatWithAPhoto(tester);
      await tester.pumpWidget(wrap(const ChatScreen(accountId: 'acc-bob', title: 'bob'), state));
      await tester.pump(const Duration(seconds: 1));

      // An ordinary message offers it, so the label below is the real one.
      await tester.longPress(find.text('schau mal'));
      await tester.pumpAndSettle();
      expect(find.text('Save to Saved'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Photo · view once'));
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget, reason: 'the sheet did not open');
      expect(find.text('Save to Saved'), findsNothing);
    });
  });
}

/// A photo library with one picture in it.
class _OnePhoto implements PhotoSource {
  const _OnePhoto(this.bytes);

  final Uint8List bytes;

  @override
  Future<PhotoPick> capture() async => const PhotoCancelled();

  @override
  Future<PhotoPick> pickImages() async => PhotoPicked([PickedPhoto(bytes)]);
}
