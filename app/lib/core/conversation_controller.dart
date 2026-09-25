import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/message_store.dart';
import '../data/outbox.dart';
import '../media/attachment.dart';
import '../media/avatar.dart';
import '../media/metadata_scrubber.dart';
import '../media/photo.dart';
import '../crypto/privio_crypto.dart';
import 'message_search.dart';
import '../media/voice.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../services/messaging_service.dart';
import '../services/realtime_connection.dart';
import '../models/models.dart';
import '../models/security_event.dart';
import 'api_client.dart';
import 'failure.dart';
import 'privio_services.dart';

/// Drives the chat and contact screens from real data.
///
/// This is the seam between the UI and the encryption layer: it hands plaintext
/// down to [MessagingService] to be sealed, and takes decrypted text back up.
/// Nothing above this class ever sees a key; nothing below it ever sees a
/// widget.
class ConversationController extends ChangeNotifier {
  ConversationController(this._services);

  final PrivioServices _services;

  /// How often the queue is drained *without* the socket having said anything.
  ///
  /// Delivery is pushed, so this is only a safety net: it covers a socket that
  /// is connected but not delivering, and the gap between app start and the
  /// handshake completing. Long, because the radio waking every few seconds is
  /// exactly what the socket exists to avoid.
  static const Duration fallbackPollInterval = Duration(minutes: 2);

  /// How often expired messages are swept off the screen.
  static const Duration expirySweepInterval = Duration(seconds: 5);

  Timer? _poller;
  Timer? _expirySweep;
  RealtimeConnection? _realtime;

  /// Voice messages that have not gone out yet, oldest first.
  ///
  /// Everything in here is already sealed, so the queue can be written to the
  /// encrypted archive without a plaintext recording ever reaching storage.
  final List<PendingSend> _outbox = [];

  /// Whether this account sends read receipts and typing notices.
  ///
  /// Reciprocal, the way people expect: someone who does not send read
  /// receipts does not see other people's either. A setting that took without
  /// giving would be a different feature wearing this one's name.
  bool _readReceipts = true;
  bool _typingIndicators = true;

  /// When a typing notice was last sent per conversation, so a burst of
  /// keystrokes does not become a burst of envelopes.
  final Map<String, DateTime> _typingSentAt = {};
  Timer? _typingSweep;

  /// The flush currently running, if any, and whether another was asked for
  /// while it ran. Without this a caller that flushes during a flush gets a
  /// silent no-op — and the message it was flushing for sits there.
  Future<void>? _flushing;
  bool _flushAgain = false;
  StreamSubscription<List<dynamic>>? _realtimeEnvelopes;
  StreamSubscription<void>? _realtimeKeyRequests;

  /// Run when somebody is waiting for a key this device might hold. Set by the
  /// app so channels can answer too, since their keys live elsewhere.
  Future<void> Function()? onKeyRequest;
  Timer? _saveDebounce;
  bool _draining = false;

  List<Contact> _contacts = const [];
  Failure? _failure;

  /// Devices whose identity key stopped matching what was pinned, by account.
  ///
  /// A send to one of these is refused rather than re-pinned, so this is the
  /// list of conversations waiting on a person to look at a safety number.
  final Map<String, Set<int>> _identityChanges = {};

  /// Accounts whose pinned key was replaced by something they sent, and whose
  /// owner has not been shown the new number yet. Loaded from storage on
  /// start, because a notice missed is a notice that did its job for nobody.
  final Set<String> _keyChangeAlerts = {};

  List<Contact> get contacts => _contacts;

  /// The last failure worth showing, or null. Cleared when the next call works.
  ///
  /// A case, never a sentence: this class cannot know which of the five
  /// languages the person holding the phone reads.
  Failure? get failure => _failure;

  /// Whether this conversation is waiting on the user to review a changed key.
  bool hasIdentityChange(String accountId) =>
      (_identityChanges[accountId] ?? const <int>{}).isNotEmpty;

  Set<int> identityChangesFor(String accountId) =>
      _identityChanges[accountId] ?? const <int>{};

  /// Whether this conversation's key changed under an incoming message.
  ///
  /// Separate from [hasIdentityChange]: that one means sends are refused and
  /// the user has to decide. This one means the change has already been
  /// accepted — receiving cannot be refused without handing anyone a way to
  /// silence a conversation — so all that is left is to say so.
  bool hasKeyChangeAlert(String accountId) => _keyChangeAlerts.contains(accountId);

  /// Answers the notice. Called when the safety number has been put in front
  /// of the user, which is the only thing that resolves it.
  Future<void> acknowledgeKeyChange(String accountId) async {
    if (!_keyChangeAlerts.remove(accountId)) return;
    await _services.crypto.clearKeyChangeAlert(accountId);
    notifyListeners();
  }

  Future<void> loadKeyChangeAlerts() async {
    _keyChangeAlerts
      ..clear()
      ..addAll(await _services.crypto.keyChangeAlerts());
    if (_keyChangeAlerts.isNotEmpty) notifyListeners();
  }

  /// Turns whatever the protocol re-pinned during decryption into something
  /// the user will actually see.
  Future<void> _raiseKeyChanges() async {
    for (final change in _services.crypto.takeIdentityReplacements()) {
      if (change.accountId == accountId) continue; // one of my own devices
      // Only the first device of theirs to change raises a line in the
      // security log. A contact who reinstalls brings several new device keys
      // at once, and five identical warnings about one event teach the reader
      // to scroll past them.
      final first = _keyChangeAlerts.add(change.accountId);
      await _services.crypto.raiseKeyChangeAlert(change.accountId);
      if (first) {
        onSecurityEvent?.call(
          SecurityEventKind.contactKeyChanged,
          subject: _services.store.conversationWith(change.accountId)?.user?.displayName,
        );
      }
    }
  }

  /// Where a security event goes, or null when nothing is listening.
  ///
  /// A callback rather than a reference to the controller that displays the
  /// list, so the conversation layer never depends on a settings screen. Set by
  /// [AppState] at sign-in.
  void Function(SecurityEventKind kind, {String? subject})? onSecurityEvent;

  /// Records a refused send so the chat can say why rather than showing a
  /// message stuck at "failed" with no explanation.
  void _noteIdentityChange(Object failure) {
    if (failure is! IdentityChangedException) return;
    (_identityChanges[failure.accountId] ??= <int>{}).add(failure.deviceIndex);
  }

  /// Re-pins whatever the server offers now, after the user has looked at the
  /// new number. Only reachable from the safety-number screen.
  Future<void> acceptIdentityChange(String accountId) async {
    for (final index in identityChangesFor(accountId)) {
      await _services.crypto.acceptIdentityChange(accountId, index);
    }
    _identityChanges.remove(accountId);
    _failure = null;
    notifyListeners();
  }

  /// This account's own id, told once at sign-in, so a reaction of mine can be
  /// told apart from somebody else's on the same message.
  String? accountId;

  bool get readReceiptsEnabled => _readReceipts;
  bool get typingIndicatorsEnabled => _typingIndicators;

  bool _blockOnKeyChange = false;

  /// Whether a chat locks itself when the contact's safety number changes.
  ///
  /// **A local setting and only a local one.** It is read from and written to
  /// this device's keystore; the server is never told, because a server that
  /// knew which of its users refuse unexplained key changes would know exactly
  /// which of them not to try it on.
  bool get blockOnKeyChange => _blockOnKeyChange;

  /// Reads the setting for [account]. Off until it has answered, which is the
  /// safe default for a *lock*: a chat must not be unusable because a keystore
  /// read was slow.
  Future<void> loadKeyChangeBlocking(String account) async {
    final block = await _services.secureStore.readBlockOnKeyChange(account);
    if (accountId != account) return;
    _blockOnKeyChange = block;
    notifyListeners();
  }

  Future<void> setBlockOnKeyChange(bool block) async {
    final account = accountId;
    _blockOnKeyChange = block;
    notifyListeners();
    if (account != null) {
      await _services.secureStore.writeBlockOnKeyChange(account, block);
    }
  }

  /// Whether this conversation is held until the new number has been looked at.
  ///
  /// Two sources, and both are already facts this class keeps: a key change
  /// seen on an *incoming* message ([hasKeyChangeAlert]) and one that refused
  /// an *outgoing* one ([hasIdentityChange]). Either means the person on the
  /// other end is not provably the person who was there yesterday.
  ///
  /// What the lock does and does not do is worth being exact about, because the
  /// difference is the difference between a security control and a comfort
  /// blanket:
  ///
  /// * **Sending is refused on a changed key whether this is on or off.** That
  ///   is the crypto layer's pinning and it has never been optional — see
  ///   [IdentityChangedException]. This setting does not add that.
  /// * What it adds is that the chat stops *looking* usable: the composer is
  ///   disabled and says why, rather than accepting a message that will fail.
  /// * **Messages already received are not deleted or hidden.** Privio does not
  ///   throw away something it has already decrypted; the chat is marked
  ///   instead. Deleting them would destroy evidence of exactly the event the
  ///   user is being warned about.
  bool isHeldByKeyChange(String conversationId) =>
      _blockOnKeyChange &&
      (hasKeyChangeAlert(conversationId) || hasIdentityChange(conversationId));

  /// True while the other side of [conversationId] is typing.
  bool isTyping(String conversationId) =>
      _typingIndicators &&
      (_services.store.conversationWith(conversationId)?.isTypingAt(DateTime.now()) ?? false);

  List<ChatSummary> get chats {
    final rows = [
      for (final conversation in _services.store.conversations()) _summarise(conversation),
    ];
    // The store leaves an empty direct conversation out of the list on purpose
    // — an empty chat with somebody is just a contact, and belongs under
    // Contacts. Saved is the one direct conversation that is not a contact: it
    // is a place, and a place has to be reachable before anything is in it or
    // there is no way to put the first thing there.
    //
    // Added here rather than by loosening the store's rule, because the store
    // does not know which id is this account's own and should not have to.
    final me = accountId;
    if (me == null) return rows;
    if (!rows.any((row) => row.id == me)) {
      final saved = _services.store.conversationWith(me);
      if (saved != null) rows.add(_summarise(saved));
    }

    // And then it goes to the top, ahead of pinned chats and whatever arrived
    // most recently.
    //
    // Not by pinning it — a pin is somebody's choice and can be taken back,
    // and Saved is not a chat competing for the same place. It is the one row
    // that is a *destination*: the place your own notes live, which is worth
    // nothing if finding it means scrolling past a busy morning. So the order
    // is fixed here rather than in the store's sort, where it would need a
    // rule about an id the store has no business knowing.
    //
    // The screen still filters this list. Under "Groups" or "Unread" the row
    // drops out like any other, because there the question being asked is not
    // "where do I start" but "which of these match".
    final at = rows.indexWhere((row) => row.id == me);
    if (at > 0) rows.insert(0, rows.removeAt(at));
    return rows;
  }

  List<Message> messagesWith(String accountId) =>
      _services.store.conversationWith(accountId)?.messages ?? const [];

  ChatSummary _summarise(Conversation conversation) {
    final last = conversation.lastMessage;
    return ChatSummary(
      id: conversation.id,
      title: conversation.title,
      // Saved is a conversation with yourself, so without this the chat list
      // would show a row bearing your own username — which reads as somebody
      // else. The word is the screen's; this only says which row it is.
      isSaved: isSaved(conversation.id),
      isGroup: conversation.isGroup,
      // A group's picture comes from its own cache, keyed by group; a person's
      // from the avatar cache, keyed by media id. Two caches because the two
      // are fetched by different rules — see `groupAvatar`.
      avatarBytes: conversation.isGroup
          ? _groupAvatarCache[conversation.id]?.$2
          : _avatarCache[conversation.id],
      // Typing replaces the preview rather than sitting beside it: the row has
      // one line, and what someone is doing now beats what they said before.
      // An empty Saved area says what it is for. Every other empty
      // conversation is one the store has already left out of the list, so
      // this is the only row that can be blank — and blank, next to a
      // bookmark, reads as a notebook somebody gave up on rather than one
      // nobody has opened.
      preview: switch (true) {
        _ when isTyping(conversation.id) => const ChatPreview(ChatPreviewKind.typing),
        _ when last == null && isSaved(conversation.id) =>
          const ChatPreview(ChatPreviewKind.savedEmpty),
        _ => _previewOf(last),
      },
      typing: isTyping(conversation.id),
      timestamp: last == null ? ChatStamp.none : _stampFor(last.sentAt),
      unreadCount: conversation.unreadCount,
      pinned: conversation.pinned,
      previewKind: last?.kind ?? MessageKind.text,
      avatarSeed: conversation.id.hashCode.abs(),
    );
  }

  /// A file with no caption still needs a line in the list.
  ///
  /// Returns the case, not the words: "Photo" has five spellings here and this
  /// class has no way of knowing which one the reader wants.
  static ChatPreview _previewOf(Message? message) {
    if (message == null) return ChatPreview.empty;
    // A tombstone has no body, and an empty last line in the chat list would
    // read as a conversation with nothing in it.
    if (message.kind == MessageKind.deleted) {
      return const ChatPreview(ChatPreviewKind.deleted);
    }
    final notice = message.notice;
    if (notice != null) return ChatPreview(ChatPreviewKind.notice, notice: notice);
    if (message.body.isNotEmpty) {
      return ChatPreview(ChatPreviewKind.body, text: message.body);
    }
    final attachment = message.attachment;
    if (attachment == null) return ChatPreview.empty;
    final fileName = attachment.fileName;
    if (fileName != null) return ChatPreview(ChatPreviewKind.body, text: fileName);
    return ChatPreview(switch (message.kind) {
      MessageKind.photo => ChatPreviewKind.photo,
      MessageKind.video => ChatPreviewKind.video,
      MessageKind.voice => ChatPreviewKind.voice,
      _ => ChatPreviewKind.file,
    });
  }

  static ChatStamp _stampFor(DateTime when) {
    final now = DateTime.now();
    final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
    if (sameDay) return ChatStamp(ChatStampKind.time, at: when);
    final yesterday = now.subtract(const Duration(days: 1));
    if (when.year == yesterday.year && when.month == yesterday.month && when.day == yesterday.day) {
      return const ChatStamp(ChatStampKind.yesterday);
    }
    return ChatStamp(ChatStampKind.date, at: when);
  }

  /// Called with whatever channel posts the archive held, on restore.
  void Function(Map<String, List<ChannelPost>>)? onChannelPostsRestored;

  /// Reads the sealed history back so a relaunch does not start blank.
  Future<void> restore() async {
    // The account is named, so an archive belonging to somebody else is refused
    // rather than adopted. That matters on a phone whose previous sign-out was
    // interrupted: the history is still on disk and the session that owned it
    // is not.
    final contents = await _services.archive.load(accountId: accountId);
    // Handed straight back out, so a channel opened before any network call
    // shows what was there last time. Kept even when there is no conversation
    // history at all — somebody may be in channels and in no chats.
    _channelPosts = contents.channelPosts;
    onChannelPostsRestored?.call(contents.channelPosts);
    if (contents.conversations.isEmpty && contents.outbox.isEmpty) return;
    _services.store.restore(contents.conversations);
    _outbox
      ..clear()
      ..addAll(contents.outbox);
    // A message queued before the app was killed is still owed to somebody.
    _services.store.pruneExpired(DateTime.now());
    _noteCappedTimers();
    notifyListeners();
    detached(flushOutbox());
  }

  /// Says so where a stored timer was longer than a day and was shortened.
  ///
  /// The clamp itself happens in the archive, and doing it quietly would be
  /// the wrong half of the job: somebody who set a week would find out from a
  /// message that disappeared six days early. Written once per chat, into that
  /// chat, and only about *new* messages — everything already in the history
  /// keeps the expiry it was sent with.
  void _noteCappedTimers() {
    for (final conversation in _services.store.conversations()) {
      if (!conversation.timerWasCapped) continue;
      conversation.timerWasCapped = false;
      _services.store.append(
        conversation.id,
        Message(
          id: 'notice-capped-${conversation.id}',
          body: 'Disappearing messages were set to 24 hours, the longest this app allows.',
          sentAt: DateTime.now(),
          isMine: false,
          kind: MessageKind.notice,
          notice: const SystemNotice(NoticeKind.timerCapped),
        ),
      );
    }
  }

  /// Takes on a history that a restore has just put into the store.
  ///
  /// The backup service replaces the store's contents; this seals them into the
  /// local archive and tells the screens, so a restore survives the next launch
  /// rather than living only in memory until something else saves.
  Future<void> adoptRestored() async {
    _services.store.pruneExpired(DateTime.now());
    await flush();
    notifyListeners();
  }

  /// Channel posts to seal alongside the conversations.
  ///
  /// Handed over by the channel controller rather than fetched, because this is
  /// the only place that knows how a history is sealed and that is the only
  /// place that knows what a channel holds. Kept here so one archive write
  /// carries both, instead of two writers racing over the same blob.
  Map<String, List<ChannelPost>> _channelPosts = const {};

  void cacheChannelPosts(Map<String, List<ChannelPost>> posts) {
    _channelPosts = {for (final entry in posts.entries) entry.key: entry.value};
    _persist();
  }

  /// Writes the history back, coalescing bursts: a fast exchange should not
  /// re-seal and rewrite the whole archive once per keystroke.
  void _persist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(
        _services.archive.save(
          _services.store.conversations(),
          outbox: _outbox,
          accountId: accountId,
          channelPosts: _channelPosts,
        ),
      );
    });
  }

  /// Flushes any pending write. Called when the app goes to the background.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    await _services.archive.save(
      _services.store.conversations(),
      outbox: _outbox,
      accountId: accountId,
      channelPosts: _channelPosts,
    );
  }

  /// Whether the realtime socket is currently up.
  ValueListenable<bool>? get connected => _realtime?.connected;

  /// Opens the realtime socket and starts the fallback poll. Safe to call more
  /// than once.
  void start({String? token}) {
    _poller ??= Timer.periodic(fallbackPollInterval, (_) => drain());
    // Often enough that a 30-second timer is roughly honoured on screen, cheap
    // enough to be invisible: it walks a list already in memory.
    _expirySweep ??= Timer.periodic(expirySweepInterval, (_) => pruneExpired());
    // A typing indicator has to go out on its own: nothing arrives to say
    // "stopped", so the screen has to notice the notice has expired.
    _typingSweep ??= Timer.periodic(typingInterval, (_) => _fadeTyping());
    if (token != null) _openRealtime(token);
    pruneExpired();
    unawaited(drain());
    detached(flushOutbox());
  }

  void _openRealtime(String token) {
    if (_realtime != null) return;
    final realtime = RealtimeConnection(
      baseUrl: _services.api.baseUrl,
      token: token,
    );
    _realtime = realtime;
    _realtimeEnvelopes = realtime.envelopes.listen(_onPushedEnvelopes);
    // Nothing to read: somebody is waiting for a key. Answering on the poll
    // instead would leave them looking at a group they cannot name for it.
    _realtimeKeyRequests = realtime.keyRequests.listen((_) {
      unawaited(_maintainGroupKeys());
      unawaited(onKeyRequest?.call() ?? Future<void>.value());
    });
    realtime.start();
  }

  /// Envelopes pushed down the socket. Acknowledged on the same socket, and
  /// only once they have been decrypted and filed.
  Future<void> _onPushedEnvelopes(List<dynamic> envelopes) async {
    try {
      final result = await _services.messaging.decryptEnvelopes(envelopes);
      await _fileResult(result);
      if (result.highestHandled > 0) _realtime?.acknowledge(result.highestHandled);
    } on Object catch (failure) {
      _failure = Failure.of(failure, FailureKind.couldNotReadMessage);
      notifyListeners();
    }
  }

  void stop() {
    _poller?.cancel();
    _poller = null;
    _expirySweep?.cancel();
    _expirySweep = null;
    _typingSweep?.cancel();
    _typingSweep = null;
    unawaited(_realtimeEnvelopes?.cancel());
    _realtimeEnvelopes = null;
    unawaited(_realtimeKeyRequests?.cancel());
    _realtimeKeyRequests = null;
    unawaited(_realtime?.close());
    _realtime = null;
  }

  @override
  void dispose() {
    stop();
    _saveDebounce?.cancel();
    _attachmentCache.clear();
    super.dispose();
  }

  // --- Saved -----------------------------------------------------------------

  /// The conversation id of this account's Saved area.
  ///
  /// **It is the account's own id**, and that one decision is most of this
  /// feature. Saved is not a second kind of message with its own store, its own
  /// sync and its own archive — it is a conversation whose other side is you,
  /// so every piece of machinery that already works on a conversation works on
  /// it unchanged: the outbox and its idempotency keys, the sealed archive,
  /// search, attachments, voice, deletion.
  ///
  /// It also gives multi-device sync for nothing. The server already treats a
  /// key request for your own account as "my other devices" (see
  /// `routes/devices.ts`), so writing to yourself seals a copy for each of
  /// them; on an account with a single device there is nobody to seal for and
  /// `MessagingService.sendPayload` reports that as delivered to nobody, which
  /// is the truth — the note is on the device it was written on.
  String? get savedId => accountId;

  bool isSaved(String conversationId) =>
      accountId != null && conversationId == accountId;

  /// Makes sure the Saved conversation exists, so both ways in open the same
  /// one rather than each making its own.
  ///
  /// Idempotent by construction: `upsertUser` is keyed on the account id, and
  /// there is exactly one of those.
  void ensureSaved({required String username, String? displayName}) {
    final me = accountId;
    if (me == null) return;
    _services.store.upsertUser(
      KnownUser(accountId: me, username: username, displayName: displayName),
    );
  }

  /// Puts a message from a chat into Saved.
  ///
  /// Returns why not, or null once the entry is filed. The caller shows
  /// "Saved" only on null — the confirmation has to follow the entry, not the
  /// tap, or it says something that may not be true.
  ///
  /// **A message under a disappearing timer is refused.** Copying it here would
  /// defeat the one guarantee the sender was given: that it goes away. The
  /// refusal is a case the screen turns into a sentence, not a silent no-op.
  Future<FailureKind?> saveToSaved(Message source) async {
    final me = accountId;
    if (me == null) return FailureKind.couldNotSave;
    if (source.expiresAt != null) return FailureKind.savedDisappearingRefused;
    if (source.kind == MessageKind.deleted || source.isNotice) {
      return FailureKind.savedNothingToSave;
    }

    final attachment = source.attachment;
    final clientId = _newClientId();
    // Filed locally first and marked `sending`: the entry exists on this device
    // from this moment, and what follows is only the copy for the other ones.
    _services.store.append(
      me,
      Message(
        id: clientId,
        clientId: clientId,
        body: source.body,
        sentAt: DateTime.now(),
        isMine: true,
        kind: source.kind,
        state: DeliveryState.sending,
        voiceDuration: source.voiceDuration,
        waveform: source.waveform,
        attachment: attachment,
        sticker: source.sticker,
        customEmoji: source.customEmoji,
      ),
    );
    notifyListeners();

    try {
      // The attachment's ciphertext has to outlive the ordinary retention, or
      // a saved photo becomes a broken placeholder on the second device. Done
      // before the payload goes out, so a blob that could not be kept is a
      // save that reports failure rather than one that quietly rots.
      if (attachment != null) {
        await _services.messaging.retainMedia(attachment.mediaId);
      }
      await _services.messaging.sendPayload(
        _selfUsernameOrThrow(),
        attachment == null
            ? MessagePayload.text(source.body, clientId: clientId)
            : MessagePayload.media(
                mediaId: attachment.mediaId,
                mediaKey: attachment.mediaKey,
                mediaType: attachment.mediaType,
                byteSize: attachment.byteSize,
                fileName: attachment.fileName,
                mediaToken: attachment.mediaToken,
                body: source.body,
                clientId: clientId,
              ),
      );
      _markSent(me, clientId, null);
      _persist();
      return null;
    } on Object {
      // The entry is on this device and the copy is not out yet. Marked so the
      // screen can say "waiting to sync" rather than "saved", and picked up by
      // the ordinary retry.
      _services.store.updateState(me, clientId, DeliveryState.queued);
      _persist();
      notifyListeners();
      return null;
    }
  }

  /// Pins an entry to the top of Saved, or lets it go.
  Future<void> togglePinned(String conversationId, Message target) async {
    final id = target.clientId ?? target.id;
    final message = _services.store
        .conversationWith(conversationId)
        ?.messages
        .where((m) => (m.clientId ?? m.id) == id)
        .firstOrNull;
    if (message == null) return;
    _services.store.replace(
      conversationId,
      message.id,
      message.copyWith(pinned: !message.pinned),
    );
    _persist();
    notifyListeners();
  }

  /// Everything in Saved that carries a file, newest first.
  List<Message> savedMedia() {
    final me = accountId;
    if (me == null) return const [];
    return [
      for (final message in _services.store.conversationWith(me)?.messages ?? const <Message>[])
        if (message.attachment != null) message,
    ].reversed.toList(growable: false);
  }

  /// This account's own username, as the Saved conversation records it.
  ///
  /// Read from the conversation rather than held in a field, so there is one
  /// answer rather than two that can drift — and it throws rather than
  /// guessing, because writing a saved entry to the wrong username would send
  /// it to somebody else.
  String _selfUsernameOrThrow() {
    final me = accountId;
    if (me == null) throw StateError('Saved has no account');
    final user = _services.store.conversationWith(me)?.user;
    if (user == null) throw StateError('Saved has no conversation yet');
    return user.username;
  }

  Future<void> refreshContacts() async {
    // Not inside the try below, and not conditional on it: the own picture has
    // nothing to do with the contact list, and a failed contacts read should
    // not also cost the user their avatar.
    detached(_restoreOwnAvatar());
    try {
      final response = await _services.api.contacts();
      final entries = response['contacts'] as List<dynamic>? ?? const [];
      _contacts = [
        for (final raw in entries) _toContact(raw as Map<String, dynamic>),
      ];
      // Knowing a contact is enough to show their name against an incoming
      // message, before any conversation exists.
      for (final raw in entries) {
        final contact = raw as Map<String, dynamic>;
        _services.store.upsertUser(
          KnownUser(
            accountId: contact['id'] as String,
            username: contact['username'] as String,
            displayName: contact['displayName'] as String?,
            avatarMediaId: contact['avatarMediaId'] as String?,
          ),
          // The contact list is the whole answer about these people, so a
          // name missing from it is a name they removed.
          authoritative: true,
        );
      }
      detached(_loadAvatars());
      _failure = null;
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
    }
    notifyListeners();
  }

  Contact _toContact(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return Contact(
      id: id,
      username: json['username'] as String,
      displayName: (json['displayName'] ?? json['username']) as String,
      // Null whenever their setting does not include us, which is the normal
      // answer and not a missing one.
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? '')?.toLocal(),
      avatarSeed: id.hashCode.abs(),
      avatarBytes: _avatarCache[id],
    );
  }

  Future<bool> addContact(String username) async {
    try {
      final added = await _services.api.addContact(username);
      _services.store.upsertUser(
        KnownUser(
          accountId: added['id'] as String,
          username: added['username'] as String,
          displayName: added['displayName'] as String?,
          avatarMediaId: added['avatarMediaId'] as String?,
        ),
      );
      await refreshContacts();
      return true;
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      return false;
    }
  }

  /// Ensures a conversation exists for [username], returning its account id.
  Future<String?> openConversation(String username) async {
    try {
      final user = await _services.api.lookup(username);
      final conversation = _services.store.upsertUser(
        KnownUser(
          accountId: user['id'] as String,
          username: user['username'] as String,
          displayName: user['displayName'] as String?,
          avatarMediaId: user['avatarMediaId'] as String?,
        ),
      );
      notifyListeners();
      detached(_loadAvatars());
      return conversation.id;
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      return null;
    }
  }

  /// Seals [text] for every device the recipient has and sends it.
  ///
  /// The message appears immediately as `sending` and only becomes `sent` once
  /// the server has taken it, so the UI never claims delivery it cannot back up.
  Future<void> send(
    String conversationId,
    String text, {
    Message? replyTo,
    List<CustomEmojiRef>? customEmoji,
  }) async {
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null || text.trim().isEmpty) return;

    final clientId = _newClientId();
    final timer = _effectiveTimer(conversation);
    final body = text.trim();
    _services.store.append(
      conversationId,
      Message(
        id: clientId,
        clientId: clientId,
        body: body,
        sentAt: DateTime.now(),
        isMine: true,
        state: DeliveryState.sending,
        // No expiry until the server has it. A send that fails leaves the
        // message on screen with a retry; a clock started here would delete
        // that retry out from under the person who was about to press it, and
        // take what they wrote with it.
        replyToId: replyTo?.clientId,
        replyPreview: replyTo == null ? null : previewOfMessage(replyTo),
        replySender: replyTo == null
            ? null
            : replyTo.isMine
                ? 'You'
                : replyTo.senderName ?? conversation.title,
        customEmoji: customEmoji,
      ),
    );
    notifyListeners();

    final payload = MessagePayload.text(
      body,
      customEmoji: customEmoji,
      groupKey: conversation.isGroup ? conversation.group!.groupKey : null,
      expiresInSeconds: timer?.inSeconds,
      // Carried so a retry — this one's or the transport's — is recognisable as
      // the same message rather than delivered twice.
      clientId: clientId,
      replyToId: replyTo?.clientId,
      replyPreview: replyTo == null ? null : previewOfMessage(replyTo),
      // From the recipient's point of view: a reply to their own message should
      // quote them by name, not tell them "You" wrote it.
      replySender: replyTo == null
          ? null
          : replyTo.isMine
              ? null
              : 'You',
    );

    try {
      if (conversation.isGroup) {
        await _services.messaging.sendPayloadToGroup(conversationId, payload);
      } else {
        await _services.messaging.sendPayload(conversation.user!.username, payload);
      }
      _markSent(conversationId, clientId, timer);
      _failure = null;
      _persist();
    } on Object catch (failure) {
      // Leaving it at `sending` would be a lie. Mark it and say why.
      _services.store.updateState(conversationId, clientId, DeliveryState.failed);
      _noteIdentityChange(failure);
      _failure = switch (failure) {
        // The one send failure the user can do something about, so it says
        // what rather than repeating the server's wording.
        ApiException(code: 'license_required') => const Failure(FailureKind.licenseRequired),
        // Refused on purpose: the key on the server is not the key that was
        // pinned. Sending anyway would seal it to whoever holds the new one.
        IdentityChangedException() => const Failure(FailureKind.identityChanged),
        ApiException(:final message) => Failure.server(message),
        _ => const Failure(FailureKind.couldNotSendMessage),
      };
    }
    notifyListeners();
  }

  // --- Groups ---------------------------------------------------------------

  /// Creates a group and tells the members about it.
  ///
  /// The name is sealed with a group key that the server never sees; the key
  /// itself reaches members inside end-to-end encrypted messages, the same way
  /// a profile key does.
  Future<String?> createGroup(String name, List<String> memberIds) async {
    try {
      final created = await _services.messaging.createGroup(name, memberIds);
      _services.store.upsertGroup(created);
      _persist();
      notifyListeners();
      return created.groupId;
    } on Object catch (failure) {
      _failure = Failure.of(failure, FailureKind.couldNotCreateGroup);
      notifyListeners();
      return null;
    }
  }

  /// Reads the groups this account belongs to, opening the names it has keys
  /// for. A group whose key has not arrived yet shows as "Group" until it does.
  Future<void> refreshGroups() async {
    try {
      for (final group in await _services.messaging.listGroups(_services.store)) {
        // The whole answer, so a picture or a description an admin removed
        // elsewhere is removed here too.
        _services.store.upsertGroup(group, authoritative: true);
      }
      _failure = null;
      notifyListeners();
      unawaited(_maintainGroupKeys());
      unawaited(_warmGroupAvatars());
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
    }
  }

  /// Both halves of group-key housekeeping, in one walk of the list.
  ///
  /// Hands the key to anyone waiting for it, and asks for it where this device
  /// is a member and does not have it. A group message carries the key too,
  /// but only once somebody speaks — and the device that needs asking most is
  /// the one that never joined: a second phone signing in to an account that
  /// is already in the group. Joining records a request; signing in does not.
  Future<void> _maintainGroupKeys() async {
    for (final conversation in _services.store.conversations()) {
      final group = conversation.group;
      if (group == null) continue;
      final key = group.groupKey;
      try {
        if (key == null) {
          await _services.messaging.requestGroupKey(group.groupId);
        } else {
          await _services.messaging.deliverGroupKeys(group.groupId, key);
        }
      } on Object {
        // One group that cannot be served is no reason to skip the rest.
        continue;
      }
    }
  }

  /// Joins a group from a link and opens it. Returns the group id, or null with
  /// [error] set.
  Future<String?> joinGroupByLink(String link) async {
    final invite = ChannelService.parseInviteLink(link);
    if (invite == null || invite.kind != InviteKind.group) {
      _failure = const Failure(FailureKind.notAGroupLink);
      notifyListeners();
      return null;
    }
    try {
      final group = await _services.messaging.joinGroupByCode(invite.code);
      _services.store.upsertGroup(group);
      await refreshGroups();
      return group.groupId;
    } on ApiException catch (failure) {
      _failure = failure.code == 'group_not_found'
          ? const Failure(FailureKind.groupNotFound)
          : Failure.server(failure.message);
      notifyListeners();
      return null;
    }
  }

  /// The link to share for a group, or null if this device does not know the
  /// code. Safe to post anywhere: it carries no key.
  String? groupInviteLink(String groupId) {
    final code = groupInfo(groupId)?.inviteCode;
    return code == null ? null : ChannelService.linkForGroup(code);
  }

  GroupInfo? groupInfo(String groupId) => _services.store.conversationWith(groupId)?.group;

  /// Everyone in a group, from the server.
  Future<List<GroupMember>> groupMembers(String groupId) =>
      _services.messaging.groupMembers(groupId);

  /// Shows this account out of a group.
  ///
  /// The conversation goes with it. A group chat nobody in it can write to any
  /// more is not a chat, and keeping it would leave a room on the list that
  /// cannot be entered — while the messages already in it stay readable
  /// nowhere, because they went with the archive entry.
  Future<bool> leaveGroup(String groupId) async {
    final me = accountId;
    if (me == null) return false;
    try {
      await _services.api.leaveGroup(groupId, me);
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      return false;
    }
    _services.store.removeConversation(groupId);
    _persist();
    notifyListeners();
    return true;
  }

  /// Removes somebody else. The server refuses unless this account is an admin
  /// of that group, so the check is not only in the screen.
  Future<bool> removeFromGroup(String groupId, String memberAccountId) async {
    try {
      await _services.api.leaveGroup(groupId, memberAccountId);
      return true;
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      return false;
    }
  }

  /// Renames a group, for everybody.
  ///
  /// The name is sealed with the group's key, so this changes a blob the server
  /// cannot read. It needs the key: a device that joined by a link and has not
  /// been sent the key yet cannot rename what it cannot name.
  Future<bool> renameGroup(String groupId, String name) async {
    final group = groupInfo(groupId);
    final key = group?.groupKey;
    if (group == null || key == null) {
      _failure = const Failure(FailureKind.groupKeyMissing);
      notifyListeners();
      return false;
    }
    try {
      await _services.messaging.renameGroup(groupId, name, key);
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      return false;
    }
    // Merged rather than rebuilt: a `GroupInfo` assembled from four fields
    // drops every other one, and since this group has a picture and a
    // description now, rebuilding it would make renaming a group quietly
    // forget both.
    _services.store.upsertGroup(group.merge(name: name));
    _persist();
    notifyListeners();
    return true;
  }

  /// Sets what a group says it is for, or clears it.
  ///
  /// Sealed with the group's key like the name, so this too changes a blob the
  /// server cannot read — and needs that key for the same reason.
  ///
  /// Admins only, and refused here as well as by the server: a screen that hid
  /// the field would still leave the call reachable.
  Future<bool> describeGroup(String groupId, String? description) async {
    final group = groupInfo(groupId);
    final key = group?.groupKey;
    if (group == null || key == null) {
      _failure = const Failure(FailureKind.groupKeyMissing);
      notifyListeners();
      return false;
    }
    if (!group.isAdmin) {
      _failure = const Failure(FailureKind.insufficientPermission);
      notifyListeners();
      return false;
    }
    final trimmed = description?.trim();
    try {
      await _services.messaging.describeGroup(groupId, trimmed, key);
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      return false;
    }
    // Authoritative, because this *is* the whole truth about the group now.
    // Without it the store would merge the cleared description against what it
    // already held and put the old text straight back — a removal that undoes
    // itself on the way to the screen.
    _services.store.upsertGroup(
      trimmed == null || trimmed.isEmpty
          ? group.merge(clearDescription: true)
          : group.merge(description: trimmed),
      authoritative: trimmed == null || trimmed.isEmpty,
    );
    _persist();
    notifyListeners();
    return true;
  }

  /// Gives a group a picture. Returns false with a reason on the failure.
  Future<bool> setGroupAvatar(String groupId, Uint8List picked) async {
    final group = groupInfo(groupId);
    if (group == null || !group.isAdmin) {
      _failure = const Failure(FailureKind.insufficientPermission);
      notifyListeners();
      return false;
    }
    try {
      final mediaId = await _services.messaging.setGroupAvatar(groupId, picked);
      _services.store.upsertGroup(
        group.merge(avatarMediaId: mediaId, avatarUpdatedAt: DateTime.now()),
      );
      // The old picture is still in this cache under the old id; the new one
      // is a new id, so nothing has to be evicted for the change to show.
      _persist();
      notifyListeners();
      return true;
    } on GroupAvatarRejected catch (rejected) {
      _failure = rejected.failure;
      notifyListeners();
      return false;
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      return false;
    } on Object {
      _failure = const Failure(FailureKind.couldNotSetPicture);
      notifyListeners();
      return false;
    }
  }

  /// Takes a group's picture away.
  Future<bool> clearGroupAvatar(String groupId) async {
    final group = groupInfo(groupId);
    if (group == null || !group.isAdmin) {
      _failure = const Failure(FailureKind.insufficientPermission);
      notifyListeners();
      return false;
    }
    try {
      await _services.messaging.clearGroupAvatar(groupId);
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      return false;
    }
    // Authoritative for the same reason as clearing a description: a merge
    // against what the store already has would restore the picture that was
    // just removed.
    _services.store.upsertGroup(group.merge(clearAvatar: true), authoritative: true);
    _groupAvatarCache.remove(groupId);
    _persist();
    notifyListeners();
    return true;
  }

  /// The group's picture, fetched once and kept for as long as the app runs.
  ///
  /// Keyed on the **media id** rather than the group, so replacing a picture
  /// is a different key and nothing has to be invalidated by hand. Per account
  /// like every other cache here: it lives on this controller, and a controller
  /// belongs to one signed-in account.
  Future<Uint8List?> groupAvatar(String groupId) async {
    final mediaId = groupInfo(groupId)?.avatarMediaId;
    if (mediaId == null) return null;
    final cached = _groupAvatarCache[groupId];
    if (cached != null && cached.$1 == mediaId) return cached.$2;

    final account = accountId;
    final bytes = await _services.messaging.groupAvatarBytes(mediaId);
    // Somebody else may be signed in by the time this answers, and their
    // caches are not this one's to fill.
    if (accountId != account) return null;
    if (bytes != null) {
      _groupAvatarCache[groupId] = (mediaId, bytes);
      notifyListeners();
    }
    return bytes;
  }

  /// Fetches the pictures of groups that have one and this run has not seen.
  ///
  /// Once per group per run, after a listing rather than while a chat list is
  /// being drawn: a screen that fetched as it scrolled would ask again every
  /// time a row came back into view. Failures are silent — a group with no
  /// picture on screen is the same thing to a reader as a group with none.
  Future<void> _warmGroupAvatars() async {
    for (final conversation in _services.store.conversations()) {
      final group = conversation.group;
      if (group?.avatarMediaId == null) continue;
      if (_groupAvatarCache[group!.groupId]?.$1 == group.avatarMediaId) continue;
      await groupAvatar(group.groupId);
    }
  }

  /// Deletes a group for everyone in it. Admins only, enforced by the server.
  Future<bool> deleteGroup(String groupId) async {
    try {
      await _services.api.deleteGroup(groupId);
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      return false;
    }
    _services.store.removeConversation(groupId);
    _persist();
    notifyListeners();
    return true;
  }

  /// Sends a file. Its metadata is stripped and it is sealed under its own key
  /// before it leaves the device; the returned report says what was removed so
  /// the UI can show it rather than leaving the user to assume.
  Future<ScrubReport?> sendAttachment(
    String conversationId, {
    required Uint8List file,
    String? fileName,
    String caption = '',
  }) async {
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return null;

    final messageId = DateTime.now().microsecondsSinceEpoch.toString();
    final timer = _effectiveTimer(conversation);
    final placeholder = Message(
      id: messageId,
      clientId: messageId,
      body: caption,
      sentAt: DateTime.now(),
      isMine: true,
      kind: MessageKind.file,
      state: DeliveryState.sending,
      // No expiry yet, as for text and voice: a file queued with no signal must
      // not run its clock down while it waits to go anywhere.
    );
    _services.store.append(conversationId, placeholder);
    notifyListeners();

    try {
      // The file is uploaded once either way; what differs is whether the
      // pointer and its key go to one account or to every member's devices.
      final report = conversation.isGroup
          ? await _services.messaging.sendGroupAttachment(
              conversationId,
              file: file,
              fileName: fileName,
              groupKey: conversation.group?.groupKey,
              expiresInSeconds: timer?.inSeconds,
              clientId: messageId,
            )
          : await _services.messaging.sendAttachment(
              conversation.user!.username,
              file: file,
              fileName: fileName,
              expiresInSeconds: timer?.inSeconds,
              clientId: messageId,
            );
      // The placeholder was drawn before the file had a name on the server.
      // Now it has one: replace it with the message the recipient will see, so
      // the sender's own bubble shows the file rather than an empty box.
      _services.store.replace(
        conversationId,
        messageId,
        Message(
          id: messageId,
          clientId: messageId,
          body: caption,
          sentAt: placeholder.sentAt,
          isMine: true,
          kind: _kindFor(report.mediaType),
          state: DeliveryState.sent,
          // The clock starts now, when the server took it — the same moment the
          // recipient's starts, from their own side of it. Without this a photo
          // sent into a disappearing chat stayed on the sender's device
          // forever: the bubble vanished from theirs and nowhere else.
          expiresAt: timer == null ? null : DateTime.now().add(timer),
          attachment: Attachment(
            mediaId: report.mediaId,
            mediaKey: report.mediaKey,
            mediaToken: report.mediaToken,
            mediaType: report.mediaType,
            byteSize: report.byteSize,
            fileName: report.fileName,
          ),
        ),
      );
      _failure = null;
      _persist();
      notifyListeners();
      return report.report;
    } on Object catch (failure) {
      _noteIdentityChange(failure);
      _failure = switch (failure) {
        ApiException(:final message) => Failure.server(message),
        IdentityChangedException() => const Failure(FailureKind.identityChanged),
        _ => const Failure(FailureKind.couldNotSendFile),
      };
      notifyListeners();
      return null;
    }
  }

  /// Downloads and decrypts an attachment, keeping it for as long as the screen
  /// is open. Nothing is written to disk in the clear.
  final Map<String, Uint8List> _attachmentCache = {};

  Future<Uint8List?> attachmentBytes(Attachment attachment) async {
    final cached = _attachmentCache[attachment.mediaId];
    if (cached != null) return cached;
    try {
      final bytes = await _services.messaging.openAttachment(
        MessagePayload.media(
          mediaId: attachment.mediaId,
          mediaKey: attachment.mediaKey,
          // Without this the server has no reason to hand the bytes over, and
          // the bubble sits on a spinner that never resolves.
          mediaToken: attachment.mediaToken,
          mediaType: attachment.mediaType,
          byteSize: attachment.byteSize,
          fileName: attachment.fileName,
        ),
      );
      return _attachmentCache[attachment.mediaId] = bytes;
    } on Object catch (failure) {
      _failure = Failure.of(failure, FailureKind.couldNotOpenFile);
      notifyListeners();
      return null;
    }
  }

  // --- Replies and reactions ------------------------------------------------

  /// The emoji offered on a long press. Six, because a picker of hundreds turns
  /// a one-tap gesture into a decision.
  static const List<String> quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  /// Reacts to a message, or takes the reaction back when it is already yours.
  ///
  /// Applied here first and sent after: a reaction that waits for the network
  /// to round-trip feels broken, and the worst case is a reaction the other
  /// side never hears about — which is what the next one will fix.
  /// Reacts to a message, or takes the reaction back when it is already yours.
  ///
  /// [sticker] makes it a custom-emoji reaction. [emoji] is still required and
  /// still travels: it is the character anybody without the pack sees, so a
  /// custom reaction never arrives as nothing.
  Future<void> react(
    String conversationId,
    Message target,
    String emoji, {
    StickerRef? sticker,
  }) async {
    final me = accountId;
    final clientId = target.clientId;
    if (me == null || clientId == null) return;

    // Pressing the same one again takes it back — and "the same one" has to
    // mean the same picture too, or two different custom emoji sharing a
    // fallback character would cancel each other.
    final same = target.reactions[me] == emoji && target.reactionStickers[me] == sticker;
    final chosen = same ? '' : emoji;
    _services.store.applyReaction(
      conversationId: conversationId,
      targetClientId: clientId,
      accountId: me,
      emoji: chosen,
      sticker: chosen.isEmpty ? null : sticker,
    );
    _persist();
    notifyListeners();

    final payload = MessagePayload.reaction(
      reactionTo: clientId,
      reactionEmoji: chosen,
      stickerItemId: chosen.isEmpty ? null : sticker?.itemId,
      stickerPackId: chosen.isEmpty ? null : sticker?.packId,
      stickerMediaId: chosen.isEmpty ? null : sticker?.mediaId,
    );
    final conversation = _services.store.conversationWith(conversationId);
    try {
      if (conversation?.isGroup ?? false) {
        await _services.messaging.sendPayloadToGroup(conversationId, payload);
      } else {
        final username = conversation?.user?.username;
        if (username != null) await _services.messaging.sendPayload(username, payload);
      }
    } on Object {
      // Left on screen deliberately: taking it back because the network failed
      // would be a second surprise on top of the first.
    }
  }

  // --- What this device is keeping ------------------------------------------

  /// What the history costs this device: the sealed blob, and what is in it.
  Future<({int sealedBytes, int messages, int conversations})> historySize() async {
    final all = _services.store.conversations();
    return (
      sealedBytes: await _services.archive.sizeInBytes(),
      messages: all.fold<int>(0, (sum, c) => sum + c.messages.length),
      conversations: all.length,
    );
  }

  /// Erases the conversation history on this device, and nothing else.
  ///
  /// Not the duress wipe, which destroys the identity too and asks the server
  /// to forget the account. This keeps the account, the keys and the sessions:
  /// messages already sent still arrive, the people already talked to can
  /// still write, and what was said before is gone from this phone.
  ///
  /// It cannot reach the other side's copy, and it cannot reach a backup
  /// already on the server. The screen offering it says both.
  Future<void> clearHistory() async {
    _outbox.clear();
    _attachmentCache.clear();
    _services.store.clear();
    await _services.archive.clear();
    _failure = null;
    notifyListeners();
  }

  /// Keeps a conversation at the top of the list, or lets it go.
  ///
  /// Local to this device and never sent. The other side is not told, because
  /// which chats someone keeps at the top says something about them and is
  /// nobody else's business — not the person on the other end, and least of
  /// all the server. It survives a reinstall only through a backup, which is
  /// where the archive it lives in already goes.
  Future<void> togglePin(String conversationId) async {
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return;
    if (!_services.store.setPinned(conversationId, pinned: !conversation.pinned)) {
      return;
    }
    _persist();
    notifyListeners();
  }

  bool isPinned(String conversationId) =>
      _services.store.conversationWith(conversationId)?.pinned ?? false;

  /// Every message that matches [query], across every conversation.
  ///
  /// Runs on this device, over what it has already decrypted. There is nowhere
  /// else it could run — the server holds ciphertext it cannot read — and
  /// sending a query there would tell it what someone is looking for.
  List<SearchHit> searchMessages(String query) =>
      MessageSearch.run(_services.store.conversations(), query);

  // --- Taking a message back ------------------------------------------------

  /// Removes a message from this device only.
  ///
  /// Available on anything, including what somebody else wrote, because this
  /// is housekeeping on one screen and nobody else is affected by it.
  Future<void> deleteForMe(String conversationId, Message target) async {
    final clientId = target.clientId;
    if (clientId == null) return;
    if (!_services.store.deleteMessage(
      conversationId: conversationId,
      clientId: clientId,
      tombstone: false,
    )) {
      return;
    }
    _forgetAttachment(target);
    _persist();
    notifyListeners();
  }

  /// Asks every device that has this message to forget it, and forgets it here.
  ///
  /// Only for messages this account sent: what someone else wrote is theirs,
  /// and a protocol that let anyone delete anyone's messages would be a way to
  /// erase a conversation you were losing.
  ///
  /// Removed here first, and the request sent after. A failed send leaves a
  /// message gone on this device and present on theirs, which is the right way
  /// round to fail: the alternative is a message the user was told is gone
  /// still sitting on their own screen.
  Future<void> deleteForEveryone(String conversationId, Message target) async {
    final clientId = target.clientId;
    if (!target.isMine || clientId == null) return;

    _services.store.deleteMessage(
      conversationId: conversationId,
      clientId: clientId,
      tombstone: true,
    );
    _forgetAttachment(target);
    // Anything still queued for this message should not go out now.
    _outbox.removeWhere((entry) => entry.clientId == clientId);
    _persist();
    notifyListeners();

    final payload = MessagePayload.deletion(clientId);
    final conversation = _services.store.conversationWith(conversationId);
    try {
      if (conversation?.isGroup ?? false) {
        await _services.messaging.sendPayloadToGroup(conversationId, payload);
      } else {
        final username = conversation?.user?.username;
        if (username != null) await _services.messaging.sendPayload(username, payload);
      }
    } on Object catch (failure) {
      _noteIdentityChange(failure);
      _failure = const Failure(FailureKind.deletedHereOnly);
      notifyListeners();
    }
  }

  /// Applies a deletion somebody asked for.
  ///
  /// Checked on the way in as well as on the way out. Refusing to *send* a
  /// deletion for someone else's message keeps this app honest; it does
  /// nothing about a modified one, and a client that could delete anything in
  /// anyone's transcript is a client that can rewrite an argument it is
  /// losing. So a request may only remove a message its own sender wrote —
  /// except from this account's own other devices, which may only remove this
  /// account's own.
  void _applyDeletion(
    String conversationId,
    MessagePayload payload, {
    required String byAccountId,
    required bool fromOwnDevice,
  }) {
    final clientId = payload.deleteTo;
    if (clientId == null || clientId.isEmpty) return;
    // Read before deleting: what has to be dropped from the decrypted cache is
    // the media id, and after the delete there is nothing left to ask.
    final target = _services.store
        .conversationWith(conversationId)
        ?.messages
        .where((m) => m.clientId == clientId)
        .firstOrNull;
    if (target == null) return;
    if (fromOwnDevice) {
      if (!target.isMine) return;
    } else {
      if (target.isMine) return;
      // Null on anything filed before this field existed. In a direct chat
      // there is only one other person, so nothing is lost; in a group it
      // means an old message can be taken back by any member, which is why the
      // field is written from now on.
      if (target.senderAccountId != null && target.senderAccountId != byAccountId) return;
    }
    final changed = _services.store.deleteMessage(
      conversationId: conversationId,
      clientId: clientId,
      tombstone: true,
    );
    if (!changed) return;
    _forgetAttachment(target);
    _persist();
    notifyListeners();
  }

  /// Drops the decrypted bytes of a deleted message's file.
  ///
  /// The archive is sealed and the ciphertext on the server expires on its own,
  /// but this cache holds the plaintext of anything opened this session. A
  /// deletion that left it there would leave the file one tap from being shown
  /// again.
  void _forgetAttachment(Message message) {
    final mediaId = message.attachment?.mediaId;
    if (mediaId != null) _attachmentCache.remove(mediaId);
  }

  void _applyReaction(String conversationId, String fromAccountId, MessagePayload payload) {
    final changed = _services.store.applyReaction(
      conversationId: conversationId,
      targetClientId: payload.reactionTo!,
      accountId: fromAccountId,
      emoji: payload.reactionEmoji ?? '',
      sticker: _stickerIn(payload),
    );
    if (changed) {
      _persist();
      notifyListeners();
    }
  }

  /// The custom item a payload names, or null.
  ///
  /// Shared by the sticker path and the reaction path because both answer the
  /// same question from the same three fields, and a second copy would be a
  /// second place to forget the null check.
  static StickerRef? _stickerIn(MessagePayload payload) {
    final itemId = payload.stickerItemId;
    final mediaId = payload.stickerMediaId;
    if (itemId == null || mediaId == null) return null;
    return StickerRef(
      itemId: itemId,
      packId: payload.stickerPackId ?? '',
      mediaId: mediaId,
    );
  }

  /// Sends a sticker.
  ///
  /// Shaped exactly like [send] on purpose: it is a message, it queues while
  /// offline, it takes a reply and the chat's disappearing timer, and it fails
  /// the same way with the same words. The only thing that differs is what the
  /// bubble draws.
  ///
  /// [fallback] is the character the sticker stands for and it is not optional:
  /// it is what the other side shows if their build predates stickers, if they
  /// do not have the pack, or if the pack has since been deleted.
  Future<void> sendSticker(
    String conversationId, {
    required String itemId,
    required String packId,
    required String mediaId,
    required String fallback,
    Message? replyTo,
  }) async {
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return;

    final clientId = _newClientId();
    final timer = _effectiveTimer(conversation);
    _services.store.append(
      conversationId,
      Message(
        id: clientId,
        clientId: clientId,
        body: fallback,
        kind: MessageKind.sticker,
        sticker: StickerRef(itemId: itemId, packId: packId, mediaId: mediaId),
        sentAt: DateTime.now(),
        isMine: true,
        state: DeliveryState.sending,
        replyToId: replyTo?.clientId,
        replyPreview: replyTo == null ? null : previewOfMessage(replyTo),
        replySender: replyTo == null
            ? null
            : replyTo.isMine
                ? 'You'
                : replyTo.senderName ?? conversation.title,
      ),
    );
    notifyListeners();

    final payload = MessagePayload.sticker(
      stickerItemId: itemId,
      stickerPackId: packId,
      stickerMediaId: mediaId,
      body: fallback,
      groupKey: conversation.isGroup ? conversation.group!.groupKey : null,
      expiresInSeconds: timer?.inSeconds,
      clientId: clientId,
      replyToId: replyTo?.clientId,
      replyPreview: replyTo == null ? null : previewOfMessage(replyTo),
      replySender: replyTo == null
          ? null
          : replyTo.isMine
              ? null
              : 'You',
    );

    try {
      if (conversation.isGroup) {
        await _services.messaging.sendPayloadToGroup(conversationId, payload);
      } else {
        await _services.messaging.sendPayload(conversation.user!.username, payload);
      }
      _markSent(conversationId, clientId, timer);
      _failure = null;
      _persist();
    } on Object catch (failure) {
      _services.store.updateState(conversationId, clientId, DeliveryState.failed);
      _noteIdentityChange(failure);
      _failure = switch (failure) {
        ApiException(code: 'license_required') => const Failure(FailureKind.licenseRequired),
        IdentityChangedException() => const Failure(FailureKind.identityChanged),
        ApiException(:final message) => Failure.server(message),
        _ => const Failure(FailureKind.couldNotSendMessage),
      };
    }
    notifyListeners();
  }

  /// A short quote of [message], as it travels with a reply.
  ///
  /// Sent rather than looked up on the other side, because the original may
  /// have been deleted there or expired on their timer.
  static String previewOfMessage(Message message) {
    if (message.body.isNotEmpty) {
      return message.body.length <= 120 ? message.body : '${message.body.substring(0, 117)}…';
    }
    return switch (message.kind) {
      MessageKind.voice => 'Voice message',
      MessageKind.photo => 'Photo',
      MessageKind.video => 'Video',
      MessageKind.file => message.attachment?.fileName ?? 'File',
      // Never reached in practice: a sticker's body is the character it stands
      // for, so the branch above returns that — which is a better quote than
      // the word "Sticker" anyway, because it is the thing that was sent.
      MessageKind.sticker => 'Sticker',
      MessageKind.deleted => 'Deleted message',
      // Never reached: a notice always has a body, and nothing replies to one.
      MessageKind.notice || MessageKind.undelivered => '',
      MessageKind.text => '',
    };
  }

  // --- Receipts and typing --------------------------------------------------

  /// How long a typing notice is believed for, and how often one is sent.
  ///
  /// Longer than the send interval so the indicator does not flicker between
  /// notices, short enough that it disappears soon after someone stops.
  static const Duration typingLifetime = Duration(seconds: 6);
  static const Duration typingInterval = Duration(seconds: 3);

  /// Reads the account's privacy settings, so the toggles reflect the server
  /// rather than a default this device guessed.
  /// Blocks an account and drops the conversation from this device.
  ///
  /// The server stops delivering what they send and tells them nothing. Keeping
  /// the chat on screen afterwards would be odd — it can never grow again — so
  /// it goes with them, and the archive is rewritten without it.
  Future<bool> block(String accountId) async {
    try {
      await _services.api.block(accountId);
    } on Object {
      return false;
    }
    _services.store.removeConversation(accountId);
    _persist();
    notifyListeners();
    return true;
  }

  Future<void> loadPrivacy() async {
    try {
      final me = await _services.api.me();
      applyPrivacy(me['privacy'] as Map<String, dynamic>? ?? const {});
    } on Object {
      // Keep whatever is on screen; the settings screen shows the error.
    }
  }

  /// Takes the privacy object from a read someone else already did.
  ///
  /// The settings screen needs the security half of the same account object,
  /// and asking for it twice spends two of a rate-limited budget on one screen.
  void applyPrivacy(Map<String, dynamic> privacy) {
    _readReceipts = privacy['readReceipts'] as bool? ?? true;
    _typingIndicators = privacy['typingIndicators'] as bool? ?? true;
    final seconds = privacy['disappearAfterSeconds'] as int?;
    _defaultDisappearAfter = seconds == null || seconds <= 0
        ? null
        : Duration(seconds: seconds > maxDisappearSeconds ? maxDisappearSeconds : seconds);
    notifyListeners();
  }

  /// Sets the account-wide default.
  ///
  /// It governs chats that follow it — new ones, and any whose own setting was
  /// cleared — and reaches no further. A chat somebody decided by hand keeps
  /// what they decided until they say otherwise, which is what
  /// [applyDefaultToFollowingChats] is for.
  ///
  /// Saved is not a chat for this purpose and is never touched.
  Future<bool> setDefaultDisappearAfter(Duration? timer) async {
    final capped = timer == null || timer.inSeconds <= maxDisappearSeconds
        ? timer
        : const Duration(seconds: maxDisappearSeconds);
    if (capped == _defaultDisappearAfter) return true;

    final before = _defaultDisappearAfter;
    _defaultDisappearAfter = capped;
    notifyListeners();
    try {
      await _services.api.updatePrivacy({'disappearAfterSeconds': capped?.inSeconds});
    } on Object {
      // Put back what it was: a default that did not reach the account is a
      // default the next device will not have, and showing it as saved here
      // would be the lie this codebase keeps refusing to tell.
      _defaultDisappearAfter = before;
      _failure = const Failure(FailureKind.couldNotSave);
      notifyListeners();
      return false;
    }
    // Chats that follow the account now expire differently, and the ones that
    // are open should say so without waiting for a message.
    notifyListeners();
    return true;
  }

  /// Every chat that would change if the default were applied to it.
  ///
  /// Split into the ones that follow already — which change for free — and the
  /// ones with their own answer, which are only touched when somebody says so.
  /// The settings screen shows both lists before it asks.
  ({List<String> following, List<String> exceptions}) chatsAffectedByDefault() {
    final following = <String>[];
    final exceptions = <String>[];
    for (final conversation in _services.store.conversations()) {
      if (isSaved(conversation.id)) continue;
      if (!_mayChangeDisappearAfter(conversation.id)) continue;
      if (conversation.timer.explicit) {
        if (conversation.timer.after != _defaultDisappearAfter) exceptions.add(conversation.id);
      } else {
        following.add(conversation.id);
      }
    }
    return (following: following, exceptions: exceptions);
  }

  /// Chats whose own setting differs from the account default.
  ///
  /// What "Manage exceptions" lists. Deliberately not "every chat that was
  /// ever set by hand": a chat set to an hour while the account says an hour
  /// is not an exception to anything, and listing it would ask somebody to
  /// tidy up something that is already tidy.
  List<String> timerExceptions() => [
        for (final conversation in _services.store.conversations())
          if (!isSaved(conversation.id) &&
              conversation.timer.isExceptionTo(_defaultDisappearAfter))
            conversation.id,
      ];

  /// Applies the account default to chats, and announces each change.
  ///
  /// [includeExceptions] is the confirmed version: without it, chats with
  /// their own setting are left exactly as they are. Groups this account may
  /// not change are skipped and returned, so the screen can name them rather
  /// than pretending they were done.
  Future<({int changed, List<String> skipped})> applyDefaultToFollowingChats({
    bool includeExceptions = false,
  }) async {
    final skipped = <String>[];
    final targets = <String>[];
    for (final conversation in _services.store.conversations()) {
      if (isSaved(conversation.id)) continue;
      if (conversation.timer.explicit && !includeExceptions) continue;
      if (!_mayChangeDisappearAfter(conversation.id)) {
        // Only worth naming when it would actually have changed.
        if (_effectiveTimer(conversation) != _defaultDisappearAfter) skipped.add(conversation.id);
        continue;
      }
      targets.add(conversation.id);
    }

    var changed = 0;
    for (final id in targets) {
      final conversation = _services.store.conversationWith(id);
      if (conversation == null) continue;
      if (_effectiveTimer(conversation) == _defaultDisappearAfter &&
          !conversation.timer.explicit) {
        continue;
      }
      if (await setChatTimer(id, const ChatTimer.followDefault())) changed += 1;
    }
    return (changed: changed, skipped: skipped);
  }

  Future<void> setReadReceipts(bool enabled) async {
    _readReceipts = enabled;
    notifyListeners();
    await _services.api.updatePrivacy({'readReceipts': enabled});
  }

  Future<void> setTypingIndicators(bool enabled) async {
    _typingIndicators = enabled;
    if (!enabled) _typingSentAt.clear();
    notifyListeners();
    await _services.api.updatePrivacy({'typingIndicators': enabled});
  }

  /// Clears typing indicators that have run out, and redraws only if one had.
  void _fadeTyping() {
    final now = DateTime.now();
    var changed = false;
    for (final conversation in _services.store.conversations()) {
      if (conversation.typingUntil == null) continue;
      if (conversation.isTypingAt(now)) continue;
      _services.store.setTyping(conversation.id, null);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Says "typing", at most once every [typingInterval].
  ///
  /// Throttled rather than debounced: the point is to keep the indicator alive
  /// while someone writes, and a debounce would only tell the other side once
  /// they stopped.
  void typing(String conversationId) {
    if (!_typingIndicators) return;
    final conversation = _services.store.conversationWith(conversationId);
    final username = conversation?.user?.username;
    // 1:1 only for now: a group typing notice needs a fan-out of its own, and
    // one that says "someone" is worse than none.
    if (username == null) return;

    final last = _typingSentAt[conversationId];
    final now = DateTime.now();
    if (last != null && now.difference(last) < typingInterval) return;
    _typingSentAt[conversationId] = now;
    unawaited(_services.messaging.sendTyping(username).catchError((_) {}));
  }

  /// Tells the sender their messages arrived. Called after a batch is filed.
  ///
  /// Always to the author, never to the group: in a group, who has read what is
  /// between the reader and whoever wrote it, and telling everybody would also
  /// cost a sealed copy per member device to say so.
  Future<void> _sendDeliveryReceipts(
    Map<(String, String?), List<String>> byAuthor,
  ) async {
    if (!_readReceipts) return;
    for (final entry in byAuthor.entries) {
      final (senderAccountId, groupId) = entry.key;
      final username = _services.store.conversationWith(senderAccountId)?.user?.username;
      if (username == null) continue;
      try {
        await _services.messaging.sendReceipt(
          username: username,
          clientIds: entry.value,
          kind: 'delivered',
          groupId: groupId,
        );
      } on Object {
        // A receipt that did not go out is not worth telling anyone about; the
        // next message from them carries the same information soon enough.
        continue;
      }
    }
  }

  /// Files a receipt that arrived: moves my own messages forward a state.
  ///
  /// [conversationId] is who it came from; a receipt about group messages names
  /// the group itself, because the envelope only says who sent it.
  void _applyReceipt(String senderAccountId, MessagePayload payload) {
    final state = payload.receiptKind == 'read' ? DeliveryState.read : DeliveryState.delivered;
    final ids = (payload.receiptIds ?? const []).toSet();
    final groupId = payload.receiptGroupId;

    final changed = groupId == null
        ? _services.store.markStateByClientIds(senderAccountId, ids, state)
        : _services.store.recordGroupReceipt(
            conversationId: groupId,
            clientIds: ids,
            accountId: senderAccountId,
            state: state,
            otherMemberCount: _otherMemberCount(groupId),
          );
    if (changed > 0) _persist();
  }

  /// Everyone in the group except this account.
  ///
  /// Zero when the count is not known yet, which the store reads as "do not
  /// claim everyone has seen it" rather than as an empty group.
  int _otherMemberCount(String groupId) {
    final count = _services.store.conversationWith(groupId)?.group?.memberCount ?? 0;
    return count > 0 ? count - 1 : 0;
  }

  void _applyTyping(String conversationId, MessagePayload payload) {
    final sentAt = DateTime.fromMillisecondsSinceEpoch(payload.typingAt ?? 0);
    // A notice that sat in a queue while the phone was off says nothing about
    // now, so it is dropped rather than shown.
    if (DateTime.now().difference(sentAt).abs() > typingLifetime) return;
    _services.store.setTyping(conversationId, sentAt.add(typingLifetime));
  }

  // --- Voice messages -------------------------------------------------------

  /// How many voice messages are waiting for a network.
  int get queuedCount => _outbox.length;

  /// Whether this message is still waiting in the queue rather than sent.
  ///
  /// The chat needs it to know what to offer on a long press: a recording that
  /// never went out can be tried again or dropped, and deleting it has to take
  /// the queue entry with it — a bubble removed on its own leaves the message
  /// to arrive later from a queue the person thought they had emptied.
  bool isQueued(String clientId) =>
      _outbox.any((pending) => pending.clientId == clientId);

  /// Seals [recording] and puts it on the wire, or in the queue if that fails.
  ///
  /// Sealing happens first and in memory: by the time anything can go wrong,
  /// the only copy that could be persisted is already ciphertext. The bubble
  /// appears immediately, so a slow network shows as a state on a message
  /// rather than as nothing happening.
  Future<void> sendVoice(String conversationId, VoiceRecording recording) async {
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return;

    final clientId = _newClientId();
    final sealed = await AttachmentCipher.seal(
      recording.bytes,
      declaredType: recording.mediaType,
    );
    final timer = _effectiveTimer(conversation);

    _services.store.append(
      conversationId,
      Message(
        id: clientId,
        clientId: clientId,
        body: '',
        sentAt: DateTime.now(),
        isMine: true,
        kind: MessageKind.voice,
        state: DeliveryState.sending,
        voiceDuration: recording.duration,
        waveform: recording.waveform,
        // No expiry yet, even where the chat has a timer. A recording made with
        // no signal waits in the outbox, and a clock started here would run
        // while it waited: the bubble would vanish from the sender's own chat
        // before the message had been anywhere, and then send regardless. The
        // clock starts when it reaches the server — which is also when the
        // recipient's starts, from their own side of the same moment.
      ),
    );
    notifyListeners();

    _outbox.add(
      PendingSend(
        clientId: clientId,
        conversationId: conversationId,
        isGroup: conversation.isGroup,
        username: conversation.user?.username,
        groupKey: conversation.group?.groupKey,
        mediaType: recording.mediaType,
        sealedBytes: sealed.bytes,
        mediaKey: base64Encode(sealed.key),
        plainLength: sealed.plainLength,
        durationMs: recording.duration.inMilliseconds,
        waveform: recording.waveform,
        expiresInSeconds: timer?.inSeconds,
      ),
    );
    _persist();
    await flushOutbox();
  }

  /// Queues photos, in the order they were chosen.
  ///
  /// Deliberately the *same* road a voice message takes rather than the one
  /// [sendAttachment] takes, and the difference is the part the user sees. The
  /// outbox seals first, persists the ciphertext, uploads once and remembers
  /// the upload: a send that fails can be retried without uploading again and
  /// — the thing that actually matters — **without a second bubble**, because
  /// the queue is keyed on the client id the server also treats as the
  /// idempotency key. `sendAttachment` has none of that; a failed photo there
  /// sat on "sending" forever with nothing to do about it.
  ///
  /// The caption goes on the first picture only. A set of six photos with the
  /// same sentence repeated under each is not what anybody means by "add a
  /// caption", and the alternative — a separate text message — arrives out of
  /// order often enough to be worse.
  ///
  /// [account] is the account these photos were chosen in. A picker is open for
  /// as long as somebody takes to choose, which is ample time to switch
  /// accounts behind it; the check means the photos are dropped rather than
  /// filed into whoever is logged in when the sheet closes.
  Future<void> sendPhotos(
    String conversationId,
    List<PreparedPhoto> photos, {
    String caption = '',
    String? account,
  }) async {
    if (photos.isEmpty) return;
    if (account != null && account != accountId) return;
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return;

    final timer = _effectiveTimer(conversation);

    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final clientId = _newClientId();
      final sealed = await AttachmentCipher.seal(photo.bytes, declaredType: _photoType);
      // Re-checked after every await, not once at the top: sealing several
      // photos takes real time on a phone, and the switch can land in the
      // middle of it.
      if (account != null && account != accountId) return;

      _services.store.append(
        conversationId,
        Message(
          id: clientId,
          clientId: clientId,
          body: i == 0 ? caption : '',
          sentAt: DateTime.now(),
          isMine: true,
          kind: MessageKind.photo,
          state: DeliveryState.sending,
          // No expiry until it has been somewhere. Same reason as voice: a
          // photo queued with no signal must not run its clock down while it
          // waits, disappear from the sender's own chat, and then send.
        ),
      );

      _outbox.add(
        PendingSend(
          clientId: clientId,
          conversationId: conversationId,
          isGroup: conversation.isGroup,
          username: conversation.user?.username,
          groupKey: conversation.group?.groupKey,
          mediaType: _photoType,
          sealedBytes: sealed.bytes,
          mediaKey: base64Encode(sealed.key),
          plainLength: sealed.plainLength,
          durationMs: 0,
          waveform: const [],
          fileName: photo.fileName,
          caption: i == 0 ? caption : '',
          expiresInSeconds: timer?.inSeconds,
        ),
      );
    }

    _persist();
    notifyListeners();
    await flushOutbox();
  }

  /// What [PhotoImage] produces, always. Named here because the outbox entry
  /// and the sealed payload have to agree with the bubble about what it is.
  static const String _photoType = 'image/jpeg';

  /// Retries one message the user asked to retry.
  Future<void> retry(String clientId) async {
    final index = _outbox.indexWhere((pending) => pending.clientId == clientId);
    if (index == -1) return;
    _setVoiceState(_outbox[index].conversationId, clientId, DeliveryState.sending);
    notifyListeners();
    await flushOutbox();
  }

  /// Drops a queued message the user gave up on, bubble and all.
  void discard(String clientId) {
    final index = _outbox.indexWhere((pending) => pending.clientId == clientId);
    if (index == -1) return;
    final pending = _outbox.removeAt(index);
    _services.store
        .conversationWith(pending.conversationId)
        ?.messages
        .removeWhere((message) => message.id == clientId);
    _persist();
    notifyListeners();
  }

  /// Works the queue from the front, stopping at the first failure.
  ///
  /// Stopping matters: if the network is down, message two will fail for the
  /// same reason message one did, and hammering the radio through a queue of
  /// them helps nobody. The next reconnect or drain tries again.
  ///
  /// Calling this while a flush is running does not no-op; it asks for another
  /// pass and hands back a future that completes after it.
  Future<void> flushOutbox() {
    final running = _flushing;
    if (running != null) {
      _flushAgain = true;
      return running;
    }
    return _flushing = _runFlush();
  }

  Future<void> _runFlush() async {
    try {
      do {
        _flushAgain = false;
        await _drainQueue();
      } while (_flushAgain && _outbox.isNotEmpty);
    } finally {
      _flushing = null;
      _persist();
      notifyListeners();
    }
  }

  Future<void> _drainQueue() async {
    while (_outbox.isNotEmpty) {
      final pending = _outbox.first;
      try {
        final sent = await _deliver(pending);
        _outbox.removeWhere((entry) => entry.clientId == pending.clientId);
        _setVoiceState(
          pending.conversationId,
          pending.clientId,
          sent ? DeliveryState.sent : DeliveryState.failed,
        );
      } on Object catch (failure) {
        // Re-read rather than reusing the local: _deliver may have written an
        // upload id into the entry, and losing that means uploading again.
        final index = _outbox.indexWhere((entry) => entry.clientId == pending.clientId);
        if (index != -1) {
          _outbox[index] = _outbox[index].copyWith(attempts: _outbox[index].attempts + 1);
        }
        _setVoiceState(pending.conversationId, pending.clientId, DeliveryState.queued);
        _noteIdentityChange(failure);
        _failure = switch (failure) {
          ApiException(:final message) => Failure.server(message),
          IdentityChangedException() => const Failure(FailureKind.identityChanged),
          _ => null,
        };
        break;
      }
    }
  }

  /// Uploads (once) and sends. The upload result is written back into the queue
  /// entry, so a retry after a failed *send* does not upload the same recording
  /// a second time.
  Future<bool> _deliver(PendingSend pending) async {
    var mediaId = pending.mediaId;
    var mediaToken = pending.mediaToken;
    if (mediaId == null) {
      final blob = await _services.api.uploadMedia(pending.sealedBytes);
      mediaId = blob.id;
      mediaToken = blob.token;
      final index = _outbox.indexWhere((p) => p.clientId == pending.clientId);
      if (index != -1) {
        // Both, together. The token is issued once, so a retry that kept the id
        // and lost the token would send a message pointing at a blob nobody can
        // fetch.
        _outbox[index] = pending.copyWith(mediaId: mediaId, mediaToken: mediaToken);
      }
    }

    final payload = MessagePayload.media(
      mediaId: mediaId,
      mediaToken: mediaToken,
      mediaKey: pending.mediaKey,
      mediaType: pending.mediaType,
      byteSize: pending.plainLength,
      fileName: pending.fileName,
      body: pending.caption,
      voiceDurationMs: pending.durationMs,
      waveform: pending.waveform,
      groupKey: pending.isGroup ? pending.groupKey : null,
      expiresInSeconds: pending.expiresInSeconds,
      clientId: pending.clientId,
    );

    if (pending.isGroup) {
      await _services.messaging.sendPayloadToGroup(pending.conversationId, payload);
    } else {
      final username = pending.username;
      if (username == null) return false;
      await _services.messaging.sendPayload(username, payload);
    }

    // Now that it is on the server, the bubble can point at the ciphertext.
    // The token goes with it: `pending` is the entry as it was *before* the
    // upload, so reading it off there would file a record with no capability.
    _attachDelivered(pending, mediaId, mediaToken);
    return true;
  }

  void _attachDelivered(PendingSend pending, String mediaId, String? mediaToken) {
    final conversation = _services.store.conversationWith(pending.conversationId);
    final message = conversation?.messages.where((m) => m.id == pending.clientId).firstOrNull;
    if (conversation == null || message == null) return;
    // The timer starts here, not where the message was recorded: this is the
    // moment it exists anywhere but on this phone.
    final seconds = pending.expiresInSeconds;
    _services.store.replace(
      pending.conversationId,
      pending.clientId,
      message.copyWith(
        state: DeliveryState.sent,
        expiresAt: seconds == null ? null : DateTime.now().add(Duration(seconds: seconds)),
        attachment: Attachment(
          mediaId: mediaId,
          mediaKey: pending.mediaKey,
          mediaToken: mediaToken,
          mediaType: pending.mediaType,
          byteSize: pending.plainLength,
          fileName: pending.fileName,
        ),
      ),
    );
  }

  /// Marks a message as taken by the server, and starts its timer from that
  /// moment — which is the same moment the recipient's starts, seen from the
  /// other side. Anything still waiting to be sent has no expiry at all.
  void _markSent(String conversationId, String clientId, Duration? timer) {
    final message = _services.store
        .conversationWith(conversationId)
        ?.messages
        .where((m) => m.id == clientId)
        .firstOrNull;
    if (message == null) return;
    _services.store.replace(
      conversationId,
      clientId,
      message.copyWith(
        state: DeliveryState.sent,
        expiresAt: timer == null ? null : DateTime.now().add(timer),
      ),
    );
  }

  void _setVoiceState(String conversationId, String clientId, DeliveryState state) =>
      _services.store.updateState(conversationId, clientId, state);

  static String _newClientId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  // --- Disappearing messages ------------------------------------------------

  /// The chat's timer, or null when it is off.
  /// How long a message sent to this chat now would live, or null for never.
  ///
  /// The effective answer, which is what every send path wants: a chat with
  /// its own setting uses that, a chat that follows uses the account's
  /// default, and Saved uses nothing at all. The three-way setting itself is
  /// [chatTimer]; this is what it resolves to.
  Duration? disappearAfter(String conversationId) =>
      _effectiveTimer(_services.store.conversationWith(conversationId));

  Duration? _effectiveTimer(Conversation? conversation) {
    if (conversation == null) return null;
    // Saved is the account's own notebook. Nothing it holds expires, and the
    // account default must not reach into it — see `saved.md`.
    if (isSaved(conversation.id)) return null;
    return conversation.timer.resolve(_defaultDisappearAfter);
  }

  /// What this chat is *set* to: its own duration, off, or following the
  /// account default. What the timer sheet ticks.
  ChatTimer chatTimer(String conversationId) =>
      _services.store.conversationWith(conversationId)?.timer ??
      const ChatTimer.followDefault();

  /// The account-wide default, or null for off.
  ///
  /// Lives in the account's privacy object, so it is the same on every device
  /// this account signs in on and needs no sync of its own.
  Duration? get defaultDisappearAfter => _defaultDisappearAfter;
  Duration? _defaultDisappearAfter;

  /// Whether this account is allowed to change a chat's timer.
  ///
  /// In a one-to-one chat, both sides are: it is their conversation and there
  /// is nobody else's expectation to break.
  ///
  /// In a group it is the group's rights that decide, and they are the
  /// server's: [GroupInfo.role] is what `GET /v1/groups` last said, never
  /// something this device chose for itself. The same role is checked again on
  /// every device that *receives* a change — see [_senderMayChangeTimer] —
  /// which is what makes this an actual restriction rather than a disabled
  /// button. A patched client can still send the payload; nobody will apply it.
  /// Whether a disappearing timer may be set on this conversation at all.
  ///
  /// Saved keeps what is put in it, and the guard is here — at the one door
  /// every timer change goes through — rather than only in the menu that no
  /// longer offers it. A rule that lives in a widget is a rule the next call
  /// site does not have.
  bool mayChangeDisappearAfter(String conversationId) {
    if (isSaved(conversationId)) return false;
    return _mayChangeDisappearAfter(conversationId);
  }

  bool _mayChangeDisappearAfter(String conversationId) {
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return false;
    final group = conversation.group;
    return group == null || group.isAdmin;
  }

  /// Sets the timer for a chat. It takes effect on messages sent from now on:
  /// the number rides inside each sealed payload, so both sides delete on their
  /// own clocks without the server being told what the setting is.
  ///
  /// The change is also announced in its own right, rather than waiting to ride
  /// on the next real message. Waiting was the old behaviour and it was wrong
  /// in the case that matters most: someone turns disappearing messages on,
  /// says nothing further, and the other side keeps writing into a chat it
  /// still believes is permanent. The announcement is end-to-end encrypted like
  /// everything else, so what the server learns from it is what it learns from
  /// any message — that one went to this conversation at this moment.
  ///
  /// Returns false when the group's rights do not allow it, so the screen can
  /// say so instead of appearing to have worked.
  Future<bool> setDisappearAfter(String conversationId, Duration? timer) =>
      setChatTimer(
        conversationId,
        timer == null ? const ChatTimer.off() : ChatTimer.after(timer),
      );

  /// Sets what a chat is: its own duration, off, or following the account.
  ///
  /// Each change carries a version, one higher than the last this device knew
  /// about, and the account that made it. That is what lets two people who
  /// change the timer in the same minute end up agreeing — see [_adoptTimer].
  ///
  /// Returns false when the group's rights do not allow it, so the screen can
  /// say so instead of appearing to have worked.
  Future<bool> setChatTimer(String conversationId, ChatTimer choice) async {
    if (!mayChangeDisappearAfter(conversationId)) return false;
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return false;
    if (conversation.timer == choice) return true;

    final effectiveBefore = _effectiveTimer(conversation);
    _services.store.setChatTimer(
      conversationId,
      choice,
      version: conversation.timerVersion + 1,
      setBy: accountId,
    );
    final effectiveAfter = _effectiveTimer(conversation);

    // The notice is about what changes for messages, not about which of three
    // radio buttons is ticked: switching a chat from an explicit hour to
    // "follow the account", where the account is also an hour, changes nothing
    // anybody would want a line in the transcript about.
    if (effectiveAfter != effectiveBefore) {
      _noteTimerChange(conversationId, effectiveAfter, by: null);
    }
    _persist();
    notifyListeners();
    await _announceTimer(conversationId, effectiveAfter);
    return true;
  }

  /// Tells the other side — and this account's own other devices — about a
  /// timer that just changed.
  ///
  /// A failure is swallowed. The setting is already true here and rides on the
  /// next message anyway, so a lost announcement costs the other side a notice,
  /// not the protection: what they receive from now on still carries the
  /// number. Throwing would leave the screen showing a change that had been
  /// made and reporting that it had not.
  Future<void> _announceTimer(String conversationId, Duration? timer) async {
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return;
    final payload = MessagePayload.timerChange(
      timer?.inSeconds,
      timerVersion: conversation.timerVersion,
    );
    try {
      if (conversation.group != null) {
        await _services.messaging.sendPayloadToGroup(conversationId, payload);
        return;
      }
      final username = conversation.user?.username;
      if (username == null || username == 'unknown') return;
      await _services.messaging.sendPayload(username, payload);
    } on Object {
      // See above: the setting stands either way.
    }
  }

  /// Whether [senderAccountId] was allowed to change [groupId]'s timer.
  ///
  /// Asked of the server rather than answered from anything the message
  /// carried: a payload claiming its sender is an admin is a payload written by
  /// whoever wanted the timer changed. Timer changes are rare enough that one
  /// request each is cheap, and a request that fails means *not* applying the
  /// change — an unverified change is the one this check exists to stop.
  Future<bool> _senderMayChangeTimer(String groupId, String senderAccountId) async {
    try {
      final members = await _services.messaging.groupMembers(groupId);
      return members.any((m) => m.accountId == senderAccountId && m.isAdmin);
    } on Object {
      return false;
    }
  }

  /// Applies a timer change that arrived on its own.
  ///
  /// [byOwnDevice] marks the copy that came from another of this account's
  /// devices, which reads as this account having changed it — and skips the
  /// group check, because the device that sent it already made it.
  Future<void> _applyTimerChange(
    String conversationId,
    MessagePayload payload, {
    required String senderAccountId,
    bool byOwnDevice = false,
  }) async {
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return;
    if (conversation.group != null &&
        !byOwnDevice &&
        !await _senderMayChangeTimer(conversationId, senderAccountId)) {
      return;
    }
    if (_services.store.conversationWith(conversationId) == null) return;
    _adoptTimer(
      conversationId,
      payload,
      by: byOwnDevice
          ? null
          : _services.store.conversationWith(senderAccountId)?.user?.label ?? 'They',
    );
    _persist();
    notifyListeners();
  }

  /// Writes the line that records a timer change.
  ///
  /// A chat that quietly starts deleting itself is the one way this feature can
  /// hurt someone: they keep writing, and what they wrote is gone. So every
  /// change says so, in the conversation, where they are already looking —
  /// including the changes that arrive from the other side.
  ///
  /// [by] is who made the change, or null for this account.
  void _noteTimerChange(String conversationId, Duration? timer, {required String? by}) {
    final who = by ?? 'You';
    final what = timer == null
        ? 'turned disappearing messages off'
        : 'set disappearing messages to ${describeTimer(timer)}';
    _services.store.append(
      conversationId,
      Message(
        // Not a client id: a notice is written independently on each device
        // from the same fact, never sent, and so never deduplicated against
        // another device's copy.
        id: 'notice-${DateTime.now().microsecondsSinceEpoch}',
        // English, and not what the chat draws: `notice` below is what the
        // bubble renders, in the reader's own language. This stays because
        // everything that is not a bubble still reads `body` — the chat list
        // preview, a notification, an exported archive — and a notice with an
        // empty body would be a blank line in all of them.
        body: '$who $what.',
        sentAt: DateTime.now(),
        isMine: by == null,
        kind: MessageKind.notice,
        // The fact, kept apart from the sentence. See [SystemNotice].
        notice: timer == null
            ? SystemNotice(NoticeKind.timerOff, who: by)
            : SystemNotice(NoticeKind.timerSet, who: by, duration: timer),
        // Deliberately no expiry of its own. The notice is the record that the
        // rule changed; a record that deletes itself under the rule it
        // describes leaves a history nobody can account for.
      ),
    );
  }

  /// How a timer reads in a sentence. One place, because it appears in the
  /// chooser, in the notice it writes, and in the chat's own header.
  static String describeTimer(Duration timer) {
    if (timer.inDays >= 7 && timer.inDays % 7 == 0) {
      final weeks = timer.inDays ~/ 7;
      return weeks == 1 ? '1 week' : '$weeks weeks';
    }
    if (timer.inHours >= 24 && timer.inHours % 24 == 0) {
      final days = timer.inDays;
      return days == 1 ? '1 day' : '$days days';
    }
    if (timer.inMinutes >= 60 && timer.inMinutes % 60 == 0) {
      final hours = timer.inHours;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    if (timer.inSeconds >= 60 && timer.inSeconds % 60 == 0) {
      final minutes = timer.inMinutes;
      return minutes == 1 ? '1 minute' : '$minutes minutes';
    }
    return '${timer.inSeconds} seconds';
  }

  /// Deletes whatever has run out. Runs on a timer and after every drain,
  /// because a message that expired while the app was closed must not reappear.
  void pruneExpired() {
    final gone = _services.store.pruneExpired(DateTime.now());
    if (gone.isEmpty) return;
    // A message whose time ran out has to take its file with it. Without this
    // the bubble disappears while the photo it carried stays decrypted in
    // memory, one tap away in the gallery for the rest of the session.
    for (final message in gone) {
      _forgetAttachment(message);
    }
    _persist();
    notifyListeners();
  }

  /// Fetches, decrypts and files whatever is queued for this device.
  /// Returns whether anything actually arrived.
  ///
  /// The answer travels back to iOS, which uses it to decide how generously to
  /// deliver future background pushes: an app that always claims new data gets
  /// throttled. `false` for a drain that found an empty queue, and for one that
  /// was already in progress — the other drain will report for itself.
  ///
  /// A network failure is a *failure*, not an empty queue, so `ApiException` is
  /// rethrown rather than swallowed into `false`. The screen state is still
  /// updated on the way past, as before.
  Future<bool> drain() async {
    if (_draining) return false;
    _draining = true;
    try {
      final result = await _services.messaging.receive();
      await _fileResult(result);
      // Draining is the one thing that happens regularly, so it is also where
      // someone waiting on a group key gets answered, where anything queued
      // gets another try, and where expired messages go.
      pruneExpired();
      unawaited(_maintainGroupKeys());
      detached(flushOutbox());
      return result.messages.isNotEmpty;
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
      rethrow;
    } finally {
      _draining = false;
    }
  }

  /// Files a decrypted batch, whichever channel it arrived on.
  Future<void> _fileResult(ReceiveResult result) async {
    if (result.messages.isEmpty && result.failures.isEmpty) return;

    // What arrived from whom, so one receipt covers a batch rather than one
    // envelope each.
    // Keyed by who wrote it and, for a group message, which group it was in —
    // the receipt goes back to the author, and has to say which conversation.
    final arrived = <(String, String?), List<String>>{};
    for (final incoming in result.messages) {
      await _fileIncoming(incoming);
      final clientId = incoming.payload.clientId;
      if (clientId != null && !incoming.payload.isControl) {
        arrived
            .putIfAbsent((incoming.senderAccountId, incoming.groupId), () => [])
            .add(clientId);
      }
    }
    await _raiseKeyChanges();
    if (arrived.isNotEmpty) unawaited(_sendDeliveryReceipts(arrived));
    if (result.messages.isNotEmpty) _persist();
    if (result.failures.isNotEmpty) await _handleFailures(result.failures);
    notifyListeners();
  }

  // --- Broken sessions ------------------------------------------------------

  /// How long before the same device is worth another reset.
  ///
  /// A reset consumes one of the other side's one-time prekeys and asks their
  /// app to do work, so a batch of twenty failed envelopes from one device must
  /// not become twenty of them — and a session that is still broken an hour
  /// later is worth one more try, not a loop.
  static const Duration sessionResetInterval = Duration(hours: 1);

  final Map<String, DateTime> _lastSessionReset = {};

  /// What to do with envelopes that would not open.
  ///
  /// Two things, and the first matters more. **Say so in the conversation**:
  /// somebody sent a message, it is gone, and the sender's screen says
  /// delivered. Dropping it silently leaves a hole that reads as an answer
  /// nobody gave — the same reason a deletion leaves a tombstone rather than
  /// closing over the gap.
  ///
  /// Then **repair the session**, because the alternative is that it stays
  /// broken: a ratchet that has gone out of step fails every message after it
  /// too, forever, and the pair of people go on writing to each other into a
  /// conversation that stopped working. Nothing recovers what was already lost;
  /// what this buys is that the next message arrives.
  Future<void> _handleFailures(List<UndecryptableMessage> failures) async {
    final counts = <(String, String?), int>{};
    for (final failure in failures) {
      final sender = failure.senderAccountId;
      if (sender == null) continue;
      final where = (sender, failure.groupId);
      counts[where] = (counts[where] ?? 0) + 1;
    }

    for (final entry in counts.entries) {
      final (sender, groupId) = entry.key;
      _noteUnreadable(
        conversationId: groupId ?? sender,
        senderAccountId: sender,
        count: entry.value,
      );
    }
    _failure = Failure(FailureKind.messagesUnreadable, count: failures.length);
    _persist();

    for (final failure in failures) {
      await _repairSession(failure);
    }
  }

  /// Writes the hole into the conversation it belongs to.
  void _noteUnreadable({
    required String conversationId,
    required String senderAccountId,
    required int count,
  }) {
    if (_services.store.conversationWith(conversationId) == null) return;
    final who = _services.store.conversationWith(senderAccountId)?.user?.label;
    _services.store.append(
      conversationId,
      Message(
        id: 'unreadable-${DateTime.now().microsecondsSinceEpoch}',
        // No body: the notice below carries the fact, and the screen writes the
        // sentence in the language of whoever is looking at it.
        body: '',
        sentAt: DateTime.now(),
        isMine: false,
        kind: MessageKind.undelivered,
        notice: SystemNotice(NoticeKind.unreadable, who: who, count: count),
      ),
    );
  }

  /// Throws away the broken session and asks the sender to start a new one.
  ///
  /// The reset payload carries nothing; sending it *is* the repair. With no
  /// session left here it goes out as a prekey message from a fresh bundle,
  /// and the other side archives its old state the moment that arrives — so
  /// one message puts both directions back on a working ratchet.
  Future<void> _repairSession(UndecryptableMessage failure) async {
    final sender = failure.senderAccountId;
    final deviceIndex = failure.senderDeviceIndex;
    if (sender == null || deviceIndex == null) return;

    final key = '$sender/$deviceIndex';
    final last = _lastSessionReset[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < sessionResetInterval) return;
    _lastSessionReset[key] = now;

    final username = _services.store.conversationWith(sender)?.user?.username;
    if (username == null || username == 'unknown') return;

    try {
      await _services.crypto.resetSession(sender, deviceIndex);
      await _services.messaging.sendPayload(username, const MessagePayload.sessionReset());
    } on Object {
      // The session is gone either way, which is the half that matters: the
      // next message this device sends rebuilds it. A reset that could not go
      // out is retried after the interval, on the next failure.
    }
  }

  Future<void> _fileIncoming(IncomingMessage incoming) async {
    // A session reset has already done its work by arriving: opening it was
    // what rebuilt the ratchet. There is nothing to file and nothing to show.
    if (incoming.payload.isSessionReset) return;
    // A key delivery is machinery, not conversation: it unlocks a channel or a
    // group name and leaves no trace in the chat.
    if (incoming.payload.isKeyDelivery) {
      await _storeDeliveredKey(incoming.payload);
      return;
    }
    // A call signal is machinery too, and the most time-critical of it: an
    // offer that sits in the queue is a phone that never rings.
    final call = incoming.payload.call;
    if (call != null) {
      await _services.calls.handleSignal(
        incoming.senderAccountId,
        call,
        // The envelope’s own timestamp: an offer drained from a queue after a
        // night asleep is not a phone that should ring now.
        sentAt: incoming.receivedAt,
        // Who the session says it was, as opposed to who the server labelled
        // it. A call is the one thing in this app that must not act on the
        // second when it can have the first.
        senderIdentityKey: incoming.senderIdentityKey,
        senderTrust: incoming.senderTrust,
        senderDeviceIndex: incoming.senderDeviceIndex,
      );
      return;
    }
    // A copy of something this account sent from another of its own devices.
    // It is filed as outgoing, in the conversation it names — never as a
    // message from whoever the envelope came from, which is this account.
    final sync = incoming.payload.sync;
    if (sync != null) {
      await _fileOwnSentCopy(sync, incoming);
      return;
    }
    if (incoming.payload.isReceipt) {
      _applyReceipt(incoming.senderAccountId, incoming.payload);
      return;
    }
    if (incoming.payload.isDeletion) {
      _applyDeletion(
        incoming.groupId ?? incoming.senderAccountId,
        incoming.payload,
        byAccountId: incoming.senderAccountId,
        fromOwnDevice: incoming.senderAccountId == accountId,
      );
      return;
    }
    if (incoming.payload.isReaction) {
      _applyReaction(
        incoming.groupId ?? incoming.senderAccountId,
        incoming.senderAccountId,
        incoming.payload,
      );
      return;
    }
    if (incoming.payload.isTyping) {
      // Someone who does not send typing notices does not see them either.
      if (_typingIndicators) _applyTyping(incoming.senderAccountId, incoming.payload);
      return;
    }
    if (incoming.payload.isTimerChange) {
      // A setting, not a sentence: it moves the chat's clock and writes the
      // notice that says so, and must never appear as an empty bubble.
      final where = incoming.groupId ?? incoming.senderAccountId;
      if (_services.store.conversationWith(incoming.senderAccountId)?.user == null) {
        await _resolveSender(incoming.senderAccountId);
      }
      await _applyTimerChange(
        where,
        incoming.payload,
        senderAccountId: incoming.senderAccountId,
      );
      return;
    }

    final groupId = incoming.groupId;
    if (groupId != null) {
      await _fileGroupMessage(groupId, incoming);
      return;
    }

    // First contact from someone not in the address book: the envelope carries
    // only the account id, so the name has to be resolved before the message
    // can be shown against anything but a UUID.
    if (_services.store.conversationWith(incoming.senderAccountId) == null) {
      await _resolveSender(incoming.senderAccountId);
    }
    final payload = incoming.payload;
    // From this account itself: a Saved entry written on another of this
    // account's devices. It belongs in Saved — which is the conversation whose
    // id *is* this account — and it is this account's own writing, so it is
    // drawn as such rather than as something somebody else said.
    if (incoming.senderAccountId == accountId) {
      _fileSavedFromOtherDevice(incoming);
      return;
    }
    if (payload.profileKey != null) {
      // Learning someone's profile key is what makes their picture openable.
      _services.store.upsertUser(
        KnownUser(
          accountId: incoming.senderAccountId,
          username: 'unknown',
          profileKey: payload.profileKey,
        ),
      );
    }
    _adoptTimer(
      incoming.senderAccountId,
      payload,
      by: _services.store.conversationWith(incoming.senderAccountId)?.user?.label ?? 'They',
    );
    _services.store.append(
      incoming.senderAccountId,
      _incomingMessage(incoming.senderAccountId, incoming),
    );
  }

  /// Files a Saved entry that another of this account's devices wrote.
  ///
  /// Deduplicated on the client id, like the sync path beside it: the device
  /// that wrote the entry already has it, and a copy that arrives twice — a
  /// redelivery, a queue drained after a reconnect — must not become a second
  /// note. That is what makes an offline entry safe to write and sync later.
  void _fileSavedFromOtherDevice(IncomingMessage incoming) {
    final me = accountId;
    if (me == null) return;
    final payload = incoming.payload;
    if (payload.isControl) return;

    final clientId = payload.clientId;
    if (clientId != null && _hasMessageWithClientId(me, clientId)) return;

    final sentAt = incoming.receivedAt.toLocal();
    _services.store.append(
      me,
      Message(
        id: 'saved-${incoming.envelopeId}',
        clientId: clientId,
        body: payload.body,
        sentAt: sentAt,
        // Everything in Saved is this account's own.
        isMine: true,
        state: DeliveryState.sent,
        kind: _kindOf(payload),
        voiceDuration: payload.voiceDuration,
        waveform: payload.waveform,
        // Deliberately no `expiresAt`: Saved keeps what is put in it.
        attachment: payload.isMedia
            ? Attachment(
                mediaId: payload.mediaId!,
                mediaKey: payload.mediaKey!,
                mediaToken: payload.mediaToken,
                mediaType: payload.mediaType!,
                byteSize: payload.byteSize!,
                fileName: payload.fileName,
              )
            : null,
        sticker: _stickerIn(payload),
        customEmoji: payload.customEmoji,
      ),
    );
  }

  /// Builds the bubble for an arriving message.
  ///
  /// Files what another of this account's devices sent.
  ///
  /// Without this a second device shows a conversation in which this account
  /// never answered: what arrives is fanned out to every device, what is sent
  /// is known only to the device that sent it.
  Future<void> _fileOwnSentCopy(SyncEnvelope sync, IncomingMessage incoming) async {
    final payload = sync.inner;
    // A deletion is the one piece of machinery that has to cross to this
    // account's own devices: taking a message back on the phone and leaving it
    // on the laptop deletes it nowhere that matters.
    if (payload.isDeletion) {
      _applyDeletion(
        sync.conversationId,
        payload,
        byAccountId: incoming.senderAccountId,
        fromOwnDevice: true,
      );
      return;
    }
    // A timer this account changed on its other device. Applied here so a
    // phone and a laptop cannot disagree about when things vanish — and
    // without the group check, because the device that sent it is this
    // account, which already passed it.
    if (payload.isTimerChange) {
      await _applyTimerChange(
        sync.conversationId,
        payload,
        senderAccountId: incoming.senderAccountId,
        byOwnDevice: true,
      );
      return;
    }
    // The rest of it does not become a bubble, whichever device it came from.
    if (payload.isControl) return;

    final conversationId = sync.conversationId;
    if (!sync.isGroup && _services.store.conversationWith(conversationId) == null) {
      // A conversation this device has never seen — the other device wrote to
      // somebody new. Resolve the name before it can be shown as a UUID.
      await _resolveSender(conversationId);
    }
    if (_services.store.conversationWith(conversationId) == null) return;

    final clientId = payload.clientId;
    if (clientId != null && _hasMessageWithClientId(conversationId, clientId)) {
      // Already here: this device sent it, or the copy arrived twice.
      return;
    }

    _adoptTimer(conversationId, payload);
    final timer = disappearAfter(conversationId);
    final sentAt = incoming.receivedAt.toLocal();
    _services.store.append(
      conversationId,
      Message(
        id: 'sync-${incoming.envelopeId}',
        clientId: clientId,
        body: payload.body,
        sentAt: sentAt,
        // The point of the whole exercise: this account wrote it.
        isMine: true,
        // It reached the server, which is all this device can honestly claim
        // about a message it did not send itself.
        state: DeliveryState.sent,
        kind: _kindOf(payload),
        voiceDuration: payload.voiceDuration,
        waveform: payload.waveform,
        expiresAt: timer == null ? null : sentAt.add(timer),
        replyToId: payload.replyToId,
        replyPreview: payload.replyPreview,
        replySender: payload.replySender,
        attachment: payload.isMedia
            ? Attachment(
                mediaId: payload.mediaId!,
                mediaKey: payload.mediaKey!,
                mediaToken: payload.mediaToken,
                mediaType: payload.mediaType!,
                byteSize: payload.byteSize!,
                fileName: payload.fileName,
              )
            : null,
        sticker: _stickerIn(payload),
        customEmoji: payload.customEmoji,
      ),
    );
  }

  /// What kind of message a payload makes.
  ///
  /// One place rather than the same three-deep ternary in both builders — the
  /// sync path and the receive path had drifted apart before, and a sticker
  /// that rendered as a bubble on one's own other device and a picture on
  /// everybody else's would be exactly that bug again.
  static MessageKind _kindOf(MessagePayload payload) {
    if (payload.isSticker) return MessageKind.sticker;
    if (payload.isVoice) return MessageKind.voice;
    if (payload.isMedia) return _kindFor(payload.mediaType!);
    return MessageKind.text;
  }

  bool _hasMessageWithClientId(String conversationId, String clientId) =>
      _services.store
          .conversationWith(conversationId)
          ?.messages
          .any((message) => message.clientId == clientId) ??
      false;

  /// One place for both the direct and the group path, because a voice message
  /// that came through a group is the same message with a name on it — and the
  /// last time these were written twice, one of them forgot the attachment.
  Message _incomingMessage(
    String conversationId,
    IncomingMessage incoming, {
    String? senderName,
  }) {
    final payload = incoming.payload;
    final timer = disappearAfter(conversationId);
    final receivedAt = incoming.receivedAt.toLocal();
    return Message(
      id: 'envelope-${incoming.envelopeId}',
      clientId: payload.clientId,
      body: payload.body,
      sentAt: receivedAt,
      isMine: false,
      senderName: senderName,
      senderAccountId: incoming.senderAccountId,
      kind: _kindOf(payload),
      voiceDuration: payload.voiceDuration,
      waveform: payload.waveform,
      // The timer starts when it arrives here, from the sender's number. Both
      // sides run their own clock; neither asks the server.
      expiresAt: timer == null ? null : receivedAt.add(timer),
      replyToId: payload.replyToId,
      replyPreview: payload.replyPreview,
      replySender: payload.replySender,
      attachment: payload.isMedia
          ? Attachment(
              mediaId: payload.mediaId!,
              mediaKey: payload.mediaKey!,
              mediaToken: payload.mediaToken,
              mediaType: payload.mediaType!,
              byteSize: payload.byteSize!,
              fileName: payload.fileName,
            )
          : null,
      sticker: _stickerIn(payload),
      customEmoji: payload.customEmoji,
    );
  }

  /// Adopts the sender's disappearing-message setting.
  ///
  /// A timer only works if both sides keep it, and the sender is the one who
  /// chose it — so it travels with the message rather than being negotiated.
  /// [by] names who changed it, for the notice. Null means this account's own
  /// other device, which reads the same as changing it here.
  void _adoptTimer(String conversationId, MessagePayload payload, {String? by}) {
    // Saved keeps what is put in it. A timer arriving with an entry — from an
    // older build, from a copy of a message that carried one, from anywhere —
    // must not start deleting somebody's notes, and the chats' own timer is
    // never applied here either. If a timer for Saved is ever offered it will
    // be set on this screen and confirmed there, not inherited.
    if (isSaved(conversationId)) return;
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null) return;

    final seconds = payload.expiresInSeconds;
    // Clamped on the way in as well as on the way out. A message from an older
    // build can carry a week; this device will not start keeping things for a
    // week because somebody else's app offered it.
    final capped = seconds == null || seconds <= 0
        ? null
        : Duration(seconds: seconds > maxDisappearSeconds ? maxDisappearSeconds : seconds);
    final incoming = capped == null ? const ChatTimer.off() : ChatTimer.after(capped);

    // Which change wins when two arrive at once.
    //
    // Higher version wins. Equal versions are broken by comparing the two
    // account ids — an arbitrary rule, but the *same* arbitrary rule on both
    // devices, which is what makes them agree instead of trading updates. A
    // change that loses is dropped silently: announcing the winner back would
    // be the loop this exists to avoid, and the next real message carries the
    // agreed number anyway.
    final version = payload.timerVersion ?? conversation.timerVersion + 1;
    final mine = conversation.timerSetBy ?? '';
    final theirs = by ?? '';
    if (version < conversation.timerVersion) return;
    if (version == conversation.timerVersion && theirs.compareTo(mine) <= 0) return;

    final before = _effectiveTimer(conversation);
    _services.store.setChatTimer(conversationId, incoming, version: version, setBy: by);
    final after = _effectiveTimer(conversation);
    if (after != before) _noteTimerChange(conversationId, after, by: by);
  }

  /// Files a key that someone sealed to this device after it joined by a link.
  ///
  /// The sender is not checked against a list of admins: only someone who could
  /// already read the thing has the key to send, and a key that does not open
  /// the content is simply a key that never gets used.
  Future<void> _storeDeliveredKey(MessagePayload payload) async {
    final scopeId = payload.keyScopeId;
    final key = payload.deliveredKey;
    if (scopeId == null || key == null) return;

    if (payload.keyScope == 'channel') {
      // Which version this is. A delivery from a client that predates
      // versioning is epoch 1, which is what such a client holds.
      //
      // Filed under its own epoch and never over another: a key that arrives
      // late — a redelivery, or a replay of an old rotation — lands in the slot
      // it belongs to and cannot displace the current one. That is what stops a
      // stale event from putting a channel back on a key a removed member has.
      final epoch = payload.keyEpoch ?? 1;
      // rememberKey signals the channel screens, so a feed of padlocks unlocks
      // where the reader is already looking at it.
      await _services.channels
          .rememberKey(scopeId, epoch, Uint8List.fromList(base64Decode(key)));
      return;
    }
    if (payload.keyScope == 'group') {
      _services.store.upsertGroup(
        GroupInfo(groupId: scopeId, role: 'member', groupKey: key),
      );
      unawaited(refreshGroups());
    }
  }

  /// Files a message that arrived through a group.
  ///
  /// A group message can be the first thing this device hears about the group,
  /// so the listing is refreshed rather than the message dropped.
  Future<void> _fileGroupMessage(String groupId, IncomingMessage incoming) async {
    if (_services.store.conversationWith(groupId) == null) {
      await refreshGroups();
      _services.store.upsertGroup(GroupInfo(groupId: groupId, role: 'member'));
    }
    if (incoming.payload.groupKey != null) {
      _services.store.upsertGroup(
        GroupInfo(groupId: groupId, role: 'member', groupKey: incoming.payload.groupKey),
      );
      unawaited(refreshGroups());
    }

    // In a group the sender is often someone not in your contacts, and a
    // message labelled "Someone" is barely a message at all.
    if (_services.store.conversationWith(incoming.senderAccountId)?.user == null) {
      await _resolveSender(incoming.senderAccountId);
    }
    final senderName = _services.store.conversationWith(incoming.senderAccountId)?.user?.label;
    // No `_adoptTimer` here, deliberately. In a group the timer is the group's
    // setting and only someone the server calls an admin may move it, which is
    // checked once per change on the announcement payload. Reading it back off
    // every ordinary message would hand that same power to every member, one
    // message at a time — and checking the sender's role per message would be
    // a request to the server for each one. The message itself still lives
    // under the group's timer: `_incomingMessage` reads it from the
    // conversation, not from what arrived.
    _services.store.append(
      groupId,
      _incomingMessage(groupId, incoming, senderName: senderName ?? 'Someone'),
    );
  }

  /// Puts a name to an account id, falling back to a short id if the lookup
  /// fails — an unnamed message is still better than a dropped one.
  Future<void> _resolveSender(String accountId) async {
    try {
      final profile = await _services.api.lookupById(accountId);
      _services.store.upsertUser(
        KnownUser(
          accountId: accountId,
          username: profile['username'] as String,
          displayName: profile['displayName'] as String?,
          avatarMediaId: profile['avatarMediaId'] as String?,
        ),
        authoritative: true,
      );
    } on ApiException {
      _services.store.upsertUser(
        KnownUser(accountId: accountId, username: accountId.substring(0, 8)),
      );
    }
  }

  static MessageKind _kindFor(String mediaType) {
    if (mediaType.startsWith('image/')) return MessageKind.photo;
    if (mediaType.startsWith('video/')) return MessageKind.video;
    if (mediaType.startsWith('audio/')) return MessageKind.voice;
    return MessageKind.file;
  }

  // --- Profile pictures -----------------------------------------------------

  /// Decrypted avatars, keyed by media id. Held in memory only: the picture is
  /// re-derivable, and writing faces to disk in the clear is not worth it.
  final Map<String, Uint8List> _avatarCache = {};

  /// Group pictures, keyed by group id and carrying the media id they are of.
  ///
  /// The pair is what makes replacing a picture show up: the entry is only a
  /// hit while it is still of the id the group currently points at. In memory
  /// only, and on this controller, so it goes with the account.
  final Map<String, (String, Uint8List)> _groupAvatarCache = {};

  /// This account's own picture, once it has been set or loaded.
  Uint8List? ownAvatar;

  /// Whether this run has already found out what the server holds for us.
  ///
  /// Guarded because `refreshContacts` runs whenever a contacts screen opens,
  /// and this costs a request against a rate-limited budget. Left false again
  /// when the attempt failed, so a later refresh retries.
  bool _ownAvatarKnown = false;

  /// Puts this account's own picture back after a restart.
  ///
  /// Avatars are deliberately not written to disk — see `_avatarCache` — so
  /// after a relaunch `ownAvatar` is null while the server still holds the
  /// picture, and the account screen falls back to initials. That reads as
  /// "the picture was lost". It was not: the pointer is on the account and the
  /// key is in the keystore, and this is what asks for both.
  ///
  /// `_loadAvatars` cannot do it — it walks conversations, and this account is
  /// not one of its own contacts.
  Future<void> _restoreOwnAvatar() async {
    if (_ownAvatarKnown) return;
    _ownAvatarKnown = true;
    try {
      final me = await _services.api.me();
      final mediaId = me['avatarMediaId'] as String?;
      if (mediaId == null) {
        // Answered: there is none. Not a failure, and not worth asking again.
        ownAvatar = null;
        return;
      }
      ownAvatar = await _services.messaging.openAvatar(
        mediaId,
        await _services.crypto.profileKey(),
      );
      notifyListeners();
    } on Object {
      // Offline, or a blob that is not there any more. The initials stand in,
      // and the next refresh tries again rather than leaving it decided.
      _ownAvatarKnown = false;
    }
  }

  /// The picture for a conversation, whichever kind it is.
  ///
  /// One question from a screen's point of view — "what do I draw here" — with
  /// the two caches behind it, so a chat header does not have to know whether
  /// it is looking at a person or a group.
  Uint8List? avatarFor(String conversationId) =>
      _avatarCache[conversationId] ?? _groupAvatarCache[conversationId]?.$2;

  /// Downloads and opens the pictures of everyone we have both a pointer and a
  /// key for. Quiet on failure — a missing avatar is a cosmetic problem.
  Future<void> _loadAvatars() async {
    var loaded = false;
    for (final conversation in _services.store.conversations()) {
      final user = conversation.user;
      if (user == null) continue;
      if (!user.hasAvatar || _avatarCache.containsKey(user.accountId)) continue;
      try {
        _avatarCache[user.accountId] = await _services.messaging.openAvatar(
          user.avatarMediaId!,
          base64Decode(user.profileKey!),
        );
        loaded = true;
      } on Object {
        // Leave it out; the initials stand in perfectly well.
      }
    }
    if (loaded) notifyListeners();
  }

  /// Sets this account's profile picture: resized, stripped, sealed with the
  /// profile key, uploaded, and pointed at.
  ///
  /// Returns false when the file was not a decodable image.
  Future<bool> setOwnAvatar(Uint8List picked) async {
    final prepared = await AvatarImage.prepare(picked);
    if (prepared == null) {
      _failure = const Failure(FailureKind.notAnImage);
      notifyListeners();
      return false;
    }
    try {
      await _services.messaging.uploadAvatar(prepared);
      ownAvatar = prepared;
      _ownAvatarKnown = true;
      _failure = null;
      notifyListeners();
      return true;
    } on Object catch (failure) {
      _failure = Failure.of(failure, FailureKind.couldNotSetPicture);
      notifyListeners();
      return false;
    }
  }

  Future<void> removeOwnAvatar() async {
    try {
      await _services.api.clearAvatar();
      ownAvatar = null;
      _ownAvatarKnown = true;
      _failure = null;
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
    }
    notifyListeners();
  }

  /// Marks a chat read, and tells the other side so — if that is switched on.
  ///
  /// The receipt names the messages by the sender's own ids, so it means "these
  /// ones", not "everything up to now": the second is a claim this device
  /// cannot honestly make about messages it has not seen.
  void markRead(String conversationId) {
    final conversation = _services.store.conversationWith(conversationId);
    // In a group the unread messages have several authors, and each of them
    // gets told about their own — one receipt to the group would tell everybody
    // what one person read.
    final unread = conversation != null && conversation.isGroup
        ? _services.store.unreadBySender(conversationId)
        : {
            if (conversation?.user?.accountId != null)
              conversation!.user!.accountId: _services.store.unreadClientIds(conversationId),
          };
    _services.store.markRead(conversationId);
    _persist();
    notifyListeners();

    if (!_readReceipts) return;
    for (final entry in unread.entries) {
      if (entry.value.isEmpty) continue;
      final username = _services.store.conversationWith(entry.key)?.user?.username;
      if (username == null) continue;
      unawaited(
        _services.messaging
            .sendReceipt(
              username: username,
              clientIds: entry.value,
              kind: 'read',
              groupId: conversation!.isGroup ? conversationId : null,
            )
            .catchError((_) {}),
      );
    }
  }

  /// Publishes fresh prekeys if the server's pool has run down.
  Future<void> maintainKeys() async {
    try {
      await _services.messaging.maintainPreKeys();
      // The signed prekey is what a stranger seals to when the one-time pool
      // is empty, and it is the same key for everyone until it is replaced.
      // `rotateSignedPreKey` had been written, documented as something clients
      // do on a schedule, and called by nothing.
      await _services.messaging.rotateSignedPreKeyIfDue();
    } on ApiException catch (failure) {
      _failure = Failure.server(failure.message);
      notifyListeners();
    }
  }
}
