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
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';
import 'package:flutter/services.dart';
import 'package:privio/screens/about_screen.dart';
import 'package:privio/screens/chats_screen.dart';
import 'package:privio/screens/invite_screen.dart';
import 'package:privio/screens/settings_screen.dart';
import 'package:privio/screens/storage_screen.dart';
import 'package:privio/services/messaging_service.dart';
import 'package:privio/theme/privio_colors.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/services/backup_service.dart';
import 'package:privio/services/channel_service.dart';

import 'support/fake_voice.dart';
import 'package:privio/widgets/chat_list_row.dart';
import 'package:privio/widgets/message_bubble.dart';

/// Services wired to a server that answers with empty collections, so screens
/// can be driven from a store seeded by the test itself.
Future<PrivioServices> quietServices() async {
  final client = MockClient((request) async => http.Response(
        jsonEncode(const {'contacts': [], 'envelopes': [], 'more': false}),
        200,
        headers: {'content-type': 'application/json'},
      ),);
  final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: client);
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

/// The scope goes *outside* the MaterialApp, as it does in `app.dart`.
///
/// Inside `home` it is a sibling of every pushed route rather than an ancestor,
/// so a screen that opens another one and reads the scope there finds nothing —
/// which is a property of this helper and not of the app.
Widget wrap(Widget child, AppState state) => PrivioScope(
      notifier: state,
      child: MaterialApp(
        theme: PrivioTheme.dark(),
        // As in `app.dart`: a screen that asks for a translated string needs
        // the delegates above it, and a helper without them fails on the
        // lookup rather than on anything the test is about.
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: child,
      ),
    );

void main() {
  testWidgets('every button on the invite screen does what it says', (tester) async {
    final services = await quietServices();
    final state = AppState(services: services, store: InMemorySecureStore());
    await state.initialise();

    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map<Object?, Object?>)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(wrap(const InviteScreen(), state));
    await tester.pumpAndSettle();

    // It used to read "Share Link" and do nothing at all.
    await tester.tap(find.text('Copy invite link'));
    await tester.pumpAndSettle();
    expect(copied, hasLength(1));
    expect(copied.single, contains('/u/'));

    // And the QR tab used to offer "Save to Photos", which also did nothing.
    expect(find.text('Save to Photos'), findsNothing);
  });

  testWidgets('settings has no row that opens nothing', (tester) async {
    final services = await quietServices();
    final state = AppState(services: services, store: InMemorySecureStore());
    await state.initialise();

    await tester.pumpWidget(wrap(const SettingsScreen(), state));
    await tester.pumpAndSettle();

    // Settings is opened from the Account tab, so a row back to it was a
    // circle with a dead button at the top of it.
    expect(find.text('Account'), findsNothing);
    expect(
      find.text('Privacy & Security'),
      findsOneWidget,
      reason: 'the rows that do open something are still there',
    );

    // "Data and Storage" opened nothing until there was something true to put
    // on it. The rule was never that the row must not exist.
    expect(find.text('Data and Storage'), findsOneWidget);
    await tester.tap(find.text('Data and Storage'));
    // Not pumpAndSettle: the screen shows a spinner while it measures, and a
    // spinner never settles.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(StorageScreen), findsOneWidget);
    expect(find.text('Conversation history'), findsOneWidget);
    // Down the page, so it has to be scrolled to rather than merely found.
    await tester.dragUntilVisible(
      find.text('Delete history on this device'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.text('Delete history on this device'), findsOneWidget);
  });

  testWidgets('about names no document that does not exist', (tester) async {
    final services = await quietServices();
    final state = AppState(services: services, store: InMemorySecureStore());
    await state.initialise();

    await tester.pumpWidget(wrap(const AboutScreen(), state));
    await tester.pumpAndSettle();

    expect(find.text('Terms of Service'), findsNothing);
    expect(find.text('Privacy Policy'), findsNothing);
    expect(find.text('Source code'), findsOneWidget);
  });

  testWidgets('the chat list shows decrypted conversations', (tester) async {
    final services = await quietServices();
    final state = AppState(
      services: services,
      store: InMemorySecureStore(),
    );
    await state.initialise();

    services.store.upsertUser(
      const KnownUser(accountId: 'acc-alice', username: 'alice', displayName: 'Alice'),
    );
    services.store.append(
      'acc-alice',
      Message(
        id: '1',
        body: 'Hey! How are you?',
        sentAt: DateTime.now(),
        isMine: false,
      ),
    );

    await tester.pumpWidget(wrap(const ChatsScreen(), state));
    await tester.pump();

    expect(find.text('Privio'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Hey! How are you?'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'one unread message');
  });

  testWidgets('an account with no conversations is told what to do next', (tester) async {
    final services = await quietServices();
    final state = AppState(
      services: services,
      store: InMemorySecureStore(),
    );
    await state.initialise();

    await tester.pumpWidget(wrap(const ChatsScreen(), state));
    await tester.pump();

    expect(find.text('No chats yet'), findsOneWidget);
    expect(find.text('Add a contact'), findsOneWidget);
  });

  testWidgets('the Unread filter hides conversations that are read', (tester) async {
    final services = await quietServices();
    final state = AppState(
      services: services,
      store: InMemorySecureStore(),
    );
    await state.initialise();

    for (final (id, name, mine) in [
      ('acc-alice', 'Alice', false),
      ('acc-charlie', 'Charlie', true),
    ]) {
      services.store.upsertUser(KnownUser(accountId: id, username: name.toLowerCase()));
      services.store.append(
        id,
        Message(id: '$id-1', body: 'hello', sentAt: DateTime.now(), isMine: mine),
      );
    }

    await tester.pumpWidget(wrap(const ChatsScreen(), state));
    await tester.pump();
    expect(find.text('charlie'), findsOneWidget);

    await tester.tap(find.text('Unread'));
    await tester.pump();

    expect(find.text('alice'), findsOneWidget, reason: 'incoming message is unread');
    expect(find.text('charlie'), findsNothing, reason: 'your own message is not unread');
  });

  testWidgets('outgoing bubbles sit right and carry read ticks', (tester) async {
    final message = Message(
      id: '1',
      body: 'Sealed before it leaves the device',
      sentAt: DateTime(2026, 1, 1, 12),
      isMine: true,
      state: DeliveryState.read,
    );

    await tester.pumpWidget(
      MaterialApp(theme: PrivioTheme.dark(), home: Scaffold(body: MessageBubble(message: message))),
    );

    final align = tester.widget<Align>(
      find
          .ancestor(
            of: find.text('Sealed before it leaves the device'),
            matching: find.byType(Align),
          )
          .first,
    );
    expect(align.alignment, Alignment.centerRight);

    final tick = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));
    expect(tick.color, PrivioColors.accentBright, reason: 'read receipts are accent green');
  });

  testWidgets('a message still in flight shows as sending, not delivered', (tester) async {
    final message = Message(
      id: '1',
      body: 'on its way',
      sentAt: DateTime(2026, 1, 1, 12),
      isMine: true,
      state: DeliveryState.sending,
    );

    await tester.pumpWidget(
      MaterialApp(theme: PrivioTheme.dark(), home: Scaffold(body: MessageBubble(message: message))),
    );

    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
  });

  testWidgets('a group row uses the group avatar', (tester) async {
    const chat = ChatSummary(
      id: 'g',
      title: 'Project X',
      preview: 'Bob: Document.pdf',
      timestamp: '10:45',
      isGroup: true,
    );
    await tester.pumpWidget(
      MaterialApp(theme: PrivioTheme.dark(), home: const Scaffold(body: ChatListRow(chat: chat))),
    );
    expect(find.byIcon(Icons.group_rounded), findsOneWidget);
  });
}
