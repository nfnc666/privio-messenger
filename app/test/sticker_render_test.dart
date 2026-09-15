import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/media/attachment.dart';
import 'package:privio/models/models.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/custom_emoji_text.dart';
import 'package:privio/widgets/message_bubble.dart';

/// What a reader sees when the pictures are not there.
///
/// Every test here runs **without** a `PrivioScope`, which is exactly the
/// situation a reader is in when they have no copy of a pack: there is nowhere
/// to fetch a picture from. The rule the whole design rests on is that this
/// still reads — so it is worth asserting rather than assuming.

const _ref = StickerRef(itemId: 'item-1', packId: 'pack-1', mediaId: 'media-1');

Widget _host(Widget child) => MaterialApp(
      theme: PrivioTheme.dark(),
      localizationsDelegates: AppText.localizationsDelegates,
      supportedLocales: AppText.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('a sticker with nowhere to fetch from shows its character', (tester) async {
    final message = Message(
      id: '1',
      body: '😺',
      kind: MessageKind.sticker,
      sticker: _ref,
      sentAt: DateTime(2026),
      isMine: false,
    );

    await tester.pumpWidget(_host(MessageBubble(message: message)));

    expect(find.text('😺'), findsOneWidget);
  });

  testWidgets('a sentence with custom emoji reads as a sentence', (tester) async {
    final message = Message(
      id: '1',
      body: 'hello 😺 there',
      sentAt: DateTime(2026),
      isMine: false,
      customEmoji: const [
        CustomEmojiRef(
          itemId: 'item-1',
          packId: 'pack-1',
          mediaId: 'media-1',
          offset: 6,
          length: 2,
        ),
      ],
    );

    await tester.pumpWidget(_host(MessageBubble(message: message)));

    // Not split into fragments, not showing a marker: the whole line.
    expect(find.text('hello 😺 there'), findsOneWidget);
  });

  testWidgets('a custom reaction falls back to its character', (tester) async {
    final message = Message(
      id: '1',
      body: 'hi',
      sentAt: DateTime(2026),
      isMine: false,
      reactions: const {'acc-alice': '😺'},
      reactionStickers: const {'acc-alice': _ref},
    );

    await tester.pumpWidget(_host(MessageBubble(message: message)));

    expect(find.text('😺'), findsOneWidget);
  });

  testWidgets('two people reacting with the same character are counted once',
      (tester) async {
    final message = Message(
      id: '1',
      body: 'hi',
      sentAt: DateTime(2026),
      isMine: false,
      reactions: const {'acc-a': '👍', 'acc-b': '👍'},
    );

    await tester.pumpWidget(_host(MessageBubble(message: message)));

    expect(find.text('👍'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('two custom emoji sharing a character are two chips', (tester) async {
    // The reason the chip is keyed by item and not by character: these are two
    // different pictures, and merging them would tell the reader that two
    // people did the same thing when they did not.
    const other = StickerRef(itemId: 'item-2', packId: 'pack-1', mediaId: 'media-2');
    final message = Message(
      id: '1',
      body: 'hi',
      sentAt: DateTime(2026),
      isMine: false,
      reactions: const {'acc-a': '😺', 'acc-b': '😺'},
      reactionStickers: const {'acc-a': _ref, 'acc-b': other},
    );

    await tester.pumpWidget(_host(MessageBubble(message: message)));

    expect(find.text('😺'), findsNWidgets(2));
    expect(find.text('2'), findsNothing, reason: 'they are not the same reaction');
  });

  testWidgets('CustomEmojiText with no controller is plain text', (tester) async {
    final message = Message(
      id: '1',
      body: 'a 😺 b',
      sentAt: DateTime(2026),
      isMine: false,
      customEmoji: const [
        CustomEmojiRef(
          itemId: 'i',
          packId: 'p',
          mediaId: 'm',
          offset: 2,
          length: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      _host(CustomEmojiText(message: message, controller: null)),
    );

    expect(find.text('a 😺 b'), findsOneWidget);
  });
}
