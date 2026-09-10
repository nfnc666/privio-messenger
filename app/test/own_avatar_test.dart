import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/media/avatar.dart';

import 'deletion_test.dart' show buildServices;

/// Avatars are held in memory and never written to disk, which is deliberate:
/// a face on disk in the clear is not worth the convenience. The cost is that
/// after a relaunch the picture has to be fetched again — and for everyone
/// else's pictures it was, while this account's own was not. The server still
/// held it, the key was still in the keystore, and the account screen showed
/// initials anyway, which reads as "the picture was lost".
void main() {
  test('the own profile picture comes back after a restart', () async {
    Uint8List? sealed;
    final client = MockClient((request) async {
      final path = request.url.path;
      Map<String, dynamic>? json;
      if (path == '/v1/contacts') json = {'contacts': <dynamic>[]};
      if (path == '/v1/accounts/me') json = {'avatarMediaId': 'media-1'};
      if (json != null) {
        return http.Response(jsonEncode(json), 200, headers: {'content-type': 'application/json'});
      }
      if (path == '/v1/media/media-1') return http.Response.bytes(sealed!, 200);
      return http.Response(
        jsonEncode({'error': 'not_found', 'message': path}),
        404,
        headers: {'content-type': 'application/json'},
      );
    });

    final store = InMemoryMessageStore();
    final (services, _) = await buildServices(store, client: client);

    // What the server holds after this account has set a picture: the prepared
    // image, sealed under this account's own profile key — which survives a
    // restart because it lives in the keystore.
    final picture = AvatarImage.prepare(img.encodeJpg(img.Image(width: 400, height: 400)))!;
    sealed = Uint8List.fromList(
      await AttachmentCipher.sealWithKey(
        picture,
        key: await services.crypto.profileKey(),
        declaredType: 'image/jpeg',
      ),
    );

    // A fresh controller is what a relaunch produces: nothing in memory.
    final controller = ConversationController(services);
    expect(controller.ownAvatar, isNull, reason: 'a new run starts with no picture in memory');

    await controller.refreshContacts();
    // The restore is deliberately not awaited by `refreshContacts` — the
    // contact list must not wait on a picture — so let it finish.
    for (var turn = 0; turn < 50 && controller.ownAvatar == null; turn++) {
      await Future<void>.delayed(Duration.zero);
    }

    // Not a byte comparison against `picture`: sealing scrubs metadata first,
    // so what comes back is the scrubbed image rather than the input. What
    // matters is that it arrived and opened — wrong key or wrong blob gives
    // bytes that do not decode at all.
    expect(
      controller.ownAvatar,
      isNotNull,
      reason: 'the server still holds it and the key is still here; a restart must not lose it',
    );
    expect(img.decodeImage(controller.ownAvatar!)?.width, AvatarImage.size);
  });

  test('an account with no picture is not asked about twice', () async {
    var meReads = 0;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/v1/accounts/me') meReads++;
      return http.Response(
        jsonEncode(path == '/v1/contacts' ? {'contacts': <dynamic>[]} : {'avatarMediaId': null}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final (services, _) = await buildServices(InMemoryMessageStore(), client: client);
    final controller = ConversationController(services);

    // Opening the contacts screen refreshes; doing it repeatedly must not spend
    // a rate-limited budget on a question already answered.
    for (var i = 0; i < 3; i++) {
      await controller.refreshContacts();
      for (var turn = 0; turn < 10; turn++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    expect(controller.ownAvatar, isNull);
    expect(meReads, 1, reason: '"there is no picture" is an answer, not a failure to retry');
  });
}
