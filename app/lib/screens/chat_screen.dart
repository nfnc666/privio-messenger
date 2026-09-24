import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../calls/call.dart';
import '../calls/call_signal.dart';
import '../core/app_state.dart';
import '../core/conversation_controller.dart';
import '../core/failure.dart';
import '../core/sticker_controller.dart';
import '../crypto/safety_number.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../models/models.dart';
import '../media/attachment.dart' show CustomEmojiRef;
import '../media/photo.dart';
import '../media/photo_source.dart';
import '../media/voice.dart';
import '../services/system_settings.dart';
import 'contact_profile_screen.dart';
import 'group_info_screen.dart';
import 'license_screen.dart';
import 'safety_number_screen.dart';
import 'saved_info_screen.dart';
import 'sticker_pack_screen.dart';
import 'stickers_screen.dart';
import '../widgets/disappearing_timer_sheet.dart';
import '../widgets/photo_preview_sheet.dart';
import '../widgets/privio_back_button.dart';
import '../core/mention_suggestions.dart';
import '../data/message_store.dart';
import '../widgets/mention_suggestions_bar.dart';
import '../widgets/voice_composer.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/scrub_notice.dart';
import '../widgets/search_field.dart';
import '../widgets/sticker_picker.dart';

/// One conversation. Everything shown here was decrypted on this device, and
/// everything typed here is sealed before it leaves it.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.accountId,
    required this.title,
    super.key,
    this.isGroup = false,
    this.jumpTo,
  });

  final String accountId;
  final String title;
  final bool isGroup;

  /// The client id of a message to open at, from a search result. Null opens
  /// where a chat always opens: at the end.
  final String? jumpTo;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final GlobalKey<VoiceComposerState> _voiceKey = GlobalKey<VoiceComposerState>();

  /// The message the next send replies to, or null.
  Message? _replyingTo;

  final TextEditingController _composer = TextEditingController();

  /// Who to offer while an `@` is being typed, and where the `@` started.
  ///
  /// Recomputed from the field's own value rather than kept in step by hand:
  /// the caret moves for reasons this screen never hears about — a tap, a
  /// paste, an autocorrection — and a remembered offset would eventually
  /// replace the wrong word.
  List<MentionCandidate> _mentionOffers = const [];
  int? _mentionStart;

  /// The group's members, once something has needed them.
  ///
  /// Fetched at most once per open chat and only when somebody actually types
  /// an `@`: a list of who is in a group is not something to ask for on the
  /// chance it might be useful.
  List<GroupMember>? _members;
  bool _loadingMembers = false;

  /// Custom emoji put into the message being written, with where they sit.
  ///
  /// Held beside the field rather than inside it, because a `TextEditingValue`
  /// has nowhere to keep them: the field holds the fallback characters, which
  /// is exactly what makes the draft an ordinary sentence. Cleared when the
  /// message goes.
  final List<CustomEmojiRef> _pendingEmoji = [];

  /// A positioned list rather than a plain one, because a search result has to
  /// land on a message that may be hundreds of lines up. A ScrollController can
  /// only be given an offset, and the offset of a message that has never been
  /// laid out is not knowable.
  final ItemScrollController _scroll = ItemScrollController();

  /// Which message a search sent us to, drawn lit until it is read. Cleared on
  /// the first touch, so it marks the message rather than staining it.
  String? _highlighted;
  bool _jumped = false;

  /// What is typed into the Saved search box, or null when it is not open.
  ///
  /// Null and empty are different: the box being closed is not the same as a
  /// box with nothing in it, and only one of them filters the list.
  String? _savedQuery;

  /// Entries picked out for deletion, by client id. Empty means not in
  /// selection mode at all, which is why there is no second flag.
  final Set<String> _selected = {};

  /// What the safety-number screen would say, kept here so the header can say
  /// it too. Read once on open rather than on every rebuild: it changes only
  /// when a key does, and asking the keystore per frame would be absurd.
  VerificationState? _verification;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _highlighted = widget.jumpTo;
    _composer.addListener(_offerMentions);
    if (!widget.isGroup) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_readVerification()));
    }
  }

  Future<void> _readVerification() async {
    final state = PrivioScope.of(context);
    final me = state.accountId;
    if (me == null) return;
    final numbers = await state.services.crypto.safetyNumbers(
      localAccountId: me,
      remoteAccountId: widget.accountId,
    );
    if (!mounted) return;
    setState(() => _verification = numbers.isEmpty ? null : numbers.state);
  }

  /// Whether this screen is the account's own Saved area.
  ///
  /// Saved is a conversation whose other side is you, so this screen is the
  /// Saved screen — with the handful of things that make no sense against
  /// yourself removed: there is nobody to call, block, verify or set a
  /// disappearing timer against. See `ConversationController.savedId`.
  bool _isSaved(AppState state) => state.conversations.isSaved(widget.accountId);

  Future<void> _openSavedInfo() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SavedInfoScreen()),
      );

  Future<void> _openGroupInfo() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupInfoScreen(groupId: widget.accountId),
        ),
      );

  /// Opens somebody's profile.
  ///
  /// A push rather than a replacement, and that is the whole of what keeps the
  /// chat as it was: this screen's State stays alive underneath, so the
  /// half-written message in `_composer`, the reply being composed and the
  /// scroll position are all still there when the profile is popped. Nothing
  /// here saves or restores them — the correct implementation is the one that
  /// does not tear the chat down in the first place.
  Future<void> _openContactProfile(String accountId) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ContactProfileScreen(
            accountId: accountId,
            // True only in a one-to-one chat with that same person: then this
            // chat is the screen underneath, and "Message" over there means
            // "go back to it" rather than "open another one".
            returnToChat: !widget.isGroup && accountId == widget.accountId,
          ),
        ),
      );

  Future<void> _openSafetyNumber() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SafetyNumberScreen(
          accountId: widget.accountId,
          title: widget.title,
        ),
      ),
    );
    if (mounted) await _readVerification();
  }

  /// The header line. It used to say "End-to-end encrypted" unconditionally,
  /// which is true and answers the wrong question: encrypted *to whom* is the
  /// part a user cannot check for themselves.
  String _encryptionSubtitle(AppState state) {
    final text = AppText.of(context);
    if (state.conversations.hasIdentityChange(widget.accountId) ||
        state.conversations.hasKeyChangeAlert(widget.accountId)) {
      return text.chatSafetyNumberChanged;
    }
    return switch (_verification) {
      VerificationState.verified => text.chatEncryptedVerified,
      VerificationState.changed => text.chatEncryptedNumberChanged,
      _ => text.chatEncrypted,
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceRebuild.dispose();
    _composer.removeListener(_offerMentions);
    _composer.dispose();
    super.dispose();
  }

  /// Keeps the `@` suggestions in step with what is in the field.
  ///
  /// Everything it needs is already on this device: the address book, and —
  /// for a group — the member list the server decided this account may see.
  /// Nothing is looked up for a partly typed name.
  void _offerMentions() {
    final active = MentionSuggestions.activeQuery(_composer.value);
    if (active == null) {
      if (_mentionOffers.isNotEmpty || _mentionStart != null) {
        setState(() {
          _mentionOffers = const [];
          _mentionStart = null;
        });
      }
      return;
    }

    final state = PrivioScope.maybeOf(context);
    if (state == null) return;
    if (widget.isGroup) unawaited(_ensureMembers(state));

    final offers = MentionSuggestions.matches(
      active.query,
      contacts: state.conversations.contacts,
      members: _members ?? const [],
      // Mentioning yourself opens your own profile, which is a screen that
      // already has its own way in and tells you nothing you did not know.
      excludeAccountId: state.conversations.accountId,
    );
    if (offers == _mentionOffers && _mentionStart == active.start) return;
    setState(() {
      _mentionOffers = offers;
      _mentionStart = active.start;
    });
  }

  Future<void> _ensureMembers(AppState state) async {
    if (_members != null || _loadingMembers) return;
    _loadingMembers = true;
    try {
      final members = await state.conversations.groupMembers(widget.accountId);
      if (!mounted) return;
      _members = members;
      // The list arrived after the query it was wanted for, so ask again.
      _offerMentions();
    } on Object {
      // No members, no suggestions, and the name can still be typed out. A
      // composer must not show an error because a convenience did not load.
    } finally {
      _loadingMembers = false;
    }
  }

  void _pickMention(MentionCandidate candidate) {
    final start = _mentionStart;
    if (start == null) return;
    _composer.value =
        MentionSuggestions.insert(_composer.value, start, candidate.username);
    setState(() {
      _mentionOffers = const [];
      _mentionStart = null;
    });
  }

  Future<void> _send() async {
    final raw = _composer.text;
    final text = raw.trim();
    if (text.isEmpty) return;
    final replyTo = _replyingTo;

    // The body is trimmed, so every span shifts left by whatever the leading
    // whitespace was — and anything that no longer fits the trimmed text is
    // dropped rather than sent pointing at nothing. Silent, because what is
    // left is the sentence with its ordinary characters in it, which is what
    // the person typed.
    final lead = raw.length - raw.trimLeft().length;
    final spans = [
      for (final ref in _pendingEmoji)
        CustomEmojiRef(
          itemId: ref.itemId,
          packId: ref.packId,
          mediaId: ref.mediaId,
          offset: ref.offset - lead,
          length: ref.length,
        ),
    ].where((ref) => ref.fits(text)).toList(growable: false);

    _composer.clear();
    setState(() {
      _replyingTo = null;
      _pendingEmoji.clear();
    });
    await PrivioScope.of(context).conversations.send(
          widget.accountId,
          text,
          replyTo: replyTo,
          customEmoji: spans.isEmpty ? null : spans,
        );
    _scrollToEnd();
  }

  /// Long press on a bubble: react, or reply.
  ///
  /// One sheet for both, because they are the two things anyone wants to do to
  /// a message that is already there — and a long press that opened a menu of
  /// twelve would be a long press people stop using.
  /// Puts a message into this account's own Saved area.
  ///
  /// **The confirmation follows the entry, not the tap.** `saveToSaved` files
  /// the entry before it returns, and only then does this say "Saved" — a
  /// message that says so before the write would be claiming something that
  /// may not have happened. An entry that is on this device but has not
  /// reached the other ones says *that* instead, which is a different and
  /// true sentence.
  /// The Saved list: what the search left, pinned entries first.
  ///
  /// Pinned at the top and in their own order, because "pin" means "keep this
  /// where I can find it" and a pin that left the entry where it was would
  /// mean nothing. Everything else stays in the order it was written, which is
  /// what makes the area read like a notebook rather than a pile.
  List<Message> _savedEntries(AppState state, List<Message> all) {
    final query = _savedQuery?.trim().toLowerCase() ?? '';
    final visible = query.isEmpty
        ? all
        : [
            for (final entry in all)
              if (entry.body.toLowerCase().contains(query) ||
                  (entry.attachment?.fileName?.toLowerCase().contains(query) ?? false))
                entry,
          ];
    final pinned = [for (final entry in visible) if (entry.pinned) entry];
    if (pinned.isEmpty) return visible;
    return [
      for (final entry in visible)
        if (!entry.pinned) entry,
      ...pinned,
    ];
  }

  /// Deletes what is selected, after one confirmation for all of it.
  Future<void> _deleteSelected(AppState state) async {
    final text = AppText.of(context);
    final all = state.conversations.messagesWith(widget.accountId);
    final targets = [
      for (final entry in all)
        if (_selected.contains(entry.clientId ?? entry.id)) entry,
    ];
    if (targets.isEmpty) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.savedDeleteMany(targets.length)),
        content: Text(text.savedDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.commonDelete),
          ),
        ],
      ),
    );
    if (!(yes ?? false) || !mounted) return;

    for (final entry in targets) {
      await state.conversations.deleteForMe(widget.accountId, entry);
    }
    if (!mounted) return;
    setState(_selected.clear);
  }

  Future<void> _saveToSaved(AppState state, Message message) async {
    final text = AppText.of(context);
    final refused = await state.conversations.saveToSaved(message);
    if (!mounted) return;
    if (refused != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Failure(refused).words(text))),
      );
      return;
    }
    final saved = state.conversations.messagesWith(state.conversations.savedId ?? '');
    final pending = saved.isNotEmpty && saved.last.state == DeliveryState.queued;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(pending ? text.savedWaitingToSync : text.savedSaved)),
    );
  }

  Future<void> _openMessageActions(AppState state, Message message) async {
    final clientId = message.clientId;
    final queued = clientId != null && state.conversations.isQueued(clientId);
    final text = AppText.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PrivioSpacing.gutter,
                vertical: PrivioSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!queued)
                    // The way to a custom emoji. Six quick ones plus a door to
                    // the rest is the shape that keeps the long press a
                    // one-tap gesture for the common case.
                    GestureDetector(
                      onTap: () => Navigator.of(sheetContext).pop('react:more'),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: PrivioColors.surfaceRaised,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_reaction_outlined,
                          size: 20,
                          color: PrivioColors.textSecondary,
                        ),
                      ),
                    ),
                  for (final emoji in queued ? const <String>[] : ConversationController.quickReactions)
                    GestureDetector(
                      onTap: () => Navigator.of(sheetContext).pop('react:$emoji'),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: state.conversations.accountId != null &&
                                  message.reactions[state.conversations.accountId] == emoji
                              ? context.accents.surface
                              : PrivioColors.surfaceRaised,
                          shape: BoxShape.circle,
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: PrivioColors.border),
            // A recording that never went out. The controller has had a retry
            // and a discard since the offline queue was written, and nothing
            // offered either of them: a failed voice message showed a red mark
            // and left the person looking at it with nothing to do.
            if (queued) ...[
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: Text(text.chatRetrySendTitle),
                subtitle: Text(
                  message.state == DeliveryState.failed
                      ? text.chatRetryFailed
                      : text.chatRetryQueued,
                ),
                onTap: () => Navigator.of(sheetContext).pop('retry'),
              ),
              const Divider(height: 1, color: PrivioColors.border),
            ],
            if (!queued)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(text.commonReply),
                onTap: () => Navigator.of(sheetContext).pop('reply'),
              ),
            if (message.body.isNotEmpty && message.kind != MessageKind.deleted)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(text.chatCopyText),
                onTap: () => Navigator.of(sheetContext).pop('copy'),
              ),
            // Saved's own action, where the entry already is. Pinning belongs
            // to the notebook and nowhere else: a chat has no top to hold a
            // message at.
            if (_isSaved(state) && !message.isNotice)
              ListTile(
                leading: Icon(
                  message.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(message.pinned ? text.savedUnpin : text.savedPin),
                onTap: () => Navigator.of(sheetContext).pop('pin'),
              ),
            // And the way in, from an ordinary chat. Offered for anything with
            // something in it — a message under a disappearing timer included,
            // because a row that silently vanished would leave somebody
            // wondering where it went. It is refused when pressed, with the
            // reason, which is the honest version of the same thing.
            if (!_isSaved(state) &&
                !queued &&
                !message.isNotice &&
                message.kind != MessageKind.deleted)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text(text.savedSaveAction),
                onTap: () => Navigator.of(sheetContext).pop('save'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              iconColor: PrivioColors.danger,
              textColor: PrivioColors.danger,
              title: Text(text.commonDelete),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'retry') {
      await state.conversations.retry(clientId!);
      return;
    }
    if (action == 'reply') {
      setState(() => _replyingTo = message);
      return;
    }
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.body));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text.commonCopied)));
      return;
    }
    if (action == 'delete') {
      // Dropping the queue entry too. Removing only the bubble would leave the
      // message to arrive later out of a queue the person thought was empty.
      if (queued) {
        state.conversations.discard(clientId);
        return;
      }
      await _confirmDelete(state, message);
      return;
    }
    if (action == 'pin') {
      await state.conversations.togglePinned(widget.accountId, message);
      return;
    }
    if (action == 'save') {
      await _saveToSaved(state, message);
      return;
    }
    if (action == 'react:more') {
      await _reactWithCustom(state, message);
      return;
    }
    await state.conversations.react(
      widget.accountId,
      message,
      action.substring('react:'.length),
    );
  }

  /// Reacts with something out of the picker.
  ///
  /// A custom emoji reacts as a picture *with* its fallback character, so the
  /// reaction reaches somebody without the pack as an ordinary one. A plain
  /// emoji from the same picker is just a reaction. Picking a sticker here
  /// reacts with the character it stands for — a sticker is a message, and
  /// putting one in a reaction chip would be a different feature.
  Future<void> _reactWithCustom(AppState state, Message message) async {
    final controller = state.stickers;
    final choice = await showStickerPicker(context, controller);
    if (choice == null || !mounted) return;

    switch (choice) {
      case InsertCustomEmoji(:final pack, :final item) || SendSticker(:final pack, :final item):
        unawaited(controller.noteUsed([item.id]));
        await state.conversations.react(
          widget.accountId,
          message,
          item.emoji,
          sticker: StickerRef(itemId: item.id, packId: pack.id, mediaId: item.mediaId),
        );
      case InsertEmoji(:final emoji):
        await state.conversations.react(widget.accountId, message, emoji);
    }
  }

  /// Asks which kind of delete this is, and says plainly what each one can and
  /// cannot do.
  Future<void> _confirmDelete(AppState state, Message message) async {
    // Taking it back everywhere is only offered for what this account wrote,
    // and only while there is still somebody to ask.
    final canRecall = message.isMine && message.kind != MessageKind.deleted;
    final text = AppText.of(context);

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: PrivioSpacing.sm),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(text.chatDeleteForMe),
              subtitle: Text(text.chatDeleteForMeNote),
              onTap: () => Navigator.of(sheetContext).pop('me'),
            ),
            if (canRecall)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                iconColor: PrivioColors.danger,
                textColor: PrivioColors.danger,
                title: Text(text.chatDeleteForEveryone),
                subtitle: Text(text.chatDeleteForEveryoneNote),
                onTap: () => Navigator.of(sheetContext).pop('everyone'),
              ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'everyone') {
      await state.conversations.deleteForEveryone(widget.accountId, message);
    } else {
      await state.conversations.deleteForMe(widget.accountId, message);
    }
  }

  /// Picks a file and sends it. The bytes are read into memory rather than
  /// handed over as a path, because they have to be scrubbed and sealed before
  /// anything leaves the device.
  /// Offers the pack a sticker came from.
  ///
  /// Two answers, and the second one is the honest limit of what a sticker
  /// carries. A pack this account owns or has added opens. Anything else does
  /// not, and says so.
  ///
  /// The reason it cannot do better: a pack is reached by its **share code**,
  /// not by its id, and the code is what the owner revokes. A sticker carries
  /// the id — enough to fetch the picture and to recognise the pack, not enough
  /// to open one that was never shared with this reader. Putting the code in
  /// every message would make revoking it useless, since it would already be in
  /// everybody's history. So the tap is honest about reaching a wall rather
  /// than spinning at one.
  Future<void> _openStickerPack(StickerRef sticker) async {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).stickers;

    if (controller.packById(sticker.packId) != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StickerPackScreen(packId: sticker.packId),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.stickerPackGone)),
    );
  }

  /// Opens the picker, and does what was picked.
  ///
  /// The three outcomes are three different actions and the sealed result is
  /// what stops one being mistaken for another: a sticker is *sent*, a custom
  /// emoji is *inserted into what is being written*, and a plain emoji is a
  /// character like any other.
  Future<void> _pickSticker() async {
    final state = PrivioScope.of(context);
    final controller = state.stickers;
    final choice = await showStickerPicker(
      context,
      controller,
      onManagePacks: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const StickersScreen()),
        );
      },
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case SendSticker(:final pack, :final item):
        // Recorded as used before the send rather than after: the recents row
        // is about what somebody reached for, and a send that fails is still
        // something they reached for.
        unawaited(controller.noteUsed([item.id]));
        await state.conversations.sendSticker(
          widget.accountId,
          itemId: item.id,
          packId: pack.id,
          mediaId: item.mediaId,
          fallback: item.emoji,
          replyTo: _replyingTo,
        );
        if (mounted) setState(() => _replyingTo = null);
      case InsertCustomEmoji(:final pack, :final item):
        unawaited(controller.noteUsed([item.id]));
        _insertCustomEmoji(pack, item);
      case InsertEmoji(:final emoji):
        _insertAtCursor(emoji, spans: null);
    }
  }

  /// Puts a custom emoji into the field, and remembers where it went.
  ///
  /// The *character* goes into the text — so the field, the draft and anything
  /// that reads the field see an ordinary sentence — and the span is kept
  /// beside it, to travel with the message. That is the same split the payload
  /// makes, held here so the two cannot disagree.
  void _insertCustomEmoji(StickerPack pack, StickerItem item) {
    final offset = _insertAtCursor(item.emoji, spans: null);
    setState(() {
      _pendingEmoji.add(
        CustomEmojiRef(
          itemId: item.id,
          packId: pack.id,
          mediaId: item.mediaId,
          offset: offset,
          length: item.emoji.length,
        ),
      );
    });
  }

  /// Inserts text at the cursor and returns where it landed.
  int _insertAtCursor(String inserted, {List<CustomEmojiRef>? spans}) {
    final selection = _composer.selection;
    final text = _composer.text;
    final at = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;

    // Everything already marked that sits after the insertion point moves by
    // the same amount. Without this, typing an emoji in the middle of a
    // sentence would leave every later picture pointing one word to the left.
    for (var i = 0; i < _pendingEmoji.length; i++) {
      final ref = _pendingEmoji[i];
      if (ref.offset >= end) {
        _pendingEmoji[i] = CustomEmojiRef(
          itemId: ref.itemId,
          packId: ref.packId,
          mediaId: ref.mediaId,
          offset: ref.offset + inserted.length - (end - at),
          length: ref.length,
        );
      }
    }

    _composer.value = TextEditingValue(
      text: text.replaceRange(at, end, inserted),
      selection: TextSelection.collapsed(offset: at + inserted.length),
    );
    return at;
  }

  /// The plus button. A menu rather than a file picker, because a chat is
  /// mostly photographs and the old button opened a file browser to get to
  /// them — three taps and a filesystem to send a picture that was in the
  /// camera roll.
  Future<void> _attach() async {
    final text = AppText.of(context);
    final timer = PrivioScope.of(context).conversations.disappearAfter(widget.accountId);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(text.attachPhotos),
              onTap: () => Navigator.of(sheetContext).pop('photos'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: Text(text.attachFile),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            const Divider(height: 1, color: PrivioColors.border),
            // The timer's control lives here now that the bar is three things
            // wide. Its *state* does not: when it is on, the chip in the field
            // says so without anybody opening anything — see [_TimerChip].
            ListTile(
              leading: Icon(
                timer == null ? Icons.timer_outlined : Icons.timer_rounded,
                color: timer == null ? null : context.accents.accent,
              ),
              title: Text(text.privacyDisappearing),
              subtitle: Text(
                timer == null
                    ? text.commonOff
                    : DisappearingTimerSheet.badge(text, timer),
              ),
              onTap: () => Navigator.of(sheetContext).pop('timer'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'photos') return _pickPhotos();
    if (choice == 'timer') return _chooseTimer(PrivioScope.of(context));
    return _attachFile();
  }

  /// Opens the camera, and nothing else. The permission is asked for here, at
  /// the moment the camera is wanted, rather than at startup — a messenger
  /// that asks for the camera on first run has not explained why it wants it.
  Future<void> _capture() async {
    final camera = PrivioScope.of(context).services.photos;
    var again = true;
    while (again && mounted) {
      final pick = await camera.capture();
      if (!mounted) return;
      again = await _handlePick(pick, allowRetake: true);
    }
  }

  Future<void> _pickPhotos() async {
    final pick = await PrivioScope.of(context).services.photos.pickImages();
    if (!mounted) return;
    await _handlePick(pick, allowRetake: false);
  }

  /// Turns one of the [PhotoPick] cases into either a preview or a sentence.
  ///
  /// Returns true when the person asked to take the picture again, so the
  /// camera loop above reopens rather than recursing into itself.
  Future<bool> _handlePick(PhotoPick pick, {required bool allowRetake}) async {
    final text = AppText.of(context);
    switch (pick) {
      // A cancel is a decision, not an error. Nothing is prepared, nothing is
      // uploaded, and nothing is said about it.
      case PhotoCancelled():
        return false;
      case PhotoUnavailable():
        _showError(text.photoNoCamera);
        return false;
      case PhotoRefused(:final camera):
        await _explainRefusal(camera: camera);
        return false;
      case PhotoFailed(:final detail):
        _showError(text.photoFailed(detail));
        return false;
      case PhotoPicked(:final photos):
        return _prepareAndPreview(photos, allowRetake: allowRetake);
    }
  }

  Future<bool> _prepareAndPreview(
    List<PickedPhoto> picked, {
    required bool allowRetake,
  }) async {
    final text = AppText.of(context);
    // Captured before the first await: the account is what these photos belong
    // to, and a preview stays open for as long as somebody takes to write a
    // caption. Everything below is checked against it.
    final controller = PrivioScope.of(context).conversations;
    final account = controller.accountId;

    final prepared = await PhotoImage.prepareAll([for (final photo in picked) photo.bytes]);
    if (!mounted) return false;
    if (prepared.isEmpty) {
      _showError(text.photoNoneReadable);
      return false;
    }
    if (prepared.length < picked.length) {
      _showError(text.photoSomeLeftOut(picked.length - prepared.length));
    }

    final result = await PhotoPreviewSheet.open(
      context,
      photos: prepared,
      allowRetake: allowRetake,
    );
    if (!mounted) return false;
    if (result is PhotoPreviewRetake) return true;
    // Null is the cancel, and the close button, and the last picture being
    // removed. All three mean the same thing: nothing goes out.
    if (result is! PhotoPreviewSend) return false;

    // The switch may have happened while the preview was open. `sendPhotos`
    // checks this again for itself — this one is so the screen does not scroll
    // somebody else's chat.
    final now = PrivioScope.of(context).conversations;
    if (!identical(now, controller) || now.accountId != account) return false;

    await controller.sendPhotos(
      widget.accountId,
      result.photos,
      caption: result.caption,
      account: account,
    );
    if (!mounted) return false;
    _scrollToEnd();
    // The same notice every other attachment shows, and for the same reason:
    // what came out of the file is worth one line rather than an assumption.
    final report = result.photos.first.report;
    ScrubNotice.show(context, report);
    return false;
  }

  /// A refused camera or photo permission, with the one thing that can be done
  /// about it. Android and iOS both stop showing their dialog after the first
  /// no, so "try again" is not an option to offer — the settings page is.
  Future<void> _explainRefusal({required bool camera}) async {
    final text = AppText.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opened = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(camera ? text.photoCameraRefused : text.photoLibraryRefused),
        content: Text(text.photoAllowInSettings),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.photoOpenSettings),
          ),
        ],
      ),
    );
    if (opened != true) return;
    if (!await const SystemSettings().open()) {
      messenger.showSnackBar(SnackBar(content: Text(text.photoSettingsFailed)));
    }
  }

  Future<void> _attachFile() async {
    final text = AppText.of(context);
    PlatformFile? picked;
    try {
      // A platform whose picker is missing answers with a future that never
      // completes, which looks to the user like a button that does nothing. The
      // timeout turns that into a message they can act on.
      picked = await FilePicker.pickFile().timeout(const Duration(minutes: 2));
    } on TimeoutException {
      if (mounted) _showError(text.chatPickerNoResponse);
      return;
    } on Object catch (failure) {
      if (mounted) _showError(text.chatPickerFailed('$failure'));
      return;
    }

    if (picked == null || !mounted) return;

    // Reading is a separate step now, and a separate failure: the picker can
    // hand back a file the app then cannot open.
    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object {
      if (mounted) _showError(text.chatCouldNotReadFile(picked.name));
      return;
    }
    if (!mounted) return;

    final report = await PrivioScope.of(context).conversations.sendAttachment(
          widget.accountId,
          file: bytes,
          fileName: picked.name,
        );
    _scrollToEnd();
    if (report != null && mounted) ScrubNotice.show(context, report);
  }

  /// Members, and whether this device can read the group's name yet.
  String _groupSubtitle(AppState state) {
    final text = AppText.of(context);
    final group = state.conversations.groupInfo(widget.accountId);
    if (group == null) return text.chatEncrypted;
    if (group.groupKey == null) return text.chatWaitingGroupKey;
    final count = group.memberIds.length;
    return count > 0 ? text.chatMembersEncrypted(count) : text.chatEncrypted;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The index of [clientId] in the list as it is drawn, or null.
  ///
  /// One past the message's own position: the encryption notice is item zero.
  int? _indexOf(List<Message> messages, String clientId) {
    final at = messages.indexWhere((m) => m.clientId == clientId);
    return at == -1 ? null : at + 1;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.isAttached) return;
      _scroll.scrollTo(
        index: _messageCount,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// How many rows the list has, kept so a scroll-to-end has something to aim
  /// at from outside the build.
  int _messageCount = 0;

  /// Where the list should be on its very first layout.
  int _initialIndex(List<Message> messages) {
    final target = widget.jumpTo;
    if (target != null) return _indexOf(messages, target) ?? messages.length;
    return messages.length;
  }

  /// Opens the chat on the message a search found, rather than at the end.
  void _scrollToHit(List<Message> messages, String clientId) {
    final index = _indexOf(messages, clientId);
    if (index == null) {
      // Deleted, expired, or never on this device. Nothing to jump to, and the
      // chat still opens.
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.isAttached) return;
      _scroll.jumpTo(index: index, alignment: 0.3);
    });
  }

  // --- Disappearing messages ------------------------------------------------

  /// Sets how long messages in this chat live.
  ///
  /// The timer is agreed end to end: it rides inside each sealed payload, and
  /// a change is announced in one of its own, so the other side adopts it
  /// without the server being told what it is. Both devices then delete on
  /// their own clocks — which is the only way this can work, because a server
  /// asked to forget something is a server being trusted.
  Future<void> _chooseTimer(AppState state) async {
    final chosen = await DisappearingTimerSheet.choose(
      context,
      current: state.conversations.chatTimer(widget.accountId),
      accountDefault: state.conversations.defaultDisappearAfter,
      isGroup: false,
    );
    if (chosen == null || !mounted) return;
    await state.conversations.setChatTimer(widget.accountId, chosen.value);
  }

  /// Blocks the other side of a 1:1 chat.
  ///
  /// The server drops what they send afterwards and tells them nothing, so the
  /// confirmation says that rather than promising them a notice.
  Future<void> _confirmBlock(AppState state) async {
    final text = AppText.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.chatBlockTitle(widget.title)),
        content: Text(text.chatBlockBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.chatBlock),
          ),
        ],
      ),
    );
    if (!(yes ?? false) || !mounted) return;

    final blocked = await state.conversations.block(widget.accountId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          blocked ? text.chatBlocked(widget.title) : text.chatCouldNotBlock,
        ),
      ),
    );
    if (blocked) Navigator.of(context).pop();
  }

  // --- Voice messages -------------------------------------------------------

  void _onVoiceFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The microphone was refused.
  ///
  /// Said once, plainly, with the way to change it — not repeated on every
  /// press, and never as a dialog that blocks the chat.
  void _onMicrophoneDenied() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppText.of(context).chatMicrophoneDenied),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _sendVoice(AppState state, VoiceRecording recording) async {
    await state.conversations.sendVoice(widget.accountId, recording);
    _scrollToEnd();
  }

  /// Bumped whenever the recorder changes stage, so the row showing either the
  /// composer or the recording strip rebuilds.
  final ValueNotifier<int> _voiceRebuild = ValueNotifier<int>(0);

  void _voiceChanged() => _voiceRebuild.value++;

  Future<void> _startRecording() async {
    await _voiceKey.currentState?.start();
    _voiceChanged();
  }

  Future<void> _endRecording() async {
    await _voiceKey.currentState?.onHoldReleased();
    _voiceChanged();
  }

  /// Plays a recording back before it is sent, from memory.
  Future<void> _previewVoice(AppState state, VoiceRecording recording) =>
      state.services.player.play(
        'preview',
        recording.bytes,
        mediaType: recording.mediaType,
      );

  /// Stops anything being recorded when the app goes away.
  ///
  /// A call arriving, or the app being backgrounded, takes the microphone with
  /// it. Keeping a half-recording running through that produces silence at
  /// best; stopping into the preview keeps what was said and lets the user
  /// decide.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden) {
      final composer = _voiceKey.currentState;
      if (composer?.stage == VoiceComposerStage.recording) {
        unawaited(composer!.pause());
      }
    }
  }

  /// Shows the group's join link. It carries no key: whoever opens it joins,
  /// and a member's device sends them the key to the group's name afterwards.
  Future<void> _shareGroupLink(AppState state) async {
    final text = AppText.of(context);
    final link = state.conversations.groupInviteLink(widget.accountId);
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.chatNoGroupLink)),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surfaceRaised,
        title: Text(text.chatInviteLink),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(link, style: Theme.of(dialogContext).textTheme.bodySmall),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              text.chatInviteLinkNote,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(text.commonClose),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(text.commonCopy),
          ),
        ],
      ),
    );
  }

  Future<void> _call(AppState state, CallMedia media) => state.services.calls.place(
        CallParty(accountId: widget.accountId, username: widget.title),
        media: media,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = PrivioScope.of(context);
    final text = AppText.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final all = state.conversations.messagesWith(widget.accountId);
        // Saved sorts differently from a chat: what was pinned is held at the
        // top, and what was searched for is all that is drawn. A chat is a
        // conversation in order and neither applies to it.
        final messages = _isSaved(state) ? _savedEntries(state, all) : all;
        _messageCount = messages.length;
        // A one-to-one chat whose safety number changed, on an account that
        // asked to be stopped rather than warned. Groups are not held: a group
        // key change is a different event with different causes, and locking
        // a group of twelve because one member reinstalled is not a security
        // control anybody would leave switched on.
        final held = !widget.isGroup &&
            state.conversations.isHeldByKeyChange(widget.accountId);
        // Once, on the way in: a search sent us to a particular line.
        if (widget.jumpTo != null && !_jumped) {
          _jumped = true;
          _scrollToHit(messages, widget.jumpTo!);
        }

        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            titleSpacing: 0,
            // The picture and the name open something now. In a group that is
            // the group's own screen, as it always was; in a one-to-one chat it
            // is the other person's profile, which had no way in at all.
            title: InkWell(
              onTap: () => unawaited(
                _isSaved(state)
                    ? _openSavedInfo()
                    : widget.isGroup
                        ? _openGroupInfo()
                        : _openContactProfile(widget.accountId),
              ),
              child: Row(
                children: [
                  PrivioAvatar(
                    label: widget.title,
                    size: 34,
                    seed: widget.accountId.hashCode.abs(),
                    isGroup: widget.isGroup,
                    imageBytes: state.conversations.avatarFor(widget.accountId),
                  ),
                  const SizedBox(width: PrivioSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isSaved(state) ? text.savedTitle : widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          _isSaved(state)
                              ? text.savedChatSubtitle
                              : state.conversations.isTyping(widget.accountId)
                                  ? text.chatTyping
                                  : widget.isGroup
                                      ? _groupSubtitle(state)
                                      : _encryptionSubtitle(state),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: state.conversations.hasIdentityChange(widget.accountId) ||
                                    state.conversations.hasKeyChangeAlert(widget.accountId) ||
                                    _verification == VerificationState.changed
                                ? PrivioColors.warning
                                : context.accents.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // Choosing what to delete. The whole bar becomes about the
              // selection while one is running — a delete button beside a
              // search box beside a camera is a bar nobody can read.
              if (_isSaved(state) && _selected.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(right: PrivioSpacing.sm),
                  child: Center(
                    child: Text(
                      text.savedSelected(_selected.length),
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => unawaited(_deleteSelected(state)),
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: PrivioColors.danger,
                  tooltip: text.commonDelete,
                ),
                IconButton(
                  onPressed: () => setState(_selected.clear),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: text.commonCancel,
                ),
              ],
              // Saved's own actions, and none of the others: there is nobody
              // here to call, verify, block or share a link with.
              if (_isSaved(state) && _selected.isEmpty) ...[
                IconButton(
                  onPressed: () => setState(
                    () => _savedQuery = _savedQuery == null ? '' : null,
                  ),
                  icon: Icon(
                    _savedQuery == null ? Icons.search_rounded : Icons.search_off_rounded,
                  ),
                  tooltip: text.savedSearchHint,
                ),
                IconButton(
                  onPressed: () => unawaited(_openSavedInfo()),
                  icon: const Icon(Icons.perm_media_outlined),
                  tooltip: text.savedMediaRow,
                ),
              ],
              if (widget.isGroup)
                IconButton(
                  onPressed: () => _shareGroupLink(state),
                  icon: const Icon(Icons.link_rounded),
                  tooltip: text.chatInviteLink,
                ),
              // Groups have no call yet: a group call is a different piece of
              // machinery, not the same one with more people in it.
              if (!widget.isGroup && !_isSaved(state)) ...[
                IconButton(
                  onPressed: () => unawaited(_call(state, CallMedia.video)),
                  icon: const Icon(Icons.videocam_outlined),
                  tooltip: text.chatVideoCall,
                ),
                IconButton(
                  onPressed: () => unawaited(_call(state, CallMedia.audio)),
                  icon: const Icon(Icons.call_outlined),
                  tooltip: text.chatVoiceCall,
                ),
              ],
              // The overflow used to open the timer sheet directly, which made
              // it an icon that meant one specific thing. It is a menu now, so
              // blocking has somewhere to live.
              PopupMenuButton<String>(
                icon: Icon(
                  state.conversations.disappearAfter(widget.accountId) == null
                      ? Icons.more_vert_rounded
                      : Icons.timer_outlined,
                  color: state.conversations.disappearAfter(widget.accountId) == null
                      ? null
                      : context.accents.accent,
                ),
                color: PrivioColors.surface,
                tooltip: text.chatMore,
                onSelected: (action) => switch (action) {
                  'timer' => _chooseTimer(state),
                  'block' => _confirmBlock(state),
                  'safety' => _openSafetyNumber(),
                  'group' => _openGroupInfo(),
                  'saved-info' => _openSavedInfo(),
                  _ => null,
                },
                itemBuilder: (context) => [
                  if (widget.isGroup)
                    PopupMenuItem(
                      value: 'group',
                      child: Text(text.chatGroupInfo),
                    ),
                  // Not in Saved. The timer is a promise made to somebody
                  // else about their copy; here there is no somebody else,
                  // and applying a chat's timer to a notebook would delete
                  // the notes. See `savedNoTimerNote`.
                  if (!_isSaved(state))
                    PopupMenuItem(
                      value: 'timer',
                      // Two lines: the setting, and what it currently means
                      // here. The composer's chip says the duration only when
                      // there is one, so "Off" — the state somebody most
                      // wants confirmed before typing — had nowhere to be
                      // read without opening the sheet.
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(text.disappearingTitle),
                          Text(
                            state.conversations.chatTimer(widget.accountId).explicit
                                ? text.disappearingEffective(
                                    DisappearingTimerSheet.label(
                                      text,
                                      state.conversations.disappearAfter(widget.accountId),
                                    ),
                                  )
                                : text.disappearingFollowsDefault,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  if (_isSaved(state))
                    PopupMenuItem(
                      value: 'saved-info',
                      child: Text(text.savedInfoTitle),
                    ),
                  if (!widget.isGroup && !_isSaved(state))
                    PopupMenuItem(
                      value: 'safety',
                      child: Text(text.chatSafetyNumber),
                    ),
                  if (!widget.isGroup && !_isSaved(state))
                    PopupMenuItem(
                      value: 'block',
                      child: Text(text.chatBlock),
                    ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (_isSaved(state) && _savedQuery != null)
                PrivioSearchField(
                  hintText: text.savedSearchHint,
                  onChanged: (value) => setState(() => _savedQuery = value),
                ),
              if (_isSaved(state) && messages.isEmpty)
                Expanded(
                  child: _SavedEmpty(
                    searching: (_savedQuery?.trim().isNotEmpty) ?? false,
                  ),
                )
              else
              Expanded(
                // The highlight is a pointer, not a state: the first touch in
                // the transcript means it has been seen.
                child: Listener(
                  onPointerDown: (_) {
                    if (_highlighted != null) setState(() => _highlighted = null);
                  },
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _scroll,
                    // The first paint lands where it belongs, rather than at
                    // the top for one frame and then jumping.
                    initialScrollIndex: _initialIndex(messages),
                    padding: const EdgeInsets.only(bottom: PrivioSpacing.md),
                    itemCount: messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return const EncryptionNotice();
                      final message = messages[index - 1];
                      return MessageBubble(
                        message: message,
                        // In a one-to-one chat, a mention of the person you
                        // are talking to comes back here rather than opening
                        // this same conversation a second time.
                        chatWith: widget.isGroup ? null : widget.accountId,
                        highlighted: message.clientId != null &&
                            message.clientId == _highlighted,
                        onLongPress: _isSaved(state)
                            ? () => setState(
                                  () => _selected.add(message.clientId ?? message.id),
                                )
                            : () => _openMessageActions(state, message),
                        onTap: _selected.isEmpty
                            ? null
                            : () => setState(() {
                                  final id = message.clientId ?? message.id;
                                  if (!_selected.remove(id)) _selected.add(id);
                                }),
                        selected: _selected.contains(message.clientId ?? message.id),
                        onStickerTap: message.sticker == null
                            ? null
                            : () => unawaited(_openStickerPack(message.sticker!)),
                        // Groups only, and only where there is an id to open:
                        // a message filed before senders were recorded has a
                        // name and no account behind it, and a tap that looked
                        // somebody up by that name could land on the wrong
                        // person. A notice was written by nobody.
                        onSenderTap: !widget.isGroup ||
                                message.isNotice ||
                                (message.isMine ? state.accountId : message.senderAccountId) == null
                            ? null
                            : () => unawaited(_openContactProfile(
                                  (message.isMine ? state.accountId : message.senderAccountId)!,
                                )),
                      );
                    },
                  ),
                ),
              ),
              // The chat is held because the safety number changed and the
              // account asked to be stopped. Above the composer rather than at
              // the top of the transcript: it is about the message somebody is
              // about to write, not about the ones already there.
              if (held)
                _HeldBanner(
                  name: widget.title,
                  onOpen: () => unawaited(_openSafetyNumber()),
                ),
              if (_replyingTo != null)
                _ReplyBar(
                  message: _replyingTo!,
                  onCancel: () => setState(() => _replyingTo = null),
                ),
              if (state.conversations.failure != null)
                _ErrorBanner(
                  message: state.conversations.failure!.words(text),
                  // The server refuses to relay for an unlicensed account, so
                  // a send that failed while one is unactivated has somewhere
                  // to go rather than just a red line.
                  onActivate: state.license.needsActivation
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const LicenseScreen()),
                          )
                      : null,
                ),
              // The `@` suggestions, directly above the field they fill in.
              // Built only when there is something to offer, so nothing covers
              // the conversation while somebody is simply writing.
              if (_mentionOffers.isNotEmpty)
                MentionSuggestionsBar(
                  candidates: _mentionOffers,
                  onPick: _pickMention,
                ),
              // The recording strip lives inside the composer row rather than
              // replacing it. The microphone that started the hold has to stay
              // mounted, or the release never arrives.
              ListenableBuilder(
                listenable: _voiceRebuild,
                builder: (context, _) => _Composer(
                  saved: _isSaved(state),
                  controller: _composer,
                  onSend: held ? () {} : _send,
                  onAttach: held ? null : _attach,
                  onCamera: held ? null : _capture,
                  onPickSticker: held ? null : _pickSticker,
                  onHoldStart: _startRecording,
                  onHoldUpdate: (dx) {
                    _voiceKey.currentState?.onDragUpdate(dx);
                    _voiceChanged();
                  },
                  onHoldEnd: _endRecording,
                  onSendVoice: () {
                    _voiceKey.currentState?.send();
                    _voiceChanged();
                  },
                  onTyping: (_) => state.conversations.typing(widget.accountId),
                  disappearAfter: state.conversations.disappearAfter(widget.accountId),
                  onChooseTimer: () => unawaited(_chooseTimer(state)),
                  voiceStage: _voiceKey.currentState?.stage ?? VoiceComposerStage.idle,
                  voice: VoiceComposer(
                    key: _voiceKey,
                    recorder: state.services.recorder,
                    onSend: (recording) {
                      unawaited(_sendVoice(state, recording));
                      _voiceChanged();
                    },
                    onPermissionDenied: () {
                      _onMicrophoneDenied();
                      _voiceChanged();
                    },
                    onFailure: (message) {
                      _onVoiceFailure(message);
                      _voiceChanged();
                    },
                    preview: (recording) => _previewVoice(state, recording),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onActivate});

  final String message;

  /// Set only when the failure is one activating a license would fix.
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PrivioColors.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.gutter,
        vertical: PrivioSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
            ),
          ),
          if (onActivate != null)
            TextButton(
              onPressed: onActivate,
              child: Text(AppText.of(context).chatActivate),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onCamera,
    required this.onPickSticker,
    required this.onHoldStart,
    required this.onHoldUpdate,
    required this.onHoldEnd,
    required this.onSendVoice,
    required this.onTyping,
    required this.voiceStage,
    required this.voice,
    required this.disappearAfter,
    required this.onChooseTimer,
    this.saved = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttach;

  /// Opens the camera. Its own button rather than a third entry in the
  /// attachment menu: taking a picture and sending it is the single commonest
  /// thing anybody does in a chat, and two taps of indirection is what makes
  /// people reach for another app to do it.
  final VoidCallback? onCamera;

  /// Opens the sticker and emoji picker.
  final VoidCallback? onPickSticker;

  /// Hold the microphone to record, slide left to throw it away, let go to
  /// stop. [onHoldUpdate] receives the horizontal movement of the finger.
  final Future<void> Function() onHoldStart;
  final void Function(double dx) onHoldUpdate;
  final Future<void> Function() onHoldEnd;

  /// Sends the recording currently in preview.
  final VoidCallback onSendVoice;

  /// Called on every keystroke; the controller decides how often that turns
  /// into anything on the wire.
  final void Function(String text) onTyping;

  final VoiceComposerStage voiceStage;

  /// The recording or preview strip. Rendered where the text field would be.
  final Widget voice;

  /// How long a message sent from here lives, or null when the timer is off.
  final Duration? disappearAfter;
  final VoidCallback onChooseTimer;

  /// Whether this is the Saved area. A notebook asks for a note, not for a
  /// message — the same field, and one word that says which thing it is.
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final recording = voiceStage != VoiceComposerStage.idle;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.md,
          PrivioSpacing.sm,
          PrivioSpacing.md,
          PrivioSpacing.sm,
        ),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PrivioColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (recording)
              Expanded(child: voice)
            else ...[
              // One round button outside the field, then the field itself, then
              // the microphone. Three things across the bar instead of six.
              //
              // The row used to hold four icons *before* the text field, and on
              // a phone that left the field a column two words wide — the thing
              // people are actually here to use was the smallest thing in the
              // row. Everything that is not needed while typing moved into this
              // button's menu; everything that is stayed, inside the field where
              // it costs no width.
              _RoundButton(
                icon: Icons.add_rounded,
                tooltip: AppText.of(context).composerAttach,
                onPressed: onAttach,
              ),
              const SizedBox(width: PrivioSpacing.sm),
              Expanded(
                child: _Field(
                  controller: controller,
                  onSend: onSend,
                  onTyping: onTyping,
                  onPickSticker: onPickSticker,
                  onCamera: onCamera,
                  disappearAfter: disappearAfter,
                  onChooseTimer: onChooseTimer,
                  saved: saved,
                ),
              ),
              // Mounted but not shown, so the recorder's state survives the
              // switch back and forth.
              Offstage(child: voice),
            ],
            const SizedBox(width: PrivioSpacing.sm),
            _TrailingAction(
              controller: controller,
              stage: voiceStage,
              onSend: onSend,
              onSendVoice: onSendVoice,
              onHoldStart: onHoldStart,
              onHoldUpdate: onHoldUpdate,
              onHoldEnd: onHoldEnd,
            ),
          ],
        ),
      ),
    );
  }
}


/// One icon in a circle, the size of a comfortable thumb.
///
/// Its own widget rather than an `IconButton` so the two buttons flanking the
/// field are the same shape and the same 44 points, whatever the icon inside
/// them is.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 24,
            color: onPressed == null
                ? PrivioColors.textTertiary
                : PrivioColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The message field, with the things you reach for *while writing* inside it.
///
/// Telegram's shape, and for Telegram's reason: an icon inside the rounded
/// field costs no width from the text, so the field stays the widest thing in
/// the row instead of the narrowest.
///
/// What is inside and what is not is the whole decision:
///
/// * **Emoji and stickers, and the camera**, because both belong to the message
///   being written. Tapping either does not leave the chat.
/// * **The disappearing-messages timer, but only when it is on** — see
///   [_TimerChip]. Off, it lives in the plus menu with the other things you go
///   and fetch.
/// * Everything else — a file, the photo library — is in the plus menu. None of
///   it is needed mid-sentence.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.onSend,
    required this.onTyping,
    required this.onPickSticker,
    required this.onCamera,
    required this.disappearAfter,
    required this.onChooseTimer,
    this.saved = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final void Function(String text) onTyping;
  final VoidCallback? onPickSticker;
  final VoidCallback? onCamera;
  final Duration? disappearAfter;
  final VoidCallback onChooseTimer;

  /// Whether this is the Saved area. A notebook asks for a note, not for a
  /// message — the same field, and one word that says which thing it is.
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: const BoxDecoration(
        color: PrivioColors.surfaceRaised,
        borderRadius: BorderRadius.all(PrivioRadius.button),
      ),
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (disappearAfter != null)
            _TimerChip(timer: disappearAfter!, onPressed: onChooseTimer),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: disappearAfter == null ? PrivioSpacing.md : PrivioSpacing.xs,
                top: PrivioSpacing.md,
                bottom: PrivioSpacing.md,
              ),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                onChanged: onTyping,
                onSubmitted: (_) => onSend(),
                // The container above draws the shape, so the field draws
                // nothing: two rounded rectangles inside each other is what the
                // old bar looked like once the icons were moved in.
                decoration: InputDecoration(
                  hintText: saved ? text.savedComposerHint : text.composerHint,
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          _InlineIcon(
            icon: Icons.emoji_emotions_outlined,
            tooltip: text.pickerOpenTooltip,
            onPressed: onPickSticker,
          ),
          _InlineIcon(
            icon: Icons.photo_camera_outlined,
            tooltip: text.composerCamera,
            onPressed: onCamera,
          ),
        ],
      ),
    );
  }
}

/// A smaller icon, sized to sit inside the field without stretching it.
class _InlineIcon extends StatelessWidget {
  const _InlineIcon({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 44,
          child: Icon(
            icon,
            size: 22,
            color: onPressed == null
                ? PrivioColors.textTertiary
                : PrivioColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The disappearing-message timer, shown only while it is **on**.
///
/// The control moved into the plus menu; this is what is left in the bar, and
/// leaving it here was not a layout decision. A chat that silently deletes
/// itself is the one way this feature can hurt somebody — they keep writing,
/// and what they wrote is gone. That state has to be visible without being
/// asked for, right next to the field they are about to type into.
///
/// Off, there is nothing to warn about and nothing is drawn: the timer is then
/// one row in the plus menu, with its state written next to it.
class _TimerChip extends StatelessWidget {
  const _TimerChip({required this.timer, required this.onPressed});

  final Duration timer;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final badge = DisappearingTimerSheet.badge(text, timer);
    return Tooltip(
      message: text.composerTimerOn(badge),
      child: InkWell(
        onTap: onPressed,
        borderRadius: const BorderRadius.all(PrivioRadius.button),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.sm,
            PrivioSpacing.sm,
            PrivioSpacing.xs,
            PrivioSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_rounded, size: 18, color: context.accents.accent),
              const SizedBox(width: 3),
              Text(
                badge,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.accents.accent,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chat is held because the contact's safety number changed.
///
/// Not a red error bar: nothing has gone wrong and nothing has failed. What has
/// happened is that the person on the other end cannot be shown to be the
/// person who was there yesterday, and this account asked to be stopped at that
/// point rather than warned past it. The way out is the number, so the banner
/// is the way to it.
class _HeldBanner extends StatelessWidget {
  const _HeldBanner({required this.name, required this.onOpen});

  final String name;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Container(
      key: const Key('chat-held-by-key-change'),
      width: double.infinity,
      color: PrivioColors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.gutter,
        vertical: PrivioSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.chatHeldByKeyChange(name),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: PrivioColors.warning),
          ),
          const SizedBox(height: PrivioSpacing.sm),
          TextButton(
            onPressed: onOpen,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(text.chatHeldCompareNow),
          ),
        ],
      ),
    );
  }
}

class _TrailingAction extends StatelessWidget {
  const _TrailingAction({
    required this.controller,
    required this.stage,
    required this.onSend,
    required this.onSendVoice,
    required this.onHoldStart,
    required this.onHoldUpdate,
    required this.onHoldEnd,
  });

  final TextEditingController controller;
  final VoiceComposerStage stage;
  final VoidCallback onSend;
  final VoidCallback onSendVoice;
  final Future<void> Function() onHoldStart;
  final void Function(double dx) onHoldUpdate;
  final Future<void> Function() onHoldEnd;

  @override
  Widget build(BuildContext context) {
    if (stage == VoiceComposerStage.preview) {
      return IconButton.filled(
        key: const Key('voice-send'),
        onPressed: onSendVoice,
        style: IconButton.styleFrom(
          backgroundColor: context.accents.accent,
          foregroundColor: PrivioColors.background,
        ),
        icon: const Icon(Icons.send_rounded, size: 20),
        tooltip: AppText.of(context).chatSend,
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        if (hasText && stage == VoiceComposerStage.idle) {
          return IconButton.filled(
            onPressed: onSend,
            style: IconButton.styleFrom(
              backgroundColor: context.accents.accent,
              foregroundColor: PrivioColors.background,
            ),
            icon: const Icon(Icons.send_rounded, size: 20),
            tooltip: AppText.of(context).chatSend,
          );
        }

        final recording = stage != VoiceComposerStage.idle;
        return GestureDetector(
          key: const Key('voice-hold'),
          onLongPressStart: (_) => unawaited(onHoldStart()),
          onLongPressMoveUpdate: (details) => onHoldUpdate(details.offsetFromOrigin.dx),
          onLongPressEnd: (_) => unawaited(onHoldEnd()),
          // A tap is a common mis-hold, and starting a recording nobody meant
          // to start is worse than saying what the gesture is.
          onTap: recording
              ? null
              : () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppText.of(context).chatHoldToRecord),
                      duration: const Duration(seconds: 2),
                    ),
                  ),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: recording ? context.accents.accent : PrivioColors.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic_rounded,
              size: 20,
              color: recording ? PrivioColors.background : PrivioColors.textSecondary,
            ),
          ),
        );
      },
    );
  }
}

/// The strip above the composer while a reply is being written.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.message, required this.onCancel});

  final Message message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.gutter,
        PrivioSpacing.sm,
        PrivioSpacing.sm,
        PrivioSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: PrivioColors.surface,
        border: Border(
          top: const BorderSide(color: PrivioColors.border),
          left: BorderSide(color: context.accents.accent, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  switch ((message.isMine, message.senderName)) {
                    (true, _) => AppText.of(context).chatReplyingToYourself,
                    // In a group the quote is meaningless without the name;
                    // in a 1:1 chat the header already says who.
                    (false, final String name) =>
                      AppText.of(context).chatReplyingTo(name),
                    (false, null) => AppText.of(context).chatReplying,
                  },
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.accents.bright,
                  ),
                ),
                Text(
                  ConversationController.previewOfMessage(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: AppText.of(context).chatCancelReply,
          ),
        ],
      ),
    );
  }
}

/// Saved with nothing in it, or nothing that matches.
///
/// Two sentences rather than one, because the two are different situations: an
/// empty notebook wants to say what it is for, and a search that found nothing
/// wants to say only that. Showing the invitation to write a first note under a
/// failed search would read as though the notes had gone.
class _SavedEmpty extends StatelessWidget {
  const _SavedEmpty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off_rounded : Icons.bookmark_border_rounded,
              size: 40,
              color: PrivioColors.textTertiary,
            ),
            const SizedBox(height: PrivioSpacing.lg),
            Text(
              searching ? text.savedSearchNothing : text.savedEmptyTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (!searching) ...[
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                text.savedEmptyBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
