import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/contact_profile_controller.dart';
import 'package:privio/data/message_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/models/models.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/avatar.dart';
import 'package:privio/widgets/message_bubble.dart';

Map<String, dynamic> profile({String id = 'peer'}) => {
  'id': id, 'username': 'same-name', 'displayName': 'Same Name',
  'isBlocked': true, 'isContact': false,
  'status': {'text': null}, 'lastSeenAt': null,
  'phoneNumber': 'must-not-be-used',
};

void main() {
  test('loads the immutable ID, preserves hidden fields and blocked state', () async {
    final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: MockClient((request) async {
      expect(request.url.path, '/v1/users/id/peer');
      return http.Response(jsonEncode(profile()), 200);
    }),)..useToken('a');
    final controller = ContactProfileController(api, 'peer');
    await controller.load();
    expect(controller.profile!.id, 'peer');
    expect(controller.profile!.isBlocked, isTrue);
    expect(controller.profile!.status.isSet, isFalse);
    expect(controller.profile!.lastSeenAt, isNull);
    controller.dispose();
  });

  test('rejects a response for another user', () async {
    final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: MockClient((_) async =>
      http.Response(jsonEncode(profile(id: 'wrong')), 200),),)..useToken('a');
    final controller = ContactProfileController(api, 'peer');
    await controller.load();
    expect(controller.failed, isTrue);
    expect(controller.profile, isNull);
    controller.dispose();
  });

  for (final code in [404, 503]) {
    test('handles HTTP $code without a stale profile', () async {
      final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: MockClient((_) async =>
        http.Response('{"error":"unavailable","message":"Unavailable"}', code),),)..useToken('a');
      final controller = ContactProfileController(api, 'peer');
      await controller.load();
      expect(controller.missing, code == 404);
      expect(controller.failed, code != 404);
      expect(controller.profile, isNull);
      controller.dispose();
    });
  }

  test('account switch discards an in-flight profile and refuses later actions', () async {
    final gate = Completer<void>();
    final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: MockClient((_) async {
      await gate.future;
      return http.Response(jsonEncode(profile()), 200);
    }),)..useToken('a');
    final controller = ContactProfileController(api, 'peer');
    final loading = controller.load();
    api.useToken('b');
    gate.complete();
    await loading;
    expect(controller.profile, isNull);
    expect(await controller.change(() async => fail('Old route must not write')), isFalse);
    controller.dispose();
  });

  test('adding and removing use IDs, not display names', () async {
    final seen = <http.Request>[];
    final api = PrivioApiClient(baseUrl: Uri.parse('https://api.test'), client: MockClient((request) async {
      seen.add(request);
      return http.Response('{}', 200);
    }),)..useToken('a');
    await api.addContactById('peer');
    await api.removeContact('peer');
    expect(jsonDecode(seen.first.body), {'accountId': 'peer'});
    expect(seen.last.method, 'DELETE');
    expect(seen.last.url.path, '/v1/contacts/peer');
  });

  test('opening a known ID keeps its messages instead of duplicating the conversation', () {
    final store = InMemoryMessageStore();
    store.upsertUser(const KnownUser(accountId: 'peer', username: 'old'));
    store.append('peer', Message(id: 'message', body: 'Kept', sentAt: DateTime(2026), isMine: false));
    store.upsertUser(const KnownUser(accountId: 'peer', username: 'new'));
    expect(store.conversations(), hasLength(1));
    expect(store.conversationWith('peer')!.messages.single.body, 'Kept');
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('group sender name and avatar are tappable on $platform', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: PrivioTheme.dark().copyWith(platform: platform),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Scaffold(body: MessageBubble(
          message: Message(id: 'm', body: 'Hello', sentAt: DateTime(2026), isMine: false, senderName: 'Sender', senderAccountId: 'peer'),
          onSenderTap: () => taps++,
        ),),
      ),);
      await tester.tap(find.text('Sender'));
      await tester.tap(find.byType(PrivioAvatar));
      expect(taps, 2);
    });
  }
}
