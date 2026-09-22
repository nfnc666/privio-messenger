import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/account_phone_controller.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/privio_services.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/phone_field.dart';
import 'package:privio/screens/account_phone_screen.dart';

import 'widget_test.dart' show quietServices, wrap;

class NoteServer {
  final notes = <String, String?>{};
  final requests = <http.Request>[];
  Completer<void>? gate;
  bool fail = false;
  late final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: MockClient((request) async {
    requests.add(request);
    final token = request.headers['authorization']!;
    final pending = gate;
    if (pending != null) await pending.future;
    if (fail) return http.Response('{"error":"offline"}', 503);
    if (request.method == 'PUT') notes[token] = (jsonDecode(request.body) as Map<String, dynamic>)['phoneNumber'] as String?;
    if (request.method == 'DELETE') notes.remove(token);
    return http.Response(jsonEncode({'phoneNumber': notes[token], 'verified': false, 'usedForDiscovery': false, 'hasVerifiedNumber': true}), 200);
  }),)..useToken('alice');
}

void main() {
  testWidgets('account editor saves, shows unverified state and removes without SMS', (tester) async {
    final server = NoteServer();
    final quiet = await quietServices();
    final services = PrivioServices(
      api: server.api, crypto: quiet.crypto, messaging: quiet.messaging, channels: quiet.channels,
      recorder: quiet.recorder, player: quiet.player, backup: quiet.backup,
      store: quiet.store, secureStore: quiet.secureStore,
    );
    final state = AppState(services: services, store: InMemorySecureStore());
    await state.initialise();
    addTearDown(state.dispose);
    await tester.pumpWidget(wrap(const AccountPhoneScreen(), state));
    await tester.pumpAndSettle();
    expect(find.text('Optional information. Your phone number is not verified and is not used for automatic contact discovery.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '+41 79 123 45 67');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(server.notes['Bearer alice'], '+41791234567');
    expect(find.text('Unverified — not proof of identity'), findsOneWidget);
    final text = AppText.of(tester.element(find.byType(AccountPhoneScreen)));
    await tester.tap(find.widgetWithText(TextButton, text.phoneRemove));
    await tester.pumpAndSettle();
    expect(server.notes['Bearer alice'], isNull);
    expect(find.text('Unverified — not proof of identity'), findsNothing);
    // Every phone request, and nothing else: `/v1/server` is the launch probe
    // that asks whether this build needs a key, which happens before any screen
    // and is not a phone route. What this guards is that the editor never
    // reaches for the SMS verification or discovery endpoints — those are under
    // `/v1/phone`, and one appearing here turns this red.
    expect(
      server.requests
          .where((r) => r.url.path != '/v1/server')
          .every((r) => r.url.path == '/v1/accounts/me/phone-note'),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('save/change/reload/remove uses only the private annotation endpoint', () async {
    final server = NoteServer();
    final first = AccountPhoneController(server.api);
    await first.load();
    expect(first.number, isNull);
    expect(await first.save('0041 79 123 45 67'), isTrue);
    expect(first.number, '+41791234567');
    expect(first.hasVerifiedNumber, isTrue);
    expect(await first.save('+447911123456'), isTrue);
    first.dispose();
    final restarted = AccountPhoneController(server.api);
    await restarted.load();
    expect(restarted.number, '+447911123456');
    expect(await restarted.remove(), isTrue);
    expect(restarted.number, isNull);
    expect(server.requests.every((r) => r.url.path == '/v1/accounts/me/phone-note'), isTrue);
    restarted.dispose();
  });

  test('invalid input does not send a request; empty input removes', () async {
    final server = NoteServer();
    final controller = AccountPhoneController(server.api);
    expect(await controller.save('not a phone'), isFalse);
    expect(server.requests, isEmpty);
    await controller.save('+41791234567');
    await controller.save(' ');
    expect(controller.number, isNull);
    controller.dispose();
  });

  test('failed save keeps the confirmed value and reports no success', () async {
    final server = NoteServer();
    final controller = AccountPhoneController(server.api);
    await controller.save('+41791234567');
    server.fail = true;
    expect(await controller.save('+447911123456'), isFalse);
    expect(controller.failed, isTrue);
    expect(controller.number, '+41791234567');
    controller.dispose();
  });

  test('account switch drops pending responses, cached number and old-route writes', () async {
    final server = NoteServer();
    final alice = AccountPhoneController(server.api);
    await alice.save('+41791234567');
    server.gate = Completer<void>();
    final pending = alice.load();
    server.api.useToken('bob');
    server.gate!.complete();
    await pending;
    expect(alice.number, isNull);
    final count = server.requests.length;
    expect(await alice.remove(), isFalse);
    expect(server.requests.length, count);
    server.gate = null;
    final bob = AccountPhoneController(server.api);
    await bob.load();
    expect(bob.number, isNull);
    await bob.save('+447911123456');
    expect(server.notes['Bearer alice'], '+41791234567');
    alice.dispose(); bob.dispose();
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('phone field restores calling code and accepts international paste on $platform', (tester) async {
      final input = TextEditingController();
      final key = GlobalKey<PhoneFieldState>();
      await tester.pumpWidget(MaterialApp(
        theme: PrivioTheme.dark().copyWith(platform: platform),
        localizationsDelegates: AppText.localizationsDelegates, supportedLocales: AppText.supportedLocales,
        home: Scaffold(body: PhoneField(key: key, controller: input, initialNumber: '+41791234567')),
      ),);
      expect(input.text, '791234567');
      expect(find.textContaining('+41'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).keyboardType, TextInputType.phone);
      await tester.enterText(find.byType(TextField), '+44 7911 123456');
      expect(key.currentState!.value!.e164, '+447911123456');
      await tester.pumpWidget(const SizedBox.shrink());
      input.dispose();
    });
  }
}
