import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/settings_row.dart';

/// A settings row keeps its label whole at large text.
///
/// Seen at the largest text size in German: "Telefonnummer hinzufügen" next to
/// "Keine Nummer verknüpft" broke as "Telefonnumm" / "er hinzufügen", because
/// label and value each had half the row.
void main() {
  // The app's own font, so widths are a phone's widths. The test font draws
  // every glyph as wide as it is tall and would fail any word.
  setUpAll(() async {
    final loader = FontLoader('Privio');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      final bytes = File('assets/fonts/Roboto-$weight.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  testWidgets('a long word in the label is not broken to make room for the value',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(),
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.3,
          maxScaleFactor: 1.3,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SettingsRow(
                icon: Icons.phone_outlined,
                label: 'Telefonnummer hinzufügen',
                value: 'Keine Nummer verknüpft',
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    // The longest word of the label fits on one line of the label's column:
    // laid out on its own at the same style, it is no wider than the column.
    final label = find.text('Telefonnummer hinzufügen');
    final column = tester.getSize(label).width;
    final style = tester.widget<Text>(label).style;
    final word = TextPainter(
      text: TextSpan(text: 'Telefonnummer', style: style),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(1.3),
    )..layout();
    expect(word.width, lessThanOrEqualTo(column), reason: 'the word was broken');
    word.dispose();
  });
}
