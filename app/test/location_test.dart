import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/conversation_controller.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/archive.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/location/device_location.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/geo_point.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chat_screen.dart';
import 'package:privio/screens/privacy_screen.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/widgets/location_card.dart';

import 'deletion_test.dart' show buildServices, storeWith;
import 'group_receipts_test.dart' show groupOf;
import 'support/fake_voice.dart';
import 'widget_test.dart' show wrap;

/// Sharing a place: two numbers, sealed like any message, shown before they go.
///
/// What these pin: nothing leaves without the person seeing it, nothing at
/// all is asked of the phone while sharing is switched off, no map server is
/// ever told the place, and a place the app cannot read is shown as the text
/// an older build would show.

const zurich = GeoPoint(latitude: 47.3768866, longitude: 8.5416940, accuracyMeters: 12);

IncomingMessage arriving(MessagePayload payload, {String from = 'account-bob'}) => IncomingMessage(
      envelopeId: 3,
      senderAccountId: from,
      payload: payload,
      receivedAt: DateTime(2026, 1, 1, 12, 10),
    );

/// Answers like the phone would, and counts how often it was asked.
class FakeDeviceLocation implements DeviceLocation {
  FakeDeviceLocation(this.answer);

  LocationRead answer;
  int asked = 0;

  @override
  Future<LocationRead> current() async {
    asked += 1;
    return answer;
  }
}

/// A signed-in state over [location], with Bob's chat in it.
Future<AppState> chatWithBob(DeviceLocation location) async {
  final api = PrivioApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(
      (request) async => http.Response(
        // Enough of every answer a signed-in start asks for; the prekey count
        // keeps it from topping up keys in the middle of a test.
        jsonEncode({'contacts': <Object>[], 'envelopes': <Object>[], 'more': false, 'remaining': 100}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
  final crypto = await PrivioCrypto.open(InMemoryCryptoStorage());
  final messaging = MessagingService(api: api, crypto: crypto);
  final services = PrivioServices(
    api: api,
    crypto: crypto,
    messaging: messaging,
    channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
    recorder: FakeVoiceRecorder(),
    player: FakeVoicePlayer(),
    deviceLocation: location,
    backup: BackupService(api: api, store: InMemorySecureStore(), messages: InMemoryMessageStore()),
    store: InMemoryMessageStore(),
    secureStore: InMemorySecureStore(),
  );
  final state = AppState(services: services, store: InMemorySecureStore());
  await state.initialise();
  state.conversations.accountId = 'acc-alice';
  services.store
    ..upsertUser(const KnownUser(accountId: 'acc-bob', username: 'bob'))
    ..append('acc-bob', Message(id: 'b1', body: 'wo bist du?', sentAt: DateTime(2026, 9, 22), isMine: false));
  return state;
}

Future<void> openAttachMenu(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(wrap(const ChatScreen(accountId: 'acc-bob', title: 'bob'), state));
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.byIcon(Icons.add_rounded));
  await tester.pumpAndSettle();
}

void main() {
  group('a place', () {
    test('is on the planet and finite, or it is not a place', () {
      expect(zurich.isValid, isTrue);
      expect(const GeoPoint(latitude: 90, longitude: -180).isValid, isTrue);
      expect(const GeoPoint(latitude: 90.0001, longitude: 0).isValid, isFalse);
      expect(const GeoPoint(latitude: 0, longitude: 180.0001).isValid, isFalse);
      expect(const GeoPoint(latitude: double.nan, longitude: 0).isValid, isFalse);
      expect(const GeoPoint(latitude: 0, longitude: double.infinity).isValid, isFalse);
      expect(const GeoPoint(latitude: 0, longitude: 0, accuracyMeters: -1).isValid, isFalse);
    });

    test('is rounded to what a phone can measure, and written with points', () {
      final rounded = zurich.rounded();
      expect(rounded.latitude, 47.376887);
      expect(rounded.longitude, 8.541694);
      expect(rounded.coordinates, '47.376887, 8.541694');
    });

    test('reads back only what is a place', () {
      expect(GeoPoint.fromJson(zurich.toJson()), zurich);
      expect(GeoPoint.fromJson({'la': 'x', 'lo': 8}), isNull);
      expect(GeoPoint.fromJson({'la': 95, 'lo': 8}), isNull);
      expect(GeoPoint.fromJson('47,8'), isNull);
    });
  });

  group('the payload', () {
    test('survives encoding, is a message, and carries nothing else', () {
      final payload = MessagePayload.location(
        body: zurich.coordinates,
        location: zurich,
        clientId: 'l1',
      );
      final json = jsonDecode(payload.encode()) as Map<String, dynamic>;
      expect(json['t'], 'loc');
      expect(json.keys.toSet(), {'v', 't', 'b', 'ci', 'gl'});

      final decoded = MessagePayload.decode(payload.encode());
      expect(decoded.isLocation, isTrue);
      expect(decoded.isControl, isFalse);
      expect(decoded.location, zurich);
      expect(decoded.body, zurich.coordinates);
    });

    test('a place off the planet is read as its text, as an older build reads it', () {
      final raw = jsonEncode({
        'v': 1,
        't': 'loc',
        'b': '95.0, 8.0',
        'gl': {'la': 95.0, 'lo': 8.0},
      });
      final decoded = MessagePayload.decode(raw);
      expect(decoded.isLocation, isFalse);
      expect(decoded.body, '95.0, 8.0');
    });

    test('attaching the profile key keeps the place', () {
      final payload = MessagePayload.location(body: zurich.coordinates, location: zurich)
          .withProfileKey('pk');
      expect(payload.location, zurich);
      expect(payload.profileKey, 'pk');
    });
  });

  group('sending', () {
    test('files the place here and sends it sealed, rounded, with its text', () async {
      final store = storeWith([]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      expect(await controller.sendLocation('account-bob', zurich), isTrue);

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.kind, MessageKind.location);
      expect(message.location, zurich.rounded());
      expect(message.body, '47.376887, 8.541694');
      final sent = messaging.sent.single;
      expect(sent.isLocation, isTrue);
      expect(sent.location, zurich.rounded());
      expect(sent.body, '47.376887, 8.541694',
          reason: 'what an older build shows, and what a reply quotes');
    });

    test('to a group goes to the group', () async {
      final store = groupOf(3);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      await controller.sendLocation('group-1', zurich);
      expect(messaging.sentToGroup.single.location, zurich.rounded());
    });

    test('is refused while sharing is switched off, and for what is not a place', () async {
      final store = storeWith([]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      expect(
        await controller.sendLocation('account-bob', const GeoPoint(latitude: 91, longitude: 0)),
        isFalse,
      );
      await controller.setShareLocation(false);
      expect(await controller.sendLocation('account-bob', zurich), isFalse);

      expect(store.conversationWith('account-bob')!.messages, isEmpty);
      expect(messaging.sent, isEmpty);
    });

    test('the switch is kept per account, and on until switched off', () async {
      final store = storeWith([]);
      final (services, _) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      expect(controller.shareLocation, isTrue);
      expect(await services.secureStore.readShareLocation('account-alice'), isTrue);

      await controller.setShareLocation(false);
      expect(await services.secureStore.readShareLocation('account-alice'), isFalse);
      expect(await services.secureStore.readShareLocation('account-carol'), isTrue);

      final again = ConversationController(services)..accountId = 'account-alice';
      addTearDown(again.stop);
      await again.loadShareLocation('account-alice');
      expect(again.shareLocation, isFalse);
    });
  });

  group('receiving', () {
    test('a place arrives as a place, and the chat list never shows where', () async {
      final store = storeWith([]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      messaging.inbox.add(arriving(MessagePayload.location(
        body: zurich.coordinates,
        location: zurich,
        clientId: 'l1',
      )));
      await controller.drain();

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.kind, MessageKind.location);
      expect(message.location, zurich);
      final preview = controller.chats.single.preview;
      expect(preview.kind, ChatPreviewKind.location);
      expect(preview.text, isNull, reason: 'the coordinates were put in the chat list');
    });

    test('a copy from this account’s other device is filed as a place too', () async {
      final store = storeWith([]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);

      final inner = MessagePayload.location(body: zurich.coordinates, location: zurich, clientId: 'l2');
      messaging.inbox.add(arriving(
        MessagePayload.sync(
          SyncEnvelope(conversationId: 'account-bob', isGroup: false, payload: inner.encode()),
        ),
        from: 'account-alice',
      ));
      await controller.drain();

      final message = store.conversationWith('account-bob')!.messages.single;
      expect(message.isMine, isTrue);
      expect(message.kind, MessageKind.location);
      expect(message.location, zurich);
    });

    test('a place written into Saved on another device lands in Saved as a place', () async {
      final store = storeWith([]);
      final (services, messaging) = await buildServices(store);
      final controller = ConversationController(services)..accountId = 'account-alice';
      addTearDown(controller.stop);
      controller.ensureSaved(username: 'alice');

      messaging.inbox.add(arriving(
        MessagePayload.location(body: zurich.coordinates, location: zurich, clientId: 'l3'),
        from: 'account-alice',
      ));
      await controller.drain();

      final message = store.conversationWith('account-alice')!.messages.single;
      expect(message.kind, MessageKind.location);
      expect(message.location, zurich);
    });

    test('a place survives the archive', () async {
      final store = storeWith([])
        ..append(
          'account-bob',
          Message(
            id: 'l1',
            clientId: 'l1',
            body: zurich.coordinates,
            kind: MessageKind.location,
            location: zurich,
            sentAt: DateTime(2026),
            isMine: false,
          ),
        );
      final archive = EncryptedMessageArchive(
        storage: InMemoryArchiveStorage(),
        keyStore: InMemorySecureStore(),
      );
      await archive.save(store.conversations());

      final restored = InMemoryMessageStore()..restore((await archive.load()).conversations);
      final message = restored.conversationWith('account-bob')!.messages.single;
      expect(message.kind, MessageKind.location);
      expect(message.location, zurich);
    });
  });

  group('asking the phone', () {
    const channel = MethodChannel('app.privio/location');

    Future<LocationRead> answeredWith(Future<Object?> Function(MethodCall call) handler) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      return const ChannelDeviceLocation().current();
    }

    testWidgets('a fix is a place', (tester) async {
      final read = await answeredWith(
        (_) async => {'latitude': 47.3768866, 'longitude': 8.541694, 'accuracy': 11.6},
      );
      expect((read as LocationFix).point,
          const GeoPoint(latitude: 47.3768866, longitude: 8.541694, accuracyMeters: 12));
    });

    testWidgets('a refusal is a refusal, and nothing else is', (tester) async {
      expect(
        await answeredWith((_) async => throw PlatformException(code: 'permission_denied')),
        isA<LocationDenied>(),
      );
      expect(
        await answeredWith((_) async => throw PlatformException(code: 'unavailable')),
        isA<LocationUnavailable>(),
      );
      expect(
        await answeredWith((_) async => {'latitude': 95.0, 'longitude': 8.0}),
        isA<LocationUnavailable>(),
      );
      expect(await const NoDeviceLocation().current(), isA<LocationUnsupported>());
    });
  });

  group('on screen', () {
    test('a maps app is opened by the platform’s own address', () {
      expect(
        mapsUri(zurich, TargetPlatform.android).toString(),
        'geo:47.3768866,8.541694?q=47.3768866,8.541694',
      );
      final apple = mapsUri(zurich, TargetPlatform.iOS);
      expect(apple.host, 'maps.apple.com');
      expect(apple.queryParameters['ll'], '47.3768866,8.541694');
    });

    testWidgets('the card asks before a maps app sees the place, and copies without asking',
        (tester) async {
      final opened = <Uri>[];
      var answer = true;
      final state = await chatWithBob(FakeDeviceLocation(const LocationUnavailable()));
      addTearDown(state.conversations.stop);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map<Object?, Object?>)['text'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(wrap(
        Scaffold(
          body: LocationCard(
            point: zurich,
            opener: (uri) async {
              opened.add(uri);
              return answer;
            },
          ),
        ),
        state,
      ));

      expect(find.text('47.376887, 8.541694'), findsOneWidget);
      expect(find.text('within 12 m'), findsOneWidget);

      await tester.tap(find.byKey(const Key('location-open')));
      await tester.pumpAndSettle();
      expect(find.text('Your maps app, and the map service behind it, will see this place.'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty, reason: 'a maps app saw the place before anybody said yes');

      await tester.tap(find.byKey(const Key('location-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(opened.single.scheme, 'geo');

      answer = false;
      await tester.tap(find.byKey(const Key('location-open')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('No app on this phone can open a place.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.byKey(const Key('location-copy')));
      await tester.pump();
      expect(copied, ['47.376887, 8.541694']);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('sharing shows the place and sends only after a yes', (tester) async {
      final phone = FakeDeviceLocation(const LocationFix(zurich));
      final state = await chatWithBob(phone);
      addTearDown(state.conversations.stop);
      await openAttachMenu(tester, state);

      await tester.tap(find.byKey(const Key('attach-location')));
      await tester.pumpAndSettle();
      expect(phone.asked, 1);
      expect(find.text('Send your location?'), findsOneWidget);
      expect(find.text('47.376887, 8.541694'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.conversations.messagesWith('acc-bob').where((m) => m.isMine), isEmpty);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('attach-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('location-send')));
      await tester.pump(const Duration(seconds: 1));

      final mine = state.conversations.messagesWith('acc-bob').where((m) => m.isMine).single;
      expect(mine.kind, MessageKind.location);
      expect(find.byType(LocationCard), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a refusal says where to change it, and sends nothing', (tester) async {
      final state = await chatWithBob(FakeDeviceLocation(const LocationDenied()));
      addTearDown(state.conversations.stop);
      await openAttachMenu(tester, state);

      await tester.tap(find.byKey(const Key('attach-location')));
      await tester.pumpAndSettle();
      expect(
        find.text('Privio may not use your location. You can allow it in the system settings.'),
        findsOneWidget,
      );
      expect(find.text('Send your location?'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('switched off, the option is gone and the phone is never asked', (tester) async {
      final phone = FakeDeviceLocation(const LocationFix(zurich));
      final state = await chatWithBob(phone);
      addTearDown(state.conversations.stop);
      await state.conversations.setShareLocation(false);
      await openAttachMenu(tester, state);

      expect(find.byKey(const Key('attach-location')), findsNothing);
      expect(phone.asked, 0);
    });

    testWidgets('a signed-in start knows when it is switched off', (tester) async {
      final secure = InMemorySecureStore();
      await secure.writeSession(token: 'session', username: 'alice', accountId: 'acc-alice');
      final state = await chatWithBob(FakeDeviceLocation(const LocationUnavailable()));
      addTearDown(state.conversations.stop);
      // Where the controller reads it. In the app this is the same store as the
      // one holding the session; the helper makes its own.
      await state.services.secureStore.writeShareLocation('acc-alice', false);
      final signedIn = AppState(services: state.services, store: secure);
      await signedIn.initialise();
      await tester.pump(const Duration(seconds: 1));

      expect(signedIn.conversations.shareLocation, isFalse);
      // A signed-in start keeps timers of its own; stopped inside the test,
      // because the pending-timer check runs before any tear-down.
      signedIn.conversations.stop();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the switch lives in Privacy', (tester) async {
      final state = await chatWithBob(FakeDeviceLocation(const LocationUnavailable()));
      addTearDown(state.conversations.stop);
      await tester.pumpWidget(wrap(const PrivacyScreen(), state));
      await tester.pump(const Duration(seconds: 1));

      final toggle = find.byKey(const ValueKey('share-location'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pump(const Duration(seconds: 1));
      expect(state.conversations.shareLocation, isFalse);
    });
  });
}
