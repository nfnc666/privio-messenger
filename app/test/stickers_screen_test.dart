import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/core/sticker_controller.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/sticker_pack_screen.dart';
import 'package:privio/screens/stickers_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';

import 'support/fake_voice.dart';

/// The packs the fake server holds, rewritten per test.
List<Map<String, dynamic>> _packs = [];

http.Client _server() => MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && (path == '/v1/accounts' || path == '/v1/sessions')) {
        final username = (jsonDecode(request.body) as Map<String, dynamic>)['username'] as String;
        return _json({
          'token': 'token-$username',
          'accountId': 'acc-$username',
          'username': username,
          'deviceId': 'device-1',
        }, status: path == '/v1/accounts' ? 201 : 200);
      }
      if (path == '/v1/keys/count') return _json(const {'remaining': 50});
      if (path == '/v1/accounts/me') {
        return _json(const {
          'accountId': 'acc',
          'username': 'x',
          'avatarMediaId': null,
          'privacy': <String, dynamic>{},
          'twoFactorEnabled': false,
          'duressCodeSet': false,
        });
      }
      if (path == '/v1/sticker-packs') return _json({'packs': _packs});
      if (path == '/v1/sticker-uses') return _json(const {'uses': <Map<String, dynamic>>[]});
      if (path.startsWith('/v1/media/')) return http.Response.bytes(const [], 200);
      return _json(const {'contacts': [], 'envelopes': [], 'more': false, 'channels': []});
    });

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _pack({
  required String id,
  required String title,
  String kind = 'sticker',
  bool installed = false,
  String? shareCode,
  int items = 0,
}) =>
    {
      'id': id,
      'kind': kind,
      'title': title,
      'shareCode': shareCode,
      'shared': shareCode != null,
      'installed': installed,
      'updatedAt': DateTime.utc(2026).toIso8601String(),
      'items': [
        for (var i = 0; i < items; i++)
          {'id': '$id-item-$i', 'mediaId': '$id-media-$i', 'emoji': '😺', 'position': i},
      ],
    };

Future<PrivioServices> _services() async {
  final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: _server());
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  return PrivioServices(
    api: api,
    crypto: crypto,
    messaging: messaging,
    channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
    recorder: FakeVoiceRecorder(),
    player: FakeVoicePlayer(),
    backup: BackupService(
      api: api,
      store: InMemorySecureStore(),
      messages: InMemoryMessageStore(),
    ),
    store: InMemoryMessageStore(),
    secureStore: InMemorySecureStore(),
  );
}

Widget _over(AppState state, Widget screen) => PrivioScope(
      notifier: state,
      child: ListenableBuilder(
        listenable: Listenable.merge([state, state.stickers]),
        builder: (context, _) => MaterialApp(
          theme: PrivioTheme.dark(),
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: screen,
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<AppState> _signedIn(WidgetTester tester) async {
  final state = await tester.runAsync(() async {
    final app = AppState(services: await _services(), store: InMemorySecureStore());
    await app.initialise();
    return app;
  }) as AppState;
  await tester.runAsync(() => state.signIn(username: 'alice', password: 'correct-horse'));
  addTearDown(state.conversations.stop);
  return state;
}

void main() {
  setUp(() => _packs = []);

  testWidgets('with nothing there, it says so rather than showing an empty list',
      (tester) async {
    final state = await _signedIn(tester);
    await tester.pumpWidget(_over(state, const StickersScreen()));
    await _settle(tester);

    expect(find.text('No packs yet'), findsOneWidget);
  });

  testWidgets('own packs and added packs are shown apart', (tester) async {
    _packs = [
      _pack(id: 'mine', title: 'My cats', items: 2),
      _pack(id: 'theirs', title: 'Their dogs', installed: true, items: 1),
    ];
    final state = await _signedIn(tester);
    await tester.pumpWidget(_over(state, const StickersScreen()));
    await _settle(tester);

    // Upper-cased by SettingsSection, which is how every caption in settings
    // is drawn. Asserted as it is rendered rather than as it is written.
    expect(find.text('MY PACKS'), findsOneWidget);
    expect(find.text('ADDED'), findsOneWidget);
    expect(find.text('My cats'), findsOneWidget);
    expect(find.text('Their dogs'), findsOneWidget);
    // The count is drawn from the pack, not from a placeholder.
    expect(find.textContaining('2 pictures'), findsOneWidget);
    expect(find.textContaining('1 picture'), findsOneWidget);
  });

  testWidgets('a pack of mine offers sharing, renaming and deleting', (tester) async {
    _packs = [_pack(id: 'mine', title: 'My cats', items: 1)];
    final state = await _signedIn(tester);
    await tester.pumpWidget(_over(state, const StickerPackScreen(packId: 'mine')));
    await _settle(tester);

    expect(find.text('SHARE THIS PACK'), findsOneWidget);
    expect(find.text('Share this pack'), findsOneWidget);
    expect(find.text('Private. Only you can see it.'), findsOneWidget);
    expect(find.text('Delete pack'), findsOneWidget);
    expect(find.text('Add a picture'), findsOneWidget);
    // And it says, before anything is shared, what sharing means.
    expect(find.textContaining('Sticker pictures are not encrypted'), findsOneWidget);
  });

  testWidgets('an added pack offers only to be dropped', (tester) async {
    _packs = [_pack(id: 'theirs', title: 'Their dogs', installed: true, items: 1)];
    final state = await _signedIn(tester);
    await tester.pumpWidget(_over(state, const StickerPackScreen(packId: 'theirs')));
    await _settle(tester);

    expect(find.text('Remove from my packs'), findsOneWidget);
    // None of the owner's controls: this pack is not this account's to change.
    expect(find.text('Delete pack'), findsNothing);
    expect(find.text('Add a picture'), findsNothing);
    expect(find.text('Share this pack'), findsNothing);
  });

  testWidgets('a pack reached by a link shows Add, and does not add itself',
      (tester) async {
    final state = await _signedIn(tester);
    await tester.pumpWidget(
      _over(
        state,
        StickerPackScreen(
          packId: 'linked',
          // What `previewByCode` hands the screen: somebody else's pack, with
          // no share code of theirs — the server never sends one.
          preview: StickerPack.fromJson(
            _pack(id: 'linked', title: 'A pack somebody shared', items: 2),
          ),
          shareCode: 'code-1',
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('Add pack'), findsOneWidget);
    expect(find.text('Remove from my packs'), findsNothing);
    expect(find.text('Delete pack'), findsNothing);
  });
}
