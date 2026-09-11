import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/channel.dart';
import 'package:privio/screens/channel_admins_screen.dart';
import 'package:privio/screens/channel_profile_screen.dart';
import 'package:privio/screens/channel_subscribers_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_theme.dart';

import 'support/fake_voice.dart';

/// The four channel screens, driven the way the four roles in the brief meet
/// them: an owner, an admin who was given less, a subscriber, and somebody
/// outside the channel.
///
/// Every one of these is a permission question before it is a layout question,
/// which is why they are tested through the screens rather than through the
/// controller: what matters is what a given person can *see and reach*.

/// A channel with whatever role and permissions the test wants to try.
ChannelInfo channelFor({
  String? role,
  ChannelPermissions permissions = const ChannelPermissions(),
  int memberCount = 34,
  bool muted = false,
  String? description,
  String? handle = 'houseoftrading',
}) =>
    ChannelInfo(
      id: 'channel-1',
      visibility: ChannelVisibility.public,
      title: 'HouseOfTrading',
      handle: handle,
      description: description,
      memberCount: memberCount,
      role: role,
      permissions: permissions,
      muted: muted,
      hasKey: true,
    );

ChannelPermissions get ownerPermissions => const ChannelPermissions(
      canPost: true,
      canEditChannel: true,
      canDeletePosts: true,
      canManageMembers: true,
      canDeleteChannel: true,
      canModerateDiscussion: true,
      canManageInvites: true,
      canManageLivestreams: true,
      canAppointAdmins: true,
    );

/// What the server answers. Each test overrides just the bits it cares about.
class FakeServer {
  FakeServer({this.live, this.members, this.adminMembers, this.complete = true});

  Map<String, dynamic>? live;
  List<Map<String, dynamic>>? members;
  List<Map<String, dynamic>>? adminMembers;

  /// What the real server answers a subscriber: the list they were given is the
  /// channel's staff and themselves, not its audience.
  bool complete;

  /// Every request that went out, so a test can assert on what was asked for
  /// as well as what came back.
  final List<String> seen = [];

  http.Client client() => MockClient((request) async {
        seen.add('${request.method} ${request.url.path}?${request.url.query}');
        final path = request.url.path;

        if (path.endsWith('/live')) {
          return _json(
            live ?? {'available': false, 'canStart': false, 'live': null, 'access': null},
          );
        }
        if (path.endsWith('/members')) {
          final wantsAdmins = request.url.queryParameters['role'] == 'admins';
          return _json({
            'complete': complete,
            'more': false,
            'nextCursor': null,
            'members': (wantsAdmins ? adminMembers : members) ?? const [],
          });
        }
        if (path.endsWith('/posts')) return _json({'posts': const []});
        if (path.endsWith('/bans')) return _json({'banned': const []});
        if (path == '/v1/channels') return _json({'channels': const []});
        return _json(const {});
      });

  http.Response _json(Map<String, dynamic> body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
}

Future<AppState> stateWith(FakeServer server, ChannelInfo channel) async {
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: server.client(),
  )..useToken('token');
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  final store = InMemoryMessageStore();
  final secure = InMemorySecureStore();
  final state = AppState(
    services: PrivioServices(
      api: api,
      crypto: crypto,
      messaging: messaging,
      channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
      recorder: FakeVoiceRecorder(),
      player: FakeVoicePlayer(),
      store: store,
      secureStore: secure,
      backup: BackupService(api: api, store: secure, messages: store),
    ),
    store: secure,
  );
  await state.initialise();
  // Seeded through the public door, so the channel is in the controller's own
  // lists exactly as a refresh would have put it there.
  state.channels.adopt(channel);
  return state;
}

Widget wrap(Widget child, AppState state) => PrivioScope(
      notifier: state,
      child: MaterialApp(theme: PrivioTheme.dark(), home: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what a permission set can say about itself', () {
    test('lists every permission exactly once, so no screen can omit one', () {
      final keys = ChannelPermissions.all.map((p) => p.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(keys, contains('canAppointAdmins'));
      expect(keys, contains('canModerateDiscussion'));
      expect(keys, contains('canManageInvites'));
      expect(keys, contains('canManageLivestreams'));
    });

    test('covers is the same rule the server enforces', () {
      const holder = ChannelPermissions(canPost: true, canManageMembers: true);
      expect(holder.covers(const ChannelPermissions(canPost: true)), isTrue);
      expect(
        holder.covers(const ChannelPermissions(canAppointAdmins: true)),
        isFalse,
        reason: 'you cannot hand out authority you do not have',
      );
      expect(holder.covers(const ChannelPermissions()), isTrue);
    });

    test('withFlag changes one and leaves the rest', () {
      const start = ChannelPermissions(canPost: true);
      final after = start.withFlag('canManageInvites', on: true);
      expect(after.canPost, isTrue);
      expect(after.canManageInvites, isTrue);
      expect(after.canAppointAdmins, isFalse);
    });

    test('a round trip through JSON keeps the new flags', () {
      const original = ChannelPermissions(
        canModerateDiscussion: true,
        canManageLivestreams: true,
      );
      final back = ChannelPermissions.fromJson(original.toJson());
      expect(back.canModerateDiscussion, isTrue);
      expect(back.canManageLivestreams, isTrue);
      expect(back.canPost, isFalse);
    });
  });

  group('presence is the member own setting, never a guess', () {
    test('says nothing at all where they do not share it', () {
      const member = ChannelMember(id: 'a', username: 'bob');
      expect(
        member.presenceLabel(),
        '',
        reason: 'not knowing is not the same as knowing it was long ago',
      );
    });

    test('reads back the way a person would say it', () {
      final now = DateTime(2026, 9, 11, 12);
      String at(Duration ago) => ChannelMember(
            id: 'a',
            username: 'bob',
            lastSeenAt: now.subtract(ago),
          ).presenceLabel(now: now);

      expect(at(const Duration(seconds: 30)), 'online');
      expect(at(const Duration(minutes: 20)), 'last seen 20 minutes ago');
      expect(at(const Duration(hours: 5)), 'last seen 5 hours ago');
      expect(at(const Duration(days: 3)), 'last seen 3 days ago');
      expect(at(const Duration(days: 40)), startsWith('last seen '));
    });
  });

  group('the profile screen', () {
    testWidgets('shows the channel, its audience and the four actions',
        (tester) async {
      final server = FakeServer();
      final state = await stateWith(
        server,
        channelFor(role: 'owner', permissions: ownerPermissions, description: 'Daily'),
      );

      await tester.pumpWidget(
        wrap(ChannelProfileScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      expect(find.text('HouseOfTrading'), findsOneWidget);
      expect(find.text('34 subscribers'), findsOneWidget);
      for (final action in ['livestream', 'mute', 'search', 'more']) {
        expect(find.text(action), findsOneWidget, reason: 'all four, equally sized');
      }
      expect(find.textContaining('privio.channel/houseoftrading'), findsOneWidget);
      expect(find.text('Daily'), findsOneWidget);
      expect(find.text('Administrators'), findsOneWidget);
      expect(find.text('Subscribers'), findsOneWidget);
      expect(find.text('Channel settings'), findsOneWidget);
    });

    testWidgets('offers Edit and Channel settings only to somebody who may edit',
        (tester) async {
      final server = FakeServer();
      final state = await stateWith(server, channelFor(role: 'subscriber'));

      await tester.pumpWidget(
        wrap(ChannelProfileScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Channel settings'), findsNothing);
      // What a subscriber still gets: the channel, its link, and the lists.
      expect(find.text('Subscribers'), findsOneWidget);
    });

    testWidgets('says why a livestream is unavailable instead of doing nothing',
        (tester) async {
      final server = FakeServer();
      final state = await stateWith(
        server,
        channelFor(role: 'owner', permissions: ownerPermissions),
      );

      await tester.pumpWidget(
        wrap(ChannelProfileScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('livestream'));
      await tester.pumpAndSettle();

      expect(find.text('Livestreams are not set up'), findsOneWidget);
      expect(
        find.textContaining('cannot be done device to device'),
        findsOneWidget,
        reason: 'the reason, not a shrug',
      );
    });

    testWidgets('draws the mute action from the state it is actually in',
        (tester) async {
      final server = FakeServer();
      final state = await stateWith(server, channelFor(role: 'subscriber', muted: true));

      await tester.pumpWidget(
        wrap(ChannelProfileScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      expect(find.text('unmute'), findsOneWidget);
      expect(find.text('mute'), findsNothing);
    });
  });

  group('the admin screen', () {
    List<Map<String, dynamic>> staff() => [
          {
            'id': 'owner-1',
            'username': 'nfnc',
            'role': 'owner',
            'permissions': ownerPermissions.toJson(),
          },
          {
            'id': 'admin-1',
            'username': 'kralle',
            'displayName': 'Papa Kralle',
            'role': 'admin',
            'permissions': const ChannelPermissions(canPost: true).toJson(),
            'promotedBy': {'id': 'owner-1', 'username': 'nfnc'},
          },
        ];

    testWidgets('shows the roles apart, and who appointed each admin',
        (tester) async {
      final server = FakeServer(adminMembers: staff());
      final state = await stateWith(
        server,
        channelFor(role: 'owner', permissions: ownerPermissions),
      );

      await tester.pumpWidget(
        wrap(ChannelAdminsScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Papa Kralle'), findsOneWidget);
      expect(find.text('promoted by nfnc'), findsOneWidget);
      expect(find.text('CHANNEL ADMINISTRATORS'), findsOneWidget);
      expect(find.text('Add admin'), findsOneWidget);
    });

    testWidgets('hides Add admin from somebody who cannot appoint one',
        (tester) async {
      // An admin who may manage members but was not given the appointing
      // permission — the case that used to be the same flag.
      final server = FakeServer(adminMembers: staff());
      final state = await stateWith(
        server,
        channelFor(
          role: 'admin',
          permissions: const ChannelPermissions(canPost: true, canManageMembers: true),
        ),
      );

      await tester.pumpWidget(
        wrap(ChannelAdminsScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add admin'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(
        find.textContaining('Only somebody who may appoint admins'),
        findsOneWidget,
        reason: 'the rule is shown, not silently applied',
      );
      // The list itself is not a secret from a member.
      expect(find.text('Papa Kralle'), findsOneWidget);
    });

    testWidgets('lets the owner toggle the signature, and nobody else',
        (tester) async {
      final server = FakeServer(adminMembers: staff());
      final asOwner = await stateWith(
        server,
        channelFor(role: 'owner', permissions: ownerPermissions),
      );
      await tester.pumpWidget(
        wrap(ChannelAdminsScreen(channel: asOwner.channels.mine.single), asOwner),
      );
      await tester.pumpAndSettle();
      expect(find.text('Show sender name'), findsOneWidget);
      expect(
        tester.widget<Switch>(find.byType(Switch).last).onChanged,
        isNotNull,
      );

      final asSubscriber = await stateWith(server, channelFor(role: 'subscriber'));
      await tester.pumpWidget(
        wrap(
          ChannelAdminsScreen(channel: asSubscriber.channels.mine.single),
          asSubscriber,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(find.byType(Switch).last).onChanged,
        isNull,
        reason: 'shown and disabled, not hidden',
      );
    });
  });

  group('the subscriber screen', () {
    List<Map<String, dynamic>> people() => [
          {
            'id': 'a',
            'username': 'kralle',
            'displayName': 'Papa Kralle',
            'role': 'admin',
            'isContact': true,
            'permissions': const ChannelPermissions(canPost: true).toJson(),
          },
          {'id': 'b', 'username': 'ztarzz', 'role': 'subscriber', 'isContact': false},
          {'id': 'c', 'username': 'og', 'role': 'subscriber', 'isContact': false},
        ];

    testWidgets('splits contacts from everybody else, as the design does',
        (tester) async {
      final server = FakeServer(members: people());
      final state = await stateWith(
        server,
        channelFor(role: 'owner', permissions: ownerPermissions),
      );

      await tester.pumpWidget(
        wrap(ChannelSubscribersScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      expect(find.text('CONTACTS IN THIS CHANNEL'), findsOneWidget);
      expect(find.text('OTHER SUBSCRIBERS'), findsOneWidget);
      expect(find.text('Papa Kralle'), findsOneWidget);
      expect(find.text('ztarzz'), findsOneWidget);
      expect(find.text('Add subscribers'), findsOneWidget);
      expect(find.text('Only channel administrators see this list.'), findsOneWidget);
    });

    testWidgets('tells a subscriber the list is not the whole list', (tester) async {
      final server = FakeServer(members: people(), complete: false);
      final state = await stateWith(server, channelFor(role: 'subscriber'));

      await tester.pumpWidget(
        wrap(ChannelSubscribersScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add subscribers'), findsNothing);
      expect(
        find.textContaining('This is not the whole list'),
        findsOneWidget,
        reason: 'a short list passed off as everybody is the thing to avoid',
      );
    });

    testWidgets('asks the server to search rather than filtering what it has',
        (tester) async {
      final server = FakeServer(members: people());
      final state = await stateWith(
        server,
        channelFor(role: 'owner', permissions: ownerPermissions),
      );

      await tester.pumpWidget(
        wrap(ChannelSubscribersScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'kralle');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        server.seen.any((r) => r.contains('q=kralle')),
        isTrue,
        reason: 'a channel with thousands of people cannot be downloaded to filter',
      );
    });
  });
}
