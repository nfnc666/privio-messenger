import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/failure.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/models/models.dart';
import 'package:privio/screens/chat_screen.dart';

import 'widget_test.dart' show quietServices, wrap;

/// The Saved area.
///
/// Its whole design is one decision — **Saved is the conversation whose id is
/// your own account id** — so most of what these tests pin is that it really
/// is that, and that the few things which must differ from a chat do:
/// no disappearing timer, nothing offered that only makes sense against
/// somebody else, and a message under a timer refused rather than copied.
Future<AppState> signedInAs(String account) async {
  final services = await quietServices();
  final state = AppState(services: services, store: InMemorySecureStore());
  await state.initialise();
  state.conversations.accountId = account;
  state.conversations.ensureSaved(username: 'alice');
  return state;
}

Message note(String body, {bool pinned = false, DateTime? at, Attachment? file}) => Message(
      id: body,
      clientId: body,
      body: body,
      sentAt: at ?? DateTime(2026, 9, 21, 10),
      isMine: true,
      kind: file == null ? MessageKind.text : MessageKind.file,
      attachment: file,
      pinned: pinned,
    );

void main() {
  group('what Saved is', () {
    test('it is the conversation with this account, and only ever one', () async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);

      expect(state.conversations.savedId, 'acc-alice');
      expect(state.conversations.isSaved('acc-alice'), isTrue);
      expect(state.conversations.isSaved('acc-bob'), isFalse);

      // Both ways in call this. Twice must not make two.
      state.conversations.ensureSaved(username: 'alice');
      state.conversations.ensureSaved(username: 'alice');
      final saved = state.conversations.chats.where((chat) => chat.isSaved);
      expect(saved, hasLength(1));
    });

    test('a second account gets its own, and never sees the first one’s',
        () async {
      // The store is per account, so this is really a test that Saved is
      // addressed by account id rather than by a fixed name — a shared id
      // would put one person's notes in another person's notebook.
      final first = await signedInAs('acc-alice');
      addTearDown(first.conversations.stop);
      first.services.store.append('acc-alice', note('Alice’s note'));

      final second = await signedInAs('acc-bob');
      addTearDown(second.conversations.stop);

      expect(second.conversations.savedId, 'acc-bob');
      expect(second.conversations.messagesWith('acc-bob'), isEmpty);
      expect(
        second.conversations.messagesWith('acc-alice'),
        isEmpty,
        reason: 'a second account read the first one’s notes',
      );
    });
  });

  group('saving a message from a chat', () {
    test('a disappearing message is refused, with a reason', () async {
      // The one rule this feature must not break: copying a message that was
      // promised to vanish would undo the promise its sender was given.
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);

      final fading = Message(
        id: 'm1',
        clientId: 'm1',
        body: 'this goes away',
        sentAt: DateTime(2026, 9, 21, 10),
        isMine: false,
        expiresAt: DateTime(2026, 9, 21, 11),
      );

      final refused = await state.conversations.saveToSaved(fading);
      expect(refused, FailureKind.savedDisappearingRefused);
      expect(
        state.conversations.messagesWith('acc-alice'),
        isEmpty,
        reason: 'it was refused and saved anyway',
      );
    });

    test('a deleted message has nothing to save', () async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);

      final gone = Message(
        id: 'm2',
        clientId: 'm2',
        body: '',
        sentAt: DateTime(2026, 9, 21, 10),
        isMine: false,
        kind: MessageKind.deleted,
      );

      expect(await state.conversations.saveToSaved(gone), FailureKind.savedNothingToSave);
      expect(state.conversations.messagesWith('acc-alice'), isEmpty);
    });

    test('an ordinary message is filed, and the entry exists before the answer',
        () async {
      // The confirmation has to follow the entry. `saveToSaved` returns only
      // once the entry is in the store, which is what lets the screen say
      // "Saved" and mean it.
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);

      final refused = await state.conversations.saveToSaved(
        note('worth keeping'),
      );
      expect(refused, isNull);

      final saved = state.conversations.messagesWith('acc-alice');
      expect(saved, hasLength(1));
      expect(saved.single.body, 'worth keeping');
      expect(saved.single.isMine, isTrue);
      expect(
        saved.single.expiresAt,
        isNull,
        reason: 'a saved entry must not carry a timer',
      );
    });
  });

  group('keeping what is in it', () {
    test('a disappearing timer cannot be set on Saved at all', () async {
      // The guard is at the door every timer change goes through, not only in
      // the menu that no longer offers one: a rule that lives in a widget is a
      // rule the next call site does not have. Remove it and this goes red.
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);

      expect(state.conversations.mayChangeDisappearAfter('acc-alice'), isFalse);
      final set = await state.conversations.setDisappearAfter(
        'acc-alice',
        const Duration(hours: 1),
      );
      expect(set, isFalse);
      expect(
        state.conversations.disappearAfter('acc-alice'),
        isNull,
        reason: 'Saved started deleting its own notes',
      );
    });

    test('pinning holds an entry and survives being read back', () async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      state.services.store.append('acc-alice', note('ordinary'));
      state.services.store.append('acc-alice', note('important'));

      final target = state.conversations.messagesWith('acc-alice').last;
      await state.conversations.togglePinned('acc-alice', target);

      final after = state.conversations.messagesWith('acc-alice');
      expect(after.where((m) => m.pinned).single.body, 'important');

      // And off again.
      await state.conversations.togglePinned('acc-alice', after.last);
      expect(state.conversations.messagesWith('acc-alice').any((m) => m.pinned), isFalse);
    });

    test('the media overview lists what carries a file, newest first', () async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      state.services.store.append('acc-alice', note('just a note'));
      state.services.store.append(
        'acc-alice',
        note(
          'the contract',
          at: DateTime(2026, 9, 21, 11),
          file: const Attachment(
            mediaId: 'media-1',
            mediaKey: 'key',
            mediaType: 'application/pdf',
            byteSize: 2048,
            fileName: 'contract.pdf',
          ),
        ),
      );

      final media = state.conversations.savedMedia();
      expect(media, hasLength(1));
      expect(media.single.attachment!.fileName, 'contract.pdf');
    });
  });

  group('the screen', () {
    Future<void> openSaved(WidgetTester tester, AppState state) async {
      await tester.pumpWidget(
        wrap(const ChatScreen(accountId: 'acc-alice', title: 'alice'), state),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('says what it is, and not whose account it is', (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      await openSaved(tester, state);

      expect(find.text('Saved'), findsWidgets);
      expect(find.text('Only you can see this'), findsOneWidget);
      // The username would read as a chat with somebody who shares your name.
      expect(find.text('alice'), findsNothing);
    });

    testWidgets('offers nothing that only makes sense against somebody else',
        (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      await openSaved(tester, state);

      expect(find.byIcon(Icons.call_outlined), findsNothing);
      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    });

    testWidgets('the empty area says what it is for', (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      await openSaved(tester, state);

      expect(find.text('Nothing saved yet'), findsOneWidget);
    });

    testWidgets('and the timer is not on its menu', (tester) async {
      // A chat's timer applied to a notebook would delete the notes.
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      await openSaved(tester, state);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Disappearing Messages'), findsNothing);
      expect(find.text('Safety Number'), findsNothing);
      expect(find.text('Block'), findsNothing);
      expect(find.text('About Saved'), findsOneWidget);
    });

    testWidgets('a long press picks entries out rather than opening the sheet',
        (tester) async {
      final state = await signedInAs('acc-alice');
      addTearDown(state.conversations.stop);
      state.services.store.append('acc-alice', note('first'));
      state.services.store.append('acc-alice', note('second'));
      await openSaved(tester, state);

      await tester.longPress(find.text('first'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      // A second one joins the selection rather than replacing it.
      await tester.tap(find.text('second'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
    });
  });
}
