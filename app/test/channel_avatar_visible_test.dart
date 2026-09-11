import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privio/core/channel_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/channel.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';

import 'support/fake_voice.dart';
import 'channel_service_test.dart' show FakeChannelServer;

/// Setting a channel picture has to become *visible*.
///
/// The reported failure was not an error — it was silence. A picture was
/// chosen, the upload succeeded, and the header went on drawing the
/// placeholder, which from the outside is identical to nothing having
/// happened at all. These tests are about the seam where that happened.
Future<(ChannelController, FakeChannelServer, PrivioServices)> build() async {
  final server = FakeChannelServer();
  final api = PrivioApiClient(
    baseUrl: Uri.parse('http://localhost:8080'),
    client: server.client(),
  )..useToken('token');
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  final store = InMemoryMessageStore();
  final secure = InMemorySecureStore();
  final services = PrivioServices(
    api: api,
    crypto: crypto,
    messaging: messaging,
    channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
    recorder: FakeVoiceRecorder(),
    player: FakeVoicePlayer(),
    store: store,
    secureStore: secure,
    backup: BackupService(api: api, store: secure, messages: store),
  );
  return (ChannelController(services), server, services);
}

Uint8List picture() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(30, 160, 120));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a channel the controller has never listed still gets its picture',
      () async {
    final (controller, _, services) = await build();

    // Reached before `refresh()` ran, or opened straight from a link: the
    // controller's lists are empty. This is the case that broke — `_replace`
    // only rewrote entries that were already there, so the update was dropped
    // and `channelById` went on answering null while the server had the
    // picture perfectly well.
    final channel = await services.channels.create(
      visibility: ChannelVisibility.public,
      handle: 'ungelistet',
      title: 'Ungelistet',
    );
    expect(controller.channelById(channel.id), isNull, reason: 'nothing listed it');

    expect(await controller.setAvatar(channel, picture()), isTrue);

    final seen = controller.channelById(channel.id);
    expect(seen, isNotNull, reason: 'the change has to reach the lists');
    expect(seen!.avatarMediaId, isNotNull);
    expect(seen.hasAvatar, isTrue);
    expect(controller.avatarFor(seen), isNotNull, reason: 'and the bytes with it');
  });

  test('and the screen is handed the updated channel to adopt', () async {
    final (controller, _, services) = await build();
    final channel = await services.channels.create(
      visibility: ChannelVisibility.public,
      handle: 'uebernahme',
      title: 'Uebernahme',
    );

    expect(controller.lastAvatarChange, isNull);
    await controller.setAvatar(channel, picture());

    // The feed screen keeps its own copy of the channel. Without being handed
    // the new one it redraws the old one, and a successful upload looks exactly
    // like a failed one.
    expect(controller.lastAvatarChange, isNotNull);
    expect(controller.lastAvatarChange!.id, channel.id);
    expect(controller.lastAvatarChange!.hasAvatar, isTrue);
  });

  test('removing one is handed back the same way', () async {
    final (controller, _, services) = await build();
    final channel = await services.channels.create(
      visibility: ChannelVisibility.public,
      handle: 'entfernung',
      title: 'Entfernung',
    );
    await controller.setAvatar(channel, picture());
    final withPicture = controller.lastAvatarChange!;

    expect(await controller.clearAvatar(withPicture), isTrue);
    expect(controller.lastAvatarChange!.hasAvatar, isFalse);
    expect(controller.channelById(channel.id)!.hasAvatar, isFalse);
  });
}
