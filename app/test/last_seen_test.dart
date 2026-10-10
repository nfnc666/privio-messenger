import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/l10n/last_seen_text.dart';
import 'package:privio/models/last_seen.dart';
import 'package:privio/screens/contact_profile_screen.dart';
import 'package:privio/screens/contacts_screen.dart';

import 'widget_test.dart' show quietServices, wrap;

/// "Last seen", to the hour.
///
/// The server keeps activity to the hour now (migration 044) and reports the
/// start of the hour somebody was last active in. Shown to the minute, that
/// would read as "last seen at 14:00" for someone who was there at 14:59, and
/// "online" could only ever be a guess. So the app says it in hours, every
/// place it says it.
void main() {
  final now = DateTime(2026, 10, 10, 15, 20);

  group('how long ago, in the steps the server allows', () {
    LastSeen ago(Duration duration) => LastSeen.of(now.subtract(duration), now: now);

    test('unknown where they do not share it', () {
      expect(LastSeen.of(null, now: now).isUnknown, isTrue);
    });

    test('within the hour, never "online" and never minutes', () {
      for (final duration in const [
        Duration.zero,
        Duration(seconds: 30),
        Duration(minutes: 20),
        Duration(minutes: 59, seconds: 59),
      ]) {
        expect(ago(duration), const LastSeen.withinTheHour(), reason: '$duration');
      }
    });

    test('a clock a little behind the server is still within the hour', () {
      expect(LastSeen.of(now.add(const Duration(minutes: 10)), now: now), const LastSeen.withinTheHour());
    });

    test('then hours, days, and a date', () {
      expect(ago(const Duration(hours: 1)), const LastSeen.hours(1));
      expect(ago(const Duration(hours: 23, minutes: 59)), const LastSeen.hours(23));
      expect(ago(const Duration(days: 1)), const LastSeen.days(1));
      expect(ago(const Duration(days: 6)), const LastSeen.days(6));
      final old = now.subtract(const Duration(days: 40));
      expect(LastSeen.of(old, now: now), LastSeen.on(old));
    });
  });

  group('said the same way in every language', () {
    final minutes = RegExp(r'\d+\s*min', caseSensitive: false);

    for (final locale in AppText.supportedLocales) {
      test('${locale.languageCode}: within the hour, then hours', () async {
        final text = await AppText.delegate.load(locale);
        final recent = LastSeen.of(now.subtract(const Duration(minutes: 7)), now: now);
        final earlier = LastSeen.of(now.subtract(const Duration(hours: 5)), now: now);
        final device = now.subtract(const Duration(minutes: 7));

        expect(presenceText(text, recent), text.presenceWithinHour);
        expect(seenWhen(text, recent), text.contactsSeenWithinHour);
        expect(deviceActivityText(text, device, now: now), text.devicesActiveWithinHour);
        for (final words in [
          presenceText(text, recent),
          seenWhen(text, recent),
          deviceActivityText(text, device, now: now),
          presenceText(text, earlier),
          seenWhen(text, earlier),
        ]) {
          expect(words, isNotEmpty);
          expect(minutes.hasMatch(words), isFalse, reason: 'counts minutes: "$words"');
        }
        expect(seenWhen(text, earlier), text.contactsSeenHours(5));
        expect(presenceText(text, earlier), text.presenceHoursAgo(5));
      });
    }
  });

  test('a device is counted in days, not dated', () async {
    final text = await AppText.delegate.load(const Locale('en'));
    String active(Duration ago) => deviceActivityText(text, now.subtract(ago), now: now);

    expect(deviceActivityText(text, null, now: now), 'Signed in');
    expect(active(const Duration(minutes: 3)), 'Active within the last hour');
    expect(active(const Duration(hours: 4)), 'Active 4 h ago');
    expect(active(const Duration(days: 1, hours: 2)), 'Active yesterday');
    expect(active(const Duration(days: 12)), 'Active 12 days ago');
  });

  testWidgets('the contact list says it by the hour', (tester) async {
    // As the server now reports it: the start of the hour, in UTC.
    final hour = DateTime.now().toUtc();
    final thisHour = DateTime.utc(hour.year, hour.month, hour.day, hour.hour);
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'contacts': [
              {
                'id': 'acc-bob',
                'username': 'bob',
                'displayName': 'Bob',
                'lastSeenAt': thisHour.toIso8601String(),
              },
              {
                'id': 'acc-carol',
                'username': 'carol',
                'displayName': 'Carol',
                'lastSeenAt': thisHour.subtract(const Duration(hours: 3)).toIso8601String(),
              },
              {'id': 'acc-dan', 'username': 'dan', 'displayName': 'Dan', 'lastSeenAt': null},
            ],
            'envelopes': <Object>[],
            'more': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),);
    final state = AppState(services: await quietServices(client: client), store: InMemorySecureStore());
    await tester.runAsync(state.initialise);
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(wrap(const ContactsScreen(), state));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('@bob · last seen within the last hour'), findsOneWidget);
    expect(find.text('@carol · last seen 3 h ago'), findsOneWidget);
    expect(find.text('@dan'), findsOneWidget, reason: 'nothing at all where they do not share it');
    expect(find.textContaining('min ago'), findsNothing);
    expect(find.textContaining('just now'), findsNothing);
  });

  testWidgets('a profile says it by the hour too, not as a date and a minute', (tester) async {
    final hour = DateTime.now().toUtc();
    final thisHour = DateTime.utc(hour.year, hour.month, hour.day, hour.hour);
    final client = MockClient((request) async {
      final body = request.url.path == '/v1/users/id/acc-bob'
          ? {
              'id': 'acc-bob',
              'username': 'bob',
              'displayName': 'Bob',
              'isBlocked': false,
              'isContact': true,
              'status': {'text': null},
              'lastSeenAt': thisHour.subtract(const Duration(hours: 3)).toIso8601String(),
            }
          : {'contacts': <Object>[], 'envelopes': <Object>[], 'more': false};
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    final state = AppState(services: await quietServices(client: client), store: InMemorySecureStore());
    await tester.runAsync(state.initialise);
    addTearDown(state.conversations.stop);

    await tester.pumpWidget(wrap(const ContactProfileScreen(accountId: 'acc-bob'), state));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    expect(find.text('@bob · last seen 3 h ago'), findsOneWidget);
    expect(find.textContaining(':00'), findsNothing, reason: 'no time of day the server no longer knows');
  });
}
