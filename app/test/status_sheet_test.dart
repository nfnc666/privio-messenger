import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/status_controller.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/theme/accent.dart';
import 'package:privio/theme/privio_theme.dart';
import 'package:privio/widgets/status_sheet.dart';

/// The sheet on its own, over a controller pointed at a scripted server.
class _Server {
  Map<String, dynamic>? stored;
  int failuresToServe = 0;
  Completer<void>? gate;
  int writes = 0;

  PrivioApiClient client() => PrivioApiClient(
        baseUrl: Uri.parse('https://api.test'),
        client: MockClient((request) async {
          final pending = gate;
          if (pending != null) await pending.future;
          if (failuresToServe > 0) {
            failuresToServe -= 1;
            throw http.ClientException('offline');
          }
          if (request.method == 'PUT' && request.url.path == '/v1/accounts/me/status') {
            writes += 1;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final text = (body['text'] as String?)?.trim();
            stored = text == null || text.isEmpty
                ? null
                : {
                    'text': text,
                    'emoji': body['emoji'],
                    'expiresAt': body['expiresAt'],
                    'updatedAt': null,
                  };
            return _json({'status': stored ?? _none});
          }
          if (request.method == 'DELETE' && request.url.path == '/v1/accounts/me/status') {
            writes += 1;
            stored = null;
            return _json({'status': _none});
          }
          return http.Response('{}', 404);
        }),
      )..useToken('token');

  static const Map<String, dynamic> _none = {
    'text': null,
    'emoji': null,
    'expiresAt': null,
    'updatedAt': null,
  };

  static http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
}

/// A screen with one button that opens the sheet, which is how it is reached in
/// the app — a sheet tested outside a Navigator cannot be dismissed.
Widget _host(StatusController controller) => MaterialApp(
      theme: PrivioTheme.dark(),
      localizationsDelegates: AppText.localizationsDelegates,
      supportedLocales: AppText.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showStatusSheet(context, controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, StatusController controller) async {
  await tester.pumpWidget(_host(controller));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens with the current status loaded for editing', (tester) async {
    final server = _Server();
    final controller = StatusController(server.client())
      ..adopt('account-a', {
        'text': 'Writing tests',
        'emoji': '💻',
        'expiresAt': null,
        'updatedAt': null,
      });

    await _open(tester, controller);

    // The existing line is in the field, not an empty box somebody would
    // overwrite by accident.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Writing tests');
  });

  testWidgets('opens empty when there is no status', (tester) async {
    final server = _Server();
    final controller = StatusController(server.client())..adopt('account-a', null);

    await _open(tester, controller);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '');
    // Nothing to remove, so no Remove button.
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('cancel discards the draft and writes nothing', (tester) async {
    final server = _Server();
    final controller = StatusController(server.client())
      ..adopt('account-a', {
        'text': 'Original',
        'emoji': null,
        'expiresAt': null,
        'updatedAt': null,
      });

    await _open(tester, controller);
    await tester.enterText(find.byType(TextField), 'Something else entirely');
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing, reason: 'the sheet should be gone');
    expect(server.writes, 0, reason: 'cancel must not reach the server');
    expect(controller.status.text, 'Original');

    // And reopening shows the stored value, not the abandoned draft.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Original');
  });

  testWidgets('save stores it and closes', (tester) async {
    final server = _Server();
    final controller = StatusController(server.client())..adopt('account-a', null);

    await _open(tester, controller);
    await tester.enterText(find.byType(TextField), 'On a break');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(controller.status.text, 'On a break');
    expect(server.stored!['text'], 'On a break');
  });

  testWidgets('a chosen emoji rides along', (tester) async {
    final server = _Server();
    final controller = StatusController(server.client())..adopt('account-a', null);

    await _open(tester, controller);
    await tester.enterText(find.byType(TextField), 'Listening');
    await tester.tap(find.text('🎧'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(server.stored!['emoji'], '🎧');
  });

  testWidgets('remove clears it', (tester) async {
    final server = _Server()..stored = {'text': 'Here'};
    final controller = StatusController(server.client())
      ..adopt('account-a', {'text': 'Here', 'emoji': null, 'expiresAt': null, 'updatedAt': null});

    await _open(tester, controller);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(controller.status.isSet, isFalse);
    expect(server.stored, isNull);
  });

  testWidgets('shows a spinner while saving and takes only one tap', (tester) async {
    final server = _Server()..gate = Completer<void>();
    final controller = StatusController(server.client())..adopt('account-a', null);

    await _open(tester, controller);
    await tester.enterText(find.byType(TextField), 'Slowly');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();

    // The button is a spinner, and the label it had is gone — so there is
    // nothing left to tap twice.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    server.gate!.complete();
    await tester.pumpAndSettle();
    expect(server.writes, 1);
  });

  testWidgets('a failure keeps the sheet open with the draft and an explanation', (tester) async {
    final server = _Server()..failuresToServe = 1;
    final controller = StatusController(server.client())..adopt('account-a', null);

    await _open(tester, controller);
    await tester.enterText(find.byType(TextField), 'Worth keeping');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Still open.
    expect(find.byType(TextField), findsOneWidget);
    // The draft is still in the field — nothing to retype.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Worth keeping');
    // And it says so, rather than closing as if it had worked.
    expect(find.textContaining('was not saved'), findsOneWidget);

    // The retry works, from the same draft.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(controller.status.text, 'Worth keeping');
  });

  testWidgets('the accent colour reaches the sheet', (tester) async {
    final server = _Server();
    final controller = StatusController(server.client())..adopt('account-a', null);

    await tester.pumpWidget(
      MaterialApp(
        theme: PrivioTheme.dark(accent: AppAccent.purple),
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showStatusSheet(context, controller),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The selected emoji wears the accent, so picking one proves the sheet
    // reads the theme rather than a hardcoded green.
    await tester.tap(find.text('☕'));
    await tester.pump();

    final expected = PrivioAccents.of(AppAccent.purple).accent;
    final tiles = tester.widgetList<Container>(find.byType(Container));
    final borders = tiles
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.border)
        .whereType<Border>()
        .map((b) => b.top.color);
    expect(borders, contains(expected));
  });

  testWidgets('every duration the sheet offers has a word in every language', (tester) async {
    for (final locale in AppText.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: PrivioTheme.dark(),
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: Builder(
            builder: (context) {
              final text = AppText.of(context);
              for (final duration in statusDurations) {
                final label = statusDurationLabel(text, duration);
                expect(label, isNotEmpty, reason: '$locale / $duration');
              }
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
    }
  });
}
