import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/models/channel.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/verified_badge.dart';

/// The blue mark, and the one rule that matters about it: **the client cannot
/// turn it on.** It is drawn from a field the server sets by comparing channel
/// ids, so a look-alike arrives here unverified and stays that way.

Widget _host(Widget child) => MaterialApp(
      theme: PrivioTheme.dark(),
      localizationsDelegates: AppText.localizationsDelegates,
      supportedLocales: AppText.supportedLocales,
      home: Scaffold(body: child),
    );

ChannelInfo _channel({required String title, required bool verified}) => ChannelInfo(
      id: 'channel-1',
      visibility: ChannelVisibility.public,
      title: title,
      verified: verified,
    );

void main() {
  testWidgets('a verified channel shows the mark after its name', (tester) async {
    await tester.pumpWidget(
      _host(const ChannelName(name: 'Privio Official', verified: true)),
    );

    expect(find.text('Privio Official'), findsOneWidget);
    expect(find.byType(VerifiedBadge), findsOneWidget);
  });

  testWidgets('a channel with the same name and no designation shows nothing',
      (tester) async {
    // The impostor case, at the widget level: identical title, no badge.
    await tester.pumpWidget(
      _host(const ChannelName(name: 'Privio Official', verified: false)),
    );

    expect(find.text('Privio Official'), findsOneWidget);
    expect(find.byType(VerifiedBadge), findsNothing);
  });

  testWidgets('the flag comes from the server, and defaults to off', (tester) async {
    // A response from a server that predates the field, or a cached channel
    // written before it — unverified, rather than accidentally verified.
    const fromOldServer = ChannelInfo(
      id: 'channel-1',
      visibility: ChannelVisibility.public,
      title: 'Privio Official',
    );
    expect(fromOldServer.verified, isFalse);

    await tester.pumpWidget(
      _host(ChannelName(name: fromOldServer.title, verified: fromOldServer.verified)),
    );
    expect(find.byType(VerifiedBadge), findsNothing);
  });

  testWidgets('the mark is blue, and not the account s accent', (tester) async {
    // A badge drawn in the accent would be a different colour on every phone
    // and would mean nothing consistent.
    await tester.pumpWidget(_host(const VerifiedBadge()));

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, VerifiedBadge.blue);
  });

  testWidgets('a long name shortens rather than pushing the mark off the edge',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 120,
          child: ChannelName(
            name: 'A channel with a very long name indeed that will not fit',
            verified: true,
          ),
        ),
      ),
    );

    // Both are present and laid out: the badge is not clipped away.
    expect(find.byType(VerifiedBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('ChannelInfo carries the flag through a copy', () {
    final verified = _channel(title: 'Privio Official', verified: true);
    expect(verified.copyWith(title: 'Renamed').verified, isTrue);

    final plain = _channel(title: 'Something Else', verified: false);
    expect(plain.copyWith(title: 'Privio Official').verified, isFalse,
        reason: 'renaming a channel must not earn it the badge');
  });
}
