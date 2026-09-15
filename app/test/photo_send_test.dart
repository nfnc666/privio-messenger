import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/media/photo.dart';
import 'package:privio/models/models.dart';

import 'voice_outbox_test.dart' show buildServices;

/// A photograph, as bytes. Small and real: the pipeline decodes it, so a
/// handful of made-up bytes would not do.
Uint8List jpeg({int width = 400, int height = 300, int shade = 120}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(shade, shade, shade));
  return Uint8List.fromList(img.encodeJpg(image));
}

Future<List<PreparedPhoto>> prepared(List<Uint8List> raw) => PhotoImage.prepareAll(raw);

void main() {
  test('a photo goes out and lands as a picture, not a file row', () async {
    final (services, messaging, server, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';

    await controller.sendPhotos('account-bob', await prepared([jpeg()]));

    final message = services.store.conversationWith('account-bob')!.messages.single;
    expect(message.kind, MessageKind.photo);
    expect(message.state, DeliveryState.sent);
    expect(message.attachment!.mediaType, 'image/jpeg');
    expect(message.attachment!.mediaId, server.uploads.single);
    expect(messaging.sent.single.mediaType, 'image/jpeg');
    expect(controller.queuedCount, 0);
  });

  test('several photos keep the order they were chosen in', () async {
    final (services, messaging, _, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';

    // Three different shades, so "which one is this" is answerable from the
    // bytes rather than from the order they happen to be in.
    await controller.sendPhotos(
      'account-bob',
      await prepared([jpeg(shade: 10), jpeg(shade: 120), jpeg(shade: 240)]),
    );

    final messages = services.store.conversationWith('account-bob')!.messages;
    expect(messages, hasLength(3));
    expect(
      messages.map((m) => m.attachment!.fileName),
      ['photo-1.jpg', 'photo-2.jpg', 'photo-3.jpg'],
    );
    expect(messaging.sent.map((p) => p.fileName), ['photo-1.jpg', 'photo-2.jpg', 'photo-3.jpg']);
  });

  test('the caption rides on the first picture and is not repeated', () async {
    final (services, messaging, _, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';

    await controller.sendPhotos(
      'account-bob',
      await prepared([jpeg(), jpeg(shade: 200)]),
      caption: 'from the roof',
    );

    final messages = services.store.conversationWith('account-bob')!.messages;
    expect(messages.first.body, 'from the roof');
    expect(messages.last.body, isEmpty);
    expect(messaging.sent.map((p) => p.body), ['from the roof', '']);
  });

  test('the file name is the one the app invented, never the one off the phone',
      () async {
    final (services, _, _, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';

    await controller.sendPhotos('account-bob', await prepared([jpeg()]));

    final name = services.store.conversationWith('account-bob')!.messages.single.attachment!
        .fileName;
    expect(name, 'photo-1.jpg');
    expect(name, isNot(contains('/')), reason: 'a path would say where on the phone it was');
  });

  test('with no network the photo waits instead of disappearing', () async {
    final (services, messaging, server, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';
    server.online = false;

    await controller.sendPhotos('account-bob', await prepared([jpeg()]), caption: 'hi');

    expect(controller.queuedCount, 1);
    final message = services.store.conversationWith('account-bob')!.messages.single;
    expect(message.state, DeliveryState.queued);
    expect(message.kind, MessageKind.photo);
    expect(message.body, 'hi', reason: 'the bubble is complete while it waits');
    expect(messaging.sent, isEmpty);
  });

  test('a retry sends once more, not a second photo', () async {
    final (services, messaging, server, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';

    // The upload gets through; the send does not. This is the case that used to
    // produce two pictures in the chat.
    messaging.failSends = true;
    await controller.sendPhotos('account-bob', await prepared([jpeg()]));
    expect(server.uploads, hasLength(1));
    expect(controller.queuedCount, 1);
    final clientId =
        services.store.conversationWith('account-bob')!.messages.single.clientId!;

    messaging.failSends = false;
    await controller.retry(clientId);

    expect(services.store.conversationWith('account-bob')!.messages, hasLength(1));
    expect(server.uploads, hasLength(1), reason: 'the bytes were already up there');
    expect(messaging.sentClientIds, [clientId]);
    expect(controller.queuedCount, 0);
  });

  test('photos chosen in one account never land in the next one', () async {
    final (services, messaging, _, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';

    // The picker was open, and the person switched accounts behind it.
    controller.accountId = 'account-carol';
    await controller.sendPhotos(
      'account-bob',
      await prepared([jpeg()]),
      account: 'account-alice',
    );

    expect(services.store.conversationWith('account-bob')?.messages ?? const [], isEmpty);
    expect(messaging.sent, isEmpty);
  });

  test('a disappearing chat starts the photo clock when the server takes it', () async {
    final (services, _, _, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';
    await controller.setDisappearAfter('account-bob', const Duration(hours: 1));

    await controller.sendPhotos('account-bob', await prepared([jpeg()]));

    final message = services.store
        .conversationWith('account-bob')!
        .messages
        .where((m) => m.kind == MessageKind.photo)
        .single;
    expect(message.expiresAt, isNotNull);
    expect(
      message.expiresAt!.difference(DateTime.now()).inMinutes,
      greaterThan(55),
      reason: 'the timer applies to pictures too',
    );
  });

  test('a photo queued in a disappearing chat has no clock until it is sent', () async {
    final (services, _, server, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';
    await controller.setDisappearAfter('account-bob', const Duration(minutes: 1));
    server.online = false;

    await controller.sendPhotos('account-bob', await prepared([jpeg()]));

    final message = services.store
        .conversationWith('account-bob')!
        .messages
        .where((m) => m.kind == MessageKind.photo)
        .single;
    expect(
      message.expiresAt,
      isNull,
      reason: 'a picture waiting for a network must not expire before it goes anywhere',
    );
  });

  test('nothing is queued for an empty selection', () async {
    final (services, messaging, _, _) = await buildServices();
    final controller = ConversationController(services)..accountId = 'account-alice';

    await controller.sendPhotos('account-bob', const []);

    expect(controller.queuedCount, 0);
    expect(messaging.sent, isEmpty);
  });
}
