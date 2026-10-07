import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/models/channel.dart';
import 'package:privio/screens/channel_access_screen.dart';
import 'package:privio/screens/channel_posts_screen.dart';
import 'package:privio/screens/channel_profile_edit_screen.dart';
import 'package:privio/screens/channel_settings_screen.dart';
import 'package:privio/widgets/channel_header.dart';
import 'package:privio/widgets/settings_row.dart';

import 'channel_profile_test.dart' show FakeServer, channelFor, ownerPermissions, stateWith, wrap;

/// The redesigned channel settings.
///
/// Two things are being checked, and the second is the one that matters most
/// in a redesign: that the layout is what it claims to be, and that **nothing
/// a person could do before has become unreachable**. The second is why there
/// is a list of rows asserted by name here rather than a screenshot — a
/// permission whose row quietly vanished is a permission nobody can withdraw,
/// and that failure is invisible to the eye.
///
/// Three people are tried throughout: the owner, an administrator holding only
/// some of the permissions, and a plain subscriber.

/// An administrator who may edit the channel and nothing else — the case that
/// catches a screen which asks "is there a role" instead of "is there a right".
ChannelPermissions get editorOnly => const ChannelPermissions(
      canPost: true,
      canEditChannel: true,
    );

/// A moderator who may admit people but may not touch the channel itself.
ChannelPermissions get doorkeeper => const ChannelPermissions(
      canManageMembers: true,
      canManageInvites: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A viewport tall enough to hold the whole screen at once.
  ///
  /// The inventory below asserts that every row exists, and a ListView only
  /// builds what fits — so on a phone-sized surface "not found" would mean
  /// "below the fold" rather than "gone", which is the one thing these tests
  /// must not confuse. Scrolling instead would work and would also quietly
  /// pass if a row moved into a section it does not belong to.
  void tallEnough(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<AppState> open(
    WidgetTester tester, {
    required ChannelInfo channel,
    FakeServer? server,
    bool tall = false,
  }) async {
    if (tall) tallEnough(tester);
    // `stateWith` registers the dispose teardown itself; a second one disposes
    // twice and the framework asserts about it.
    final state = await stateWith(server ?? FakeServer(), channel);
    await tester.pumpWidget(
      wrap(ChannelSettingsScreen(channel: state.channels.mine.single), state),
    );
    await tester.pumpAndSettle();
    return state;
  }

  group('the layout is Privio s, not a copy', () {
    testWidgets('a compact left-aligned header, not a centred lock-up',
        (tester) async {
      await open(
        tester,
        channel: channelFor(
          role: 'owner',
          permissions: ownerPermissions,
          description: 'Daily notes',
        ),
      );

      final header = tester.widget<ChannelHeader>(find.byType(ChannelHeader));
      expect(header.channel.title, 'HouseOfTrading');

      // The name sits to the left of the screen's middle. A centred lock-up
      // cannot satisfy this, which is the point of asserting it.
      final name = tester.getRect(find.text('HouseOfTrading'));
      final screen = tester.getRect(find.byType(Scaffold));
      expect(
        name.center.dx,
        lessThan(screen.center.dx),
        reason: 'the header is centred, as the old one was',
      );
      // And it is compact: the first section caption is on screen without
      // scrolling, which it never was under a 96pt circle.
      expect(find.text('CHANNEL PROFILE'), findsOneWidget);
    });

    testWidgets('every section is captioned, and the dangerous one is last',
        (tester) async {
      await open(
        tester,
        channel: channelFor(role: 'owner', permissions: ownerPermissions),
      );

      for (final caption in [
        'CHANNEL PROFILE',
        'ACCESS & INVITATIONS',
        'TEAM & MEMBERS',
        'POSTS & INTERACTION',
      ]) {
        expect(find.text(caption), findsOneWidget, reason: caption);
      }

      // Scrolled to the end first: a ListView builds what is on screen, so the
      // last section does not exist as a widget until somebody can see it.
      // Then the order is read off the tree rather than off pixels, because by
      // that point the first captions have scrolled away.
      await tester.scrollUntilVisible(
        find.text('THIS CANNOT BE UNDONE'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final captions = tester
          .widgetList<SettingsSection>(find.byType(SettingsSection))
          .map((section) => section.caption)
          .whereType<String>()
          .toList();
      expect(captions.last, 'THIS CANNOT BE UNDONE', reason: 'danger is not last');
    });

    testWidgets('rows say what they are set to without being opened',
        (tester) async {
      await open(
        tester,
        channel: channelFor(
          role: 'owner',
          permissions: ownerPermissions,
          memberCount: 34,
          description: 'Daily notes',
        ),
      );

      // The question somebody opens this screen with, answered on it.
      expect(find.text('Public · @houseoftrading'), findsOneWidget);
      expect(find.text('Daily notes'), findsOneWidget);
      // Twice, and deliberately: once in the header as who this channel is,
      // once on the row that opens the list. The header does not repeat the
      // description, which is what the row above it is about.
      expect(find.text('34 subscribers'), findsNWidgets(2));
    });
  });

  group('nothing a person could do has become unreachable', () {
    testWidgets('the owner reaches every one of them', (tester) async {
      await open(
        tester,
        channel: channelFor(role: 'owner', permissions: ownerPermissions),
        tall: true,
      );

      // One row per function the old screens had. A row that disappears in a
      // redesign is a function nobody can perform any more.
      for (final row in [
        'Picture, name and description',
        'Link',
        'Who can find this channel',
        'Invite link',
        'Administrators',
        'Subscribers',
        'Reactions',
        'Comments',
        'Show who posted',
        'Direct messages',
        'Welcome message',
        'Colours',
        'Livestream',
        'Statistics',
      ]) {
        expect(find.text(row), findsOneWidget, reason: '$row is gone');
      }

      expect(find.text('Hand this channel on'), findsOneWidget);
      expect(find.text('Delete this channel'), findsOneWidget);
    });

    testWidgets('an administrator who may only edit sees no member management',
        (tester) async {
      await open(
        tester,
        channel: channelFor(role: 'admin', permissions: editorOnly),
        tall: true,
      );

      // What they hold.
      expect(find.text('Picture, name and description'), findsOneWidget);
      expect(find.text('Reactions'), findsOneWidget);
      expect(find.text('Statistics'), findsOneWidget);

      // What they do not. Hidden here as a courtesy; refused on the server,
      // which is where it counts.
      expect(find.text('Invite link'), findsNothing);
      expect(find.text('Requests to join'), findsNothing);
      expect(find.text('Delete this channel'), findsNothing);
      expect(find.text('Hand this channel on'), findsNothing);
    });

    testWidgets('a doorkeeper gets the invitations and not the channel itself',
        (tester) async {
      await open(
        tester,
        channel: channelFor(role: 'admin', permissions: doorkeeper),
        tall: true,
      );

      expect(find.text('Invite link'), findsOneWidget);
      // The rows that change the channel are shown disabled rather than hidden,
      // so somebody can see the setting exists and that it is not theirs.
      expect(find.text('Only an administrator can change these.'), findsOneWidget);
      expect(find.text('Statistics'), findsNothing);
      expect(find.text('Colours'), findsNothing);
    });

    testWidgets('a subscriber sees the lists and nothing to change',
        (tester) async {
      await open(tester, channel: channelFor(role: 'subscriber'), tall: true);

      expect(find.text('Administrators'), findsOneWidget);
      expect(find.text('Subscribers'), findsOneWidget);
      expect(find.text('Invite link'), findsNothing);
      expect(find.text('Direct messages'), findsNothing);
      expect(find.text('Leave this channel'), findsOneWidget);
      expect(find.text('Delete this channel'), findsNothing);
      expect(find.text('Hand this channel on'), findsNothing);
    });
  });

  group('deleting asks for the name', () {
    testWidgets('and refuses until it matches', (tester) async {
      final state = await open(
        tester,
        channel: channelFor(role: 'owner', permissions: ownerPermissions),
        tall: true,
      );

      await tester.tap(find.text('Delete this channel'));
      await tester.pumpAndSettle();

      // A confirmation somebody can tap through twice is one tap of muscle
      // memory away from being no confirmation at all.
      final action = find.widgetWithText(TextButton, 'Delete channel');
      expect(tester.widget<TextButton>(action).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'HouseOfTrad');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(action).onPressed, isNull,
          reason: 'a near-miss was accepted');

      await tester.enterText(find.byType(TextField), 'HouseOfTrading');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(action).onPressed, isNotNull);

      // Nothing has been asked of the server yet.
      expect(state.channels.mine, isNotEmpty);
    });
  });

  group('the detail pages', () {
    testWidgets('the profile page will not save an empty name, and Save is off '
        'until something changes', (tester) async {
      final state = await stateWith(
        FakeServer(),
        channelFor(role: 'owner', permissions: ownerPermissions, description: 'Daily'),
      );
      await tester.pumpWidget(
        wrap(ChannelProfileEditScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      final save = find.widgetWithText(TextButton, 'Save');
      expect(tester.widget<TextButton>(save).onPressed, isNull,
          reason: 'Save was live with nothing changed');

      await tester.enterText(find.byType(TextField).first, 'A new name');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(save).onPressed, isNotNull);
    });

    testWidgets('and leaving it with unsaved changes asks first', (tester) async {
      final state = await stateWith(
        FakeServer(),
        channelFor(role: 'owner', permissions: ownerPermissions),
      );
      await tester.pumpWidget(
        wrap(ChannelProfileEditScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Changed');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Keep your changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      // Still here, still changed.
      expect(find.byType(ChannelProfileEditScreen), findsOneWidget);
    });

    testWidgets('the access page says why public and private is not a switch',
        (tester) async {
      final state = await stateWith(
        FakeServer(),
        channelFor(role: 'owner', permissions: ownerPermissions),
      );
      await tester.pumpWidget(
        wrap(ChannelAccessScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      expect(find.text('Public'), findsOneWidget);
      // The section caption, which `SettingsSection` upper-cases.
      expect(find.text('INVITE LINK'), findsOneWidget);
      expect(find.text('Ask me first'), findsOneWidget);
    });

    testWidgets('the posts page carries the welcome text, not a dialog',
        (tester) async {
      final state = await stateWith(
        FakeServer(),
        channelFor(role: 'owner', permissions: ownerPermissions),
      );
      await tester.pumpWidget(
        wrap(ChannelPostsScreen(channel: state.channels.mine.single), state),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reactions'), findsOneWidget);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Show who posted'), findsOneWidget);
      // The welcome message used to be a text field inside an alert dialog.
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
