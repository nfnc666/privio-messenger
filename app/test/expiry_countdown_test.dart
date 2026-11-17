import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/models/models.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/disappearing_timer_sheet.dart';
import 'package:privio/widgets/message_bubble.dart';

/// How long a message under a timer has left, where its time is.
///
/// The bubble showed a clock and nothing else: a reader could see that a
/// message would go, not when.
void main() {
  group('what the label says', () {
    late AppText text;
    setUpAll(() async => text = await AppText.delegate.load(const Locale('en')));

    String said(Duration left) => DisappearingTimerSheet.remaining(text, left).label;

    test('a day-long timer just after sending reads its full length', () {
      expect(said(const Duration(hours: 24) - const Duration(milliseconds: 1)), '24h');
      expect(said(const Duration(minutes: 30)), '30m');
      expect(said(const Duration(seconds: 30)), '30s');
    });

    test('rounded up, so a message never outlives what its label said', () {
      expect(said(const Duration(minutes: 1, seconds: 1)), '2m');
      expect(said(const Duration(hours: 2, minutes: 1)), '3h');
      expect(said(const Duration(milliseconds: 1)), '1s');
      // Across a day: what the label promises is never less than what is
      // left, and never as much as an hour more.
      for (var s = 1; s <= 24 * 3600; s += 7) {
        final left = Duration(seconds: s);
        final shown = DisappearingTimerSheet.remaining(text, left);
        expect(shown.exact, greaterThanOrEqualTo(left), reason: '$left read ${shown.label}');
        expect(shown.exact - left, lessThan(const Duration(hours: 1)), reason: '$left read ${shown.label}');
      }
    });

    test('a little over a day is hours, not "2 days"', () {
      expect(said(const Duration(hours: 25)), '25h');
      expect(said(const Duration(days: 7) - const Duration(seconds: 1)), '7d');
    });

    test('nothing left is nothing left, with nothing to count down to', () {
      final gone = DisappearingTimerSheet.remaining(text, Duration.zero);
      expect(gone.label, '0s');
      expect(gone.changesIn, isNull);
      expect(DisappearingTimerSheet.remaining(text, const Duration(seconds: -3)).label, '0s');
    });

    test('it says when it will next read differently, and then it does', () {
      for (final left in const [
        Duration(hours: 24),
        Duration(hours: 2, minutes: 1),
        Duration(minutes: 1, seconds: 1),
        Duration(seconds: 5, milliseconds: 500),
      ]) {
        final now = DisappearingTimerSheet.remaining(text, left);
        final wait = now.changesIn!;
        expect(wait, greaterThan(Duration.zero));
        final justBefore = DisappearingTimerSheet.remaining(text, left - wait + const Duration(microseconds: 1));
        final after = DisappearingTimerSheet.remaining(text, left - wait);
        expect(justBefore.label, now.label, reason: 'unchanged until then: $left');
        expect(after.label, isNot(now.label), reason: 'changed at it: $left');
      }
    });
  });

  testWidgets('the bubble counts down beside its time, in the reader\'s language',
      (tester) async {
    Future<void> show(Locale locale, Message message) => tester.pumpWidget(
          MaterialApp(
            theme: PrivioTheme.dark(),
            locale: locale,
            localizationsDelegates: AppText.localizationsDelegates,
            supportedLocales: AppText.supportedLocales,
            home: Scaffold(body: MessageBubble(message: message)),
          ),
        );
    final sent = clock.now();
    final message = Message(
      id: 'm1',
      body: 'PrivioNews um neun',
      sentAt: sent,
      isMine: false,
      expiresAt: sent.add(const Duration(hours: 2, minutes: 30)),
    );

    await show(const Locale('de'), message);
    expect(find.text('3 Std'), findsOneWidget);
    expect(find.bySemanticsLabel('Noch 3 Stunden sichtbar'), findsOneWidget);

    // Half an hour later, without anything else happening on screen.
    await tester.pump(const Duration(minutes: 30));
    expect(find.text('2 Std'), findsOneWidget);

    await tester.pump(const Duration(hours: 1, minutes: 59));
    expect(find.text('60 Sek'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('45 Sek'), findsOneWidget);

    await show(const Locale('fr'), message);
    expect(find.text('45 s'), findsOneWidget);
    expect(find.bySemanticsLabel('Disparaît dans 45 secondes'), findsOneWidget);
  });

  testWidgets('a message with no timer has no countdown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Scaffold(
          body: MessageBubble(
            message: Message(id: 'm2', body: 'PrivioNews', sentAt: clock.now(), isMine: true),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
  });
}
