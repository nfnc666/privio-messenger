import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/biometric_gate.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/crypto/crypto_storage.dart';
import 'package:privio/crypto/privio_crypto.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chats_screen.dart';
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

Widget wrap(Widget child, AppState state) => MaterialApp(
      theme: PrivioTheme.dark(),
      home: PrivioScope(notifier: state, child: child),
    );

void main() {
  testWidgets('the chat list shows decrypted conversations', (tester) async {
    final services = await quietServices();
    final state = AppState(
      services: services,
      store: InMemorySecureStore(),
      biometrics: const NoBiometrics(),
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
      biometrics: const NoBiometrics(),
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
      biometrics: const NoBiometrics(),
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
