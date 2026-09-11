import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/widgets/linked_text.dart';

/// The link runs in what [LinkedText] rendered, in order.
///
/// A run counts as a link when it carries a tap recognizer, which is the only
/// thing that makes it one: a coloured span nobody can tap would look like a
/// link and do nothing.
List<String> linksIn(WidgetTester tester) =>
    [for (final span in linkSpansIn(tester)) span.text ?? ''];

/// The spans themselves, for the test that needs the recognizer rather than
/// the words.
List<TextSpan> linkSpansIn(WidgetTester tester) {
  final found = <TextSpan>[];
  final text = tester.widget<Text>(find.byType(Text));
  text.textSpan?.visitChildren((span) {
    if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
      found.add(span);
    }
    return true;
  });
  return found;
}

Future<void> pumpText(WidgetTester tester, String text) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: LinkedText(text))),
    );

void main() {
  testWidgets('plain text stays plain', (tester) async {
    await pumpText(tester, 'Nothing to open here. Ends with a dot.');

    expect(linksIn(tester), isEmpty);
    expect(find.text('Nothing to open here. Ends with a dot.'), findsOneWidget);
  });

  testWidgets('an address is tappable and the sentence around it is not',
      (tester) async {
    await pumpText(tester, 'Read https://example.org/post today');

    expect(linksIn(tester), ['https://example.org/post']);
  });

  testWidgets('the full stop at the end of a sentence is not part of the link',
      (tester) async {
    // Otherwise every link that ends a sentence points one character past
    // where it says it does.
    await pumpText(tester, 'It is at https://example.org/a.');

    expect(linksIn(tester), ['https://example.org/a']);
  });

  testWidgets('a closing bracket that has an opening one stays in', (tester) async {
    await pumpText(tester, 'See https://example.org/Foo_(bar) for more');

    expect(linksIn(tester), ['https://example.org/Foo_(bar)']);
  });

  testWidgets('a bare www address counts', (tester) async {
    await pumpText(tester, 'try www.example.org now');

    expect(linksIn(tester), ['www.example.org']);
  });

  testWidgets('several in one post are separate links', (tester) async {
    await pumpText(tester, 'https://a.example http://b.example www.c.example');

    expect(
      linksIn(tester),
      ['https://a.example', 'http://b.example', 'www.c.example'],
    );
  });

  testWidgets('a word with a dot in it is not an address', (tester) async {
    // The detection is narrow on purpose. "file.txt" and "e.g." are not links,
    // and a rule loose enough to catch every real address catches these too.
    await pumpText(tester, 'Open file.txt, e.g. the one from Monday.');

    expect(linksIn(tester), isEmpty);
  });

  testWidgets('tapping asks before it opens anything', (tester) async {
    await pumpText(tester, 'Go to https://example.org/somewhere');

    // Reach the recognizer the way a tap does, rather than hit-testing a span:
    // what matters here is that it leads to the confirmation, not to a launch.
    final spans = linkSpansIn(tester);
    expect(spans, hasLength(1), reason: 'the address is tappable');

    (spans.single.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    expect(find.text('Open this link?'), findsOneWidget);
    expect(find.text('example.org'), findsOneWidget, reason: 'the host is named');
    expect(
      find.text('https://example.org/somewhere'),
      findsOneWidget,
      reason: 'and so is the whole address',
    );
  });
}
