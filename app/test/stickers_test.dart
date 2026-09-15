import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/failure.dart';
import 'package:privio/core/sticker_controller.dart';
import 'package:privio/media/sticker_image.dart';
import 'package:privio/models/channel.dart';
import 'package:privio/services/channel_service.dart';

/// A sticker server that answers from a little state of its own.
///
/// Enough of one to be worth having rather than stubbing each call: the rules
/// that matter here — a pack is private until it is shared, a fresh code
/// replaces the old one, a pack belongs to an account — are rules about state
/// across several requests, and a per-call stub cannot break them.
class _Server {
  _Server();

  final List<http.Request> seen = <http.Request>[];

  /// packId -> the pack as the server holds it.
  final Map<String, Map<String, dynamic>> packs = {};

  /// Codes that currently open a pack. Revoking removes the entry.
  final Map<String, String> codes = {};

  /// Which packs each account has added.
  final Map<String, Set<String>> installs = {};

  /// What `/v1/sticker-uses` answers.
  List<Map<String, dynamic>> uses = [];

  /// Refusals to serve on the next write, as `code`.
  final List<String> refusals = [];

  /// Held open so a test can decide when a request finishes.
  Completer<void>? gate;

  int _nextId = 0;
  String _id(String prefix) => '$prefix-${_nextId++}';

  /// A client signed in as [account].
  ///
  /// The account is carried so the fake can answer the way the real server
  /// does: `GET /v1/sticker-packs` returns *this* account's packs, not every
  /// pack in the table. Without it the fake would let a test pass that the
  /// server would fail — which is the failure mode of a fake that is too
  /// agreeable to be worth having.
  PrivioApiClient client({String account = 'account-a'}) => PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient((request) async {
          seen.add(request);
          final pending = gate;
          if (pending != null) await pending.future;

          final path = request.url.path;
          final method = request.method;

          if (refusals.isNotEmpty && method != 'GET') {
            final code = refusals.removeAt(0);
            return _json({'error': code, 'message': 'refused'}, status: 400);
          }

          if (method == 'GET' && path == '/v1/sticker-packs') {
            return _json({
              'packs': [
                for (final pack in packs.values)
                  if (pack['owner'] == account)
                    {...pack, 'installed': false}
                  else if ((installs[account] ?? const <String>{})
                      .contains(pack['id'] as String))
                    {...pack, 'shareCode': null, 'installed': true},
              ],
            });
          }
          if (method == 'POST' && path == '/v1/sticker-packs') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final id = _id('pack');
            packs[id] = {
              'id': id,
              'owner': account,
              'kind': body['kind'],
              'title': body['title'],
              'shareCode': null,
              'shared': false,
              'installed': false,
              'updatedAt': DateTime.utc(2026).toIso8601String(),
              'items': <Map<String, dynamic>>[],
            };
            return _json(packs[id]!, status: 201);
          }
          if (method == 'GET' && path.startsWith('/v1/sticker-packs/by-code/')) {
            final code = path.split('/').last;
            final id = codes[code];
            if (id == null) return _json({'error': 'pack_not_found'}, status: 404);
            // What a viewer sees: no share code of somebody else's.
            return _json({...packs[id]!, 'shareCode': null, 'installed': false});
          }
          if (method == 'POST' && path.endsWith('/share')) {
            final id = _packIdIn(path);
            final code = _id('code');
            // A fresh code every time, and the old one stops opening it.
            codes.removeWhere((_, value) => value == id);
            codes[code] = id;
            packs[id] = {...packs[id]!, 'shareCode': code, 'shared': true};
            return _json(packs[id]!);
          }
          if (method == 'DELETE' && path.endsWith('/share')) {
            final id = _packIdIn(path);
            codes.removeWhere((_, value) => value == id);
            packs[id] = {...packs[id]!, 'shareCode': null, 'shared': false};
            return _json({'shared': false});
          }
          if (method == 'POST' && path.endsWith('/items')) {
            final id = _packIdIn(path);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final items = [...(packs[id]!['items'] as List<dynamic>)];
            final item = {
              'id': _id('item'),
              'mediaId': body['mediaId'],
              'emoji': body['emoji'],
              'position': items.length,
            };
            items.add(item);
            packs[id] = {...packs[id]!, 'items': items};
            return _json(item, status: 201);
          }
          if (method == 'PUT' && path.endsWith('/order')) {
            final id = _packIdIn(path);
            final wanted = (jsonDecode(request.body) as Map<String, dynamic>)['itemIds']
                as List<dynamic>;
            final byId = {
              for (final item in packs[id]!['items'] as List<dynamic>)
                (item as Map<String, dynamic>)['id'] as String: item,
            };
            packs[id] = {
              ...packs[id]!,
              'items': [for (final each in wanted) byId[each]!],
            };
            return _json({'ordered': wanted.length});
          }
          if (method == 'POST' && path.endsWith('/install')) {
            final id = _packIdIn(path);
            (installs[account] ??= <String>{}).add(id);
            return _json({...packs[id]!, 'shareCode': null, 'installed': true});
          }
          if (method == 'DELETE' && path.endsWith('/install')) {
            final id = _packIdIn(path);
            installs[account]?.remove(id);
            return _json({'installed': false});
          }
          if (method == 'DELETE' && RegExp(r'^/v1/sticker-packs/[^/]+$').hasMatch(path)) {
            packs.remove(_packIdIn('$path/'));
            return _json({'deleted': true});
          }
          if (method == 'POST' && path == '/v1/media') {
            return _json({'id': _id('media')}, status: 201);
          }
          if (method == 'GET' && path.startsWith('/v1/media/')) {
            return http.Response.bytes([1, 2, 3], 200);
          }
          if (method == 'GET' && path == '/v1/sticker-uses') {
            return _json({'uses': uses});
          }
          if (method == 'POST' && path == '/v1/sticker-uses') {
            return _json({'recorded': 1});
          }
          return _json({'error': 'not_found'}, status: 404);
        }),
      )..useToken('token');

  static String _packIdIn(String path) => path.split('/')[3];

  static http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}

/// The test picture: a real 64×64 RGBA PNG. See [_makePng].
Uint8List _png() => Uint8List.fromList(_pngBytes);

late final List<int> _pngBytes;

void main() {
  setUpAll(() {
    // Built once: encoding is the slow part and every test wants the same file.
    _pngBytes = _makePng();
  });

  group('a pack is created, filled and reordered', () {
    test('creating one puts it in "my packs" and not in "added"', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');

      final pack = await controller.createPack(
        title: 'Cats',
        kind: StickerPackKind.sticker,
      );

      expect(pack, isNotNull);
      expect(controller.myPacks.map((each) => each.title), ['Cats']);
      expect(controller.installedPacks, isEmpty);
      expect(pack!.isMine, isTrue);
    });

    test('a picture is uploaded and added with the emoji it stands for', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');
      final pack = await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);

      final item = await controller.addItem(pack!.id, bytes: _png(), emoji: '😺');

      expect(item, isNotNull);
      expect(item!.emoji, '😺');
      expect(controller.packById(pack.id)!.items, hasLength(1));

      // Uploaded as a sticker, which is the kind whose bytes the server checks.
      final upload = server.seen.firstWhere((each) => each.url.path == '/v1/media');
      expect(upload.url.queryParameters['kind'], 'sticker');
    });

    test('an oversized picture is refused here, before it is uploaded', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');
      final pack = await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);
      final before = server.seen.length;

      final huge = Uint8List(StickerLimits.maxBytes + 1);
      final item = await controller.addItem(pack!.id, bytes: huge, emoji: '😺');

      expect(item, isNull);
      expect(controller.failure?.kind, FailureKind.stickerTooLarge);
      expect(server.seen.length, before, reason: 'nothing should have been sent');
    });

    test('reordering sends the whole order, and puts it back if refused', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');
      final pack = await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);
      final first = await controller.addItem(pack!.id, bytes: _png(), emoji: '1');
      final second = await controller.addItem(pack.id, bytes: _png(), emoji: '2');

      expect(await controller.reorder(pack.id, [second!.id, first!.id]), isTrue);
      expect(controller.packById(pack.id)!.items.map((each) => each.emoji), ['2', '1']);

      // Refused: the list goes back rather than staying in an order the server
      // does not have.
      server.refusals.add('pack_not_found');
      expect(await controller.reorder(pack.id, [first.id, second.id]), isFalse);
      expect(controller.packById(pack.id)!.items.map((each) => each.emoji), ['2', '1']);
    });
  });

  group('a pack is private until it is shared', () {
    test('a new pack has no code, and sharing produces one', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');
      final pack = await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);

      expect(pack!.shared, isFalse);
      expect(pack.shareCode, isNull);

      final code = await controller.share(pack.id);
      expect(code, isNotNull);
      expect(controller.packById(pack.id)!.shared, isTrue);
    });

    test('sharing again replaces the link, so a regretted one stops', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');
      final pack = await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);

      final first = await controller.share(pack!.id);
      final second = await controller.share(pack.id);

      expect(second, isNot(first));
      expect(await controller.previewByCode(first!), isNull,
          reason: 'the replaced link must stop opening the pack');
      expect(await controller.previewByCode(second!), isNotNull);
    });

    test('withdrawing the link stops it opening anything', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');
      final pack = await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);
      final code = await controller.share(pack!.id);

      expect(await controller.unshare(pack.id), isTrue);
      expect(controller.packById(pack.id)!.shared, isFalse);
      expect(await controller.previewByCode(code!), isNull);
    });

    test('a preview is not an install', () async {
      final server = _Server();
      final owner = StickerController(server.client());
      await owner.load('account-a');
      final pack = await owner.createPack(title: 'Cats', kind: StickerPackKind.sticker);
      final code = await owner.share(pack!.id);

      final viewer = StickerController(server.client(account: 'account-b'));
      await viewer.load('account-b');
      final seen = await viewer.previewByCode(code!);

      expect(seen, isNotNull);
      expect(viewer.packs, isEmpty, reason: 'looking is not adding');
      // And the viewer is never handed the code itself.
      expect(seen!.shareCode, isNull);

      expect(await viewer.install(seen.id, code: code), isNotNull);
      expect(viewer.installedPacks.map((each) => each.id), [pack.id]);
    });
  });

  group('packs belong to an account', () {
    test('a switch empties everything, including the picture cache', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');
      final pack = await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);
      final item = await controller.addItem(pack!.id, bytes: _png(), emoji: '😺');
      await controller.image(item!.mediaId);
      expect(controller.imageOf(item.mediaId), isNotNull);

      server.packs.clear();
      await controller.load('account-b');

      expect(controller.packs, isEmpty);
      expect(controller.imageOf(item.mediaId), isNull,
          reason: 'one account s picture must not be drawn for the next');
    });

    test('an answer that arrives after a switch is dropped, not applied', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');

      // A read for account A, held open.
      server.gate = Completer<void>();
      final inFlight = controller.load('account-a');

      // Meanwhile the person switches. Nothing is awaited, so the controller is
      // already on B when A's answer lands.
      controller.signedOut();
      server.packs['ghost'] = {
        'id': 'ghost',
        // Owned by the account whose read is in flight, so the fake really
        // does return it: without this the listing filtered it out and the
        // test passed with the guard removed, which is no test at all.
        'owner': 'account-a',
        'kind': 'sticker',
        'title': 'A s pack',
        'shareCode': null,
        'shared': false,
        'installed': false,
        'updatedAt': DateTime.utc(2026).toIso8601String(),
        'items': <Map<String, dynamic>>[],
      };
      server.gate!.complete();
      await inFlight;

      expect(controller.packs, isEmpty,
          reason: 'a late answer must not write one account s packs into another s');
    });

    test('signing out clears the failure and the busy flag too', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');
      server.refusals.add('pack_full');
      await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);
      expect(controller.failure, isNotNull);

      controller.signedOut();
      expect(controller.failure, isNull);
      expect(controller.busy, isFalse);
    });
  });

  group('the server s refusals become this app s words', () {
    test('each code becomes its own case rather than English from the wire', () async {
      final cases = {
        'not_an_image': FailureKind.stickerNotAnImage,
        'unsupported_format': FailureKind.stickerAnimated,
        'too_large': FailureKind.stickerTooLarge,
        'dimensions_too_large': FailureKind.stickerTooWide,
        'dimensions_too_small': FailureKind.stickerTooSmall,
        'pack_full': FailureKind.stickerPackFull,
        'too_many_packs': FailureKind.stickerTooManyPacks,
      };
      for (final entry in cases.entries) {
        final server = _Server();
        final controller = StickerController(server.client());
        await controller.load('account-a');
        server.refusals.add(entry.key);

        await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);
        expect(controller.failure?.kind, entry.value, reason: entry.key);
      }
    });

    test('a code this app does not know still says what the server said', () async {
      final server = _Server();
      final controller = StickerController(server.client());
      await controller.load('account-a');
      server.refusals.add('some_new_rule');

      await controller.createPack(title: 'Cats', kind: StickerPackKind.sticker);
      expect(controller.failure?.kind, FailureKind.serverSaid);
      expect(controller.failure?.detail, 'refused');
    });
  });

  group('a pack link', () {
    test('is built and read back, and is not confused with a channel', () {
      final link = ChannelService.linkForStickerPack('abc123');
      final target = ChannelService.parseLink(link);

      expect(target, isA<StickerPackLink>());
      expect((target! as StickerPackLink).code, 'abc123');
    });

    test('a channel link is still a channel link', () {
      expect(
        ChannelService.parseLink('https://privio.channel/+code'),
        isA<ChannelLinkByCode>(),
      );
      expect(
        ChannelService.parseLink('https://privio.channel/c/code'),
        isA<ChannelLinkByCode>(),
      );
      expect(
        ChannelService.parseLink('https://privio.channel/somechannel'),
        isA<ChannelLinkByHandle>(),
      );
    });

    test('the app s own scheme and the /open path carry it too', () {
      for (final link in [
        'privio://open/s/abc123',
        'https://privio.channel/open/s/abc123',
      ]) {
        final target = ChannelService.parseLink(link);
        expect(target, isA<StickerPackLink>(), reason: link);
        expect((target! as StickerPackLink).code, 'abc123', reason: link);
      }
    });
  });

  group('preparing a picture', () {
    test('keeps transparency, which means PNG and not JPEG', () async {
      final prepared = await StickerImage.prepare(_png());

      expect(prepared, isNotNull);
      // The PNG signature. A JPEG would start FF D8, and a sticker that lost
      // its alpha channel would be a rectangle with a box around it.
      expect(prepared!.take(4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('comes out within the limits the server enforces', () async {
      final prepared = await StickerImage.prepare(_png());
      expect(prepared!.length, lessThanOrEqualTo(StickerLimits.maxBytes));
    });

    test('is null for something that is not a picture at all', () async {
      final prepared = await StickerImage.prepare(
        Uint8List.fromList('not a picture, whatever the name says'.codeUnits),
      );
      expect(prepared, isNull);
    });
  });
}

/// A real 64×64 RGBA PNG, encoded by the library the app itself uses.
///
/// Built rather than checked in, so what the test depends on is visible: an
/// image with four channels, half of it transparent, so "transparency
/// survived" is something the assertions can actually be about.
List<int> _makePng() {
  final image = img.Image(width: 64, height: 64, numChannels: 4);
  for (var y = 0; y < 64; y++) {
    for (var x = 0; x < 64; x++) {
      image.setPixelRgba(x, y, 220, 40, 90, x < 32 ? 255 : 0);
    }
  }
  return img.encodePng(image);
}
