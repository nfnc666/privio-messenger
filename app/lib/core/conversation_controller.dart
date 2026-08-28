import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/message_store.dart';
import '../data/outbox.dart';
import '../media/attachment.dart';
import '../media/avatar.dart';
import '../media/metadata_scrubber.dart';
import '../media/voice.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../services/messaging_service.dart';
import '../services/realtime_connection.dart';
import '../models/models.dart';
import 'api_client.dart';
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
  Timer? _saveDebounce;
  bool _draining = false;

  List<Contact> _contacts = const [];
  String? _error;

  List<Contact> get contacts => _contacts;

  /// The last failure worth showing, or null. Cleared when the next call works.
  String? get error => _error;

  bool get readReceiptsEnabled => _readReceipts;
  bool get typingIndicatorsEnabled => _typingIndicators;

  /// True while the other side of [conversationId] is typing.
  bool isTyping(String conversationId) =>
      _typingIndicators &&
      (_services.store.conversationWith(conversationId)?.isTypingAt(DateTime.now()) ?? false);

  List<ChatSummary> get chats => [
        for (final conversation in _services.store.conversations())
          _summarise(conversation),
      ];

  List<Message> messagesWith(String accountId) =>
      _services.store.conversationWith(accountId)?.messages ?? const [];

  ChatSummary _summarise(Conversation conversation) {
    final last = conversation.lastMessage;
    return ChatSummary(
      id: conversation.id,
      title: conversation.title,
      isGroup: conversation.isGroup,
      avatarBytes: _avatarCache[conversation.id],
      // Typing replaces the preview rather than sitting beside it: the row has
      // one line, and what someone is doing now beats what they said before.
      preview: isTyping(conversation.id) ? 'typing…' : _previewOf(last),
      typing: isTyping(conversation.id),
      timestamp: last == null ? '' : _formatTimestamp(last.sentAt),
      unreadCount: conversation.unreadCount,
      previewKind: last?.kind ?? MessageKind.text,
      avatarSeed: conversation.id.hashCode.abs(),
    );
  }

  /// A file with no caption still needs a line in the list.
  static String _previewOf(Message? message) {
    if (message == null) return '';
    if (message.body.isNotEmpty) return message.body;
    final attachment = message.attachment;
    if (attachment == null) return '';
    return attachment.fileName ??
        switch (message.kind) {
          MessageKind.photo => 'Photo',
          MessageKind.video => 'Video',
          MessageKind.voice => 'Voice message',
          _ => 'File',
        };
  }

  static String _formatTimestamp(DateTime when) {
    final now = DateTime.now();
    final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
    if (sameDay) {
      return '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (when.year == yesterday.year && when.month == yesterday.month && when.day == yesterday.day) {
      return 'Yesterday';
    }
    return '${when.day.toString().padLeft(2, '0')}.${when.month.toString().padLeft(2, '0')}.';
  }

  /// Reads the sealed history back so a relaunch does not start blank.
  Future<void> restore() async {
    final contents = await _services.archive.load();
    if (contents.conversations.isEmpty && contents.outbox.isEmpty) return;
    _services.store.restore(contents.conversations);
    _outbox
      ..clear()
      ..addAll(contents.outbox);
    // A message queued before the app was killed is still owed to somebody.
    _services.store.pruneExpired(DateTime.now());
    notifyListeners();
    unawaited(flushOutbox());
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

  /// Writes the history back, coalescing bursts: a fast exchange should not
  /// re-seal and rewrite the whole archive once per keystroke.
  void _persist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(
        _services.archive.save(_services.store.conversations(), outbox: _outbox),
      );
    });
  }

  /// Flushes any pending write. Called when the app goes to the background.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    await _services.archive.save(_services.store.conversations(), outbox: _outbox);
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
    unawaited(flushOutbox());
  }

  void _openRealtime(String token) {
    if (_realtime != null) return;
    final realtime = RealtimeConnection(
      baseUrl: _services.api.baseUrl,
      token: token,
    );
    _realtime = realtime;
    _realtimeEnvelopes = realtime.envelopes.listen(_onPushedEnvelopes);
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
      _error = failure is ApiException ? failure.message : 'Could not read a message';
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

  Future<void> refreshContacts() async {
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
        );
      }
      unawaited(_loadAvatars());
      _error = null;
    } on ApiException catch (failure) {
      _error = failure.message;
    }
    notifyListeners();
  }

  Contact _toContact(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return Contact(
      id: id,
      username: json['username'] as String,
      displayName: (json['alias'] ?? json['displayName'] ?? json['username']) as String,
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
      _error = failure.message;
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
      unawaited(_loadAvatars());
      return conversation.id;
    } on ApiException catch (failure) {
      _error = failure.message;
      notifyListeners();
      return null;
    }
  }

  /// Seals [text] for every device the recipient has and sends it.
  ///
  /// The message appears immediately as `sending` and only becomes `sent` once
  /// the server has taken it, so the UI never claims delivery it cannot back up.
  Future<void> send(String conversationId, String text) async {
    final conversation = _services.store.conversationWith(conversationId);
    if (conversation == null || text.trim().isEmpty) return;

    final clientId = _newClientId();
    final timer = conversation.disappearAfter;
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
        expiresAt: timer == null ? null : DateTime.now().add(timer),
      ),
    );
    notifyListeners();

    final payload = MessagePayload.text(
      body,
      groupKey: conversation.isGroup ? conversation.group!.groupKey : null,
      expiresInSeconds: timer?.inSeconds,
      // Carried so a retry — this one's or the transport's — is recognisable as
      // the same message rather than delivered twice.
      clientId: clientId,
    );

    try {
      if (conversation.isGroup) {
        await _services.messaging.sendPayloadToGroup(conversationId, payload);
      } else {
        await _services.messaging.sendPayload(conversation.user!.username, payload);
      }
      _services.store.updateState(conversationId, clientId, DeliveryState.sent);
      _error = null;
      _persist();
    } on Object catch (failure) {
      // Leaving it at `sending` would be a lie. Mark it and say why.
      _services.store.updateState(conversationId, clientId, DeliveryState.failed);
      _error = switch (failure) {
        // The one send failure the user can do something about, so it says
        // what rather than repeating the server's wording.
        ApiException(code: 'license_required') =>
          'Activate your license in Settings to send messages.',
        ApiException(:final message) => message,
        _ => 'Could not send message',
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
      _error = failure is ApiException ? failure.message : 'Could not create the group';
      notifyListeners();
      return null;
    }
  }

  /// Reads the groups this account belongs to, opening the names it has keys
  /// for. A group whose key has not arrived yet shows as "Group" until it does.
  Future<void> refreshGroups() async {
    try {
      for (final group in await _services.messaging.listGroups(_services.store)) {
        _services.store.upsertGroup(group);
      }
      _error = null;
      notifyListeners();
      unawaited(_deliverGroupKeys());
    } on ApiException catch (failure) {
      _error = failure.message;
      notifyListeners();
    }
  }

  /// Hands the group name key to anyone who joined by a link.
  ///
  /// A group message would carry the key too, but only once somebody speaks;
  /// this way a new member sees the group's name straight away.
  Future<void> _deliverGroupKeys() async {
    for (final conversation in _services.store.conversations()) {
      final group = conversation.group;
      final key = group?.groupKey;
      if (group == null || key == null) continue;
      try {
        await _services.messaging.deliverGroupKeys(group.groupId, key);
      } on Object {
        continue;
      }
    }
  }

  /// Joins a group from a link and opens it. Returns the group id, or null with
  /// [error] set.
  Future<String?> joinGroupByLink(String link) async {
    final invite = ChannelService.parseInviteLink(link);
    if (invite == null || invite.kind != InviteKind.group) {
      _error = 'That does not look like a Privio group link.';
      notifyListeners();
      return null;
    }
    try {
      final group = await _services.messaging.joinGroupByCode(invite.code);
      _services.store.upsertGroup(group);
      await refreshGroups();
      return group.groupId;
    } on ApiException catch (failure) {
      _error = failure.code == 'group_not_found'
          ? 'That group does not exist, or the link is wrong.'
          : failure.message;
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
    final placeholder = Message(
      id: messageId,
      body: caption,
      sentAt: DateTime.now(),
      isMine: true,
      kind: MessageKind.file,
      state: DeliveryState.sending,
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
            )
          : await _services.messaging.sendAttachment(
              conversation.user!.username,
              file: file,
              fileName: fileName,
            );
      _services.store.updateState(conversationId, messageId, DeliveryState.sent);
      _error = null;
      _persist();
      notifyListeners();
      return report;
    } on Object catch (failure) {
      _error = failure is ApiException ? failure.message : 'Could not send file';
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
          mediaType: attachment.mediaType,
          byteSize: attachment.byteSize,
          fileName: attachment.fileName,
        ),
      );
      return _attachmentCache[attachment.mediaId] = bytes;
    } on Object catch (failure) {
      _error = failure is ApiException ? failure.message : 'Could not open the file';
      notifyListeners();
      return null;
    }
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
  Future<void> loadPrivacy() async {
    try {
      final me = await _services.api.me();
      final privacy = me['privacy'] as Map<String, dynamic>? ?? const {};
      _readReceipts = privacy['readReceipts'] as bool? ?? true;
      _typingIndicators = privacy['typingIndicators'] as bool? ?? true;
      notifyListeners();
    } on Object {
      // Keep whatever is on screen; the settings screen shows the error.
    }
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
  Future<void> _sendDeliveryReceipts(Map<String, List<String>> byConversation) async {
    if (!_readReceipts) return;
    for (final entry in byConversation.entries) {
      final username = _services.store.conversationWith(entry.key)?.user?.username;
      if (username == null) continue;
      try {
        await _services.messaging.sendReceipt(
          username: username,
          clientIds: entry.value,
          kind: 'delivered',
        );
      } on Object {
        // A receipt that did not go out is not worth telling anyone about; the
        // next message from them carries the same information soon enough.
        continue;
      }
    }
  }

  /// Files a receipt that arrived: moves my own messages forward a state.
  void _applyReceipt(String conversationId, MessagePayload payload) {
    final state = payload.receiptKind == 'read'
        ? DeliveryState.read
        : DeliveryState.delivered;
    final changed = _services.store.markStateByClientIds(
      conversationId,
      (payload.receiptIds ?? const []).toSet(),
      state,
    );
    if (changed > 0) _persist();
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
    final timer = conversation.disappearAfter;

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
        expiresAt: timer == null ? null : DateTime.now().add(timer),
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
        _error = failure is ApiException ? failure.message : null;
        break;
      }
    }
  }

  /// Uploads (once) and sends. The upload result is written back into the queue
  /// entry, so a retry after a failed *send* does not upload the same recording
  /// a second time.
  Future<bool> _deliver(PendingSend pending) async {
    var mediaId = pending.mediaId;
    if (mediaId == null) {
      mediaId = await _services.api.uploadMedia(pending.sealedBytes);
      final index = _outbox.indexWhere((p) => p.clientId == pending.clientId);
      if (index != -1) _outbox[index] = pending.copyWith(mediaId: mediaId);
    }

    final payload = MessagePayload.media(
      mediaId: mediaId,
      mediaKey: pending.mediaKey,
      mediaType: pending.mediaType,
      byteSize: pending.plainLength,
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
    _attachDelivered(pending, mediaId);
    return true;
  }

  void _attachDelivered(PendingSend pending, String mediaId) {
    final conversation = _services.store.conversationWith(pending.conversationId);
    final message = conversation?.messages
        .where((m) => m.id == pending.clientId)
        .firstOrNull;
    if (conversation == null || message == null) return;
    _services.store.replace(
      pending.conversationId,
      pending.clientId,
      message.copyWith(
        state: DeliveryState.sent,
        attachment: Attachment(
          mediaId: mediaId,
          mediaKey: pending.mediaKey,
          mediaType: pending.mediaType,
          byteSize: pending.plainLength,
        ),
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
  Duration? disappearAfter(String conversationId) =>
      _services.store.conversationWith(conversationId)?.disappearAfter;

  /// Sets the timer for a chat. It takes effect on messages sent from now on:
  /// the number rides inside each sealed payload, so the other side adopts it
  /// without the server being told anything.
  void setDisappearAfter(String conversationId, Duration? timer) {
    _services.store.setDisappearAfter(conversationId, timer);
    _persist();
    notifyListeners();
  }

  /// Deletes whatever has run out. Runs on a timer and after every drain,
  /// because a message that expired while the app was closed must not reappear.
  void pruneExpired() {
    if (_services.store.pruneExpired(DateTime.now()) == 0) return;
    _persist();
    notifyListeners();
  }

  /// Fetches, decrypts and files whatever is queued for this device.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      await _fileResult(await _services.messaging.receive());
      // Draining is the one thing that happens regularly, so it is also where
      // someone waiting on a group key gets answered, where anything queued
      // gets another try, and where expired messages go.
      pruneExpired();
      unawaited(_deliverGroupKeys());
      unawaited(flushOutbox());
    } on ApiException catch (failure) {
      _error = failure.message;
      notifyListeners();
    } finally {
      _draining = false;
    }
  }

  /// Files a decrypted batch, whichever channel it arrived on.
  Future<void> _fileResult(ReceiveResult result) async {
    if (result.messages.isEmpty && result.failures.isEmpty) return;

    // What arrived from whom, so one receipt covers a batch rather than one
    // envelope each.
    final arrived = <String, List<String>>{};
    for (final incoming in result.messages) {
      await _fileIncoming(incoming);
      final clientId = incoming.payload.clientId;
      if (clientId != null && !incoming.payload.isControl && incoming.groupId == null) {
        arrived.putIfAbsent(incoming.senderAccountId, () => []).add(clientId);
      }
    }
    if (arrived.isNotEmpty) unawaited(_sendDeliveryReceipts(arrived));
    if (result.messages.isNotEmpty) _persist();
    if (result.failures.isNotEmpty) {
      _error = '${result.failures.length} message(s) could not be decrypted';
    }
    notifyListeners();
  }

  Future<void> _fileIncoming(IncomingMessage incoming) async {
    // A key delivery is machinery, not conversation: it unlocks a channel or a
    // group name and leaves no trace in the chat.
    if (incoming.payload.isKeyDelivery) {
      await _storeDeliveredKey(incoming.payload);
      return;
    }
    if (incoming.payload.isReceipt) {
      _applyReceipt(incoming.senderAccountId, incoming.payload);
      return;
    }
    if (incoming.payload.isTyping) {
      // Someone who does not send typing notices does not see them either.
      if (_typingIndicators) _applyTyping(incoming.senderAccountId, incoming.payload);
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
    _adoptTimer(incoming.senderAccountId, payload);
    _services.store.append(
      incoming.senderAccountId,
      _incomingMessage(incoming.senderAccountId, incoming),
    );
  }

  /// Builds the bubble for an arriving message.
  ///
  /// One place for both the direct and the group path, because a voice message
  /// that came through a group is the same message with a name on it — and the
  /// last time these were written twice, one of them forgot the attachment.
  Message _incomingMessage(
    String conversationId,
    IncomingMessage incoming, {
    String? senderName,
  }) {
    final payload = incoming.payload;
    final timer = _services.store.conversationWith(conversationId)?.disappearAfter;
    final receivedAt = incoming.receivedAt.toLocal();
    return Message(
      id: 'envelope-${incoming.envelopeId}',
      clientId: payload.clientId,
      body: payload.body,
      sentAt: receivedAt,
      isMine: false,
      senderName: senderName,
      kind: payload.isVoice
          ? MessageKind.voice
          : payload.isMedia
              ? _kindFor(payload.mediaType!)
              : MessageKind.text,
      voiceDuration: payload.voiceDuration,
      waveform: payload.waveform,
      // The timer starts when it arrives here, from the sender's number. Both
      // sides run their own clock; neither asks the server.
      expiresAt: timer == null ? null : receivedAt.add(timer),
      attachment: payload.isMedia
          ? Attachment(
              mediaId: payload.mediaId!,
              mediaKey: payload.mediaKey!,
              mediaType: payload.mediaType!,
              byteSize: payload.byteSize!,
              fileName: payload.fileName,
            )
          : null,
    );
  }

  /// Adopts the sender's disappearing-message setting.
  ///
  /// A timer only works if both sides keep it, and the sender is the one who
  /// chose it — so it travels with the message rather than being negotiated.
  void _adoptTimer(String conversationId, MessagePayload payload) {
    final seconds = payload.expiresInSeconds;
    final current = _services.store.conversationWith(conversationId)?.disappearAfter;
    final incoming = seconds == null || seconds <= 0 ? null : Duration(seconds: seconds);
    if (incoming == current) return;
    _services.store.setDisappearAfter(conversationId, incoming);
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
      // rememberKey signals the channel screens, so a feed of padlocks unlocks
      // where the reader is already looking at it.
      await _services.channels.rememberKey(scopeId, Uint8List.fromList(base64Decode(key)));
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
    _adoptTimer(groupId, incoming.payload);
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

  /// This account's own picture, once it has been set or loaded.
  Uint8List? ownAvatar;

  Uint8List? avatarFor(String accountId) => _avatarCache[accountId];

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
    final prepared = AvatarImage.prepare(picked);
    if (prepared == null) {
      _error = 'That file is not an image Privio can use.';
      notifyListeners();
      return false;
    }
    try {
      await _services.messaging.uploadAvatar(prepared);
      ownAvatar = prepared;
      _error = null;
      notifyListeners();
      return true;
    } on Object catch (failure) {
      _error = failure is ApiException ? failure.message : 'Could not set the picture';
      notifyListeners();
      return false;
    }
  }

  Future<void> removeOwnAvatar() async {
    try {
      await _services.api.clearAvatar();
      ownAvatar = null;
      _error = null;
    } on ApiException catch (failure) {
      _error = failure.message;
    }
    notifyListeners();
  }

  /// Marks a chat read, and tells the other side so — if that is switched on.
  ///
  /// The receipt names the messages by the sender's own ids, so it means "these
  /// ones", not "everything up to now": the second is a claim this device
  /// cannot honestly make about messages it has not seen.
  void markRead(String accountId) {
    final unread = _services.store.unreadClientIds(accountId);
    _services.store.markRead(accountId);
    _persist();
    notifyListeners();

    if (!_readReceipts || unread.isEmpty) return;
    final username = _services.store.conversationWith(accountId)?.user?.username;
    if (username == null) return;
    unawaited(
      _services.messaging
          .sendReceipt(username: username, clientIds: unread, kind: 'read')
          .catchError((_) {}),
    );
  }

  /// Publishes fresh prekeys if the server's pool has run down.
  Future<void> maintainKeys() async {
    try {
      await _services.messaging.maintainPreKeys();
    } on ApiException catch (failure) {
      _error = failure.message;
      notifyListeners();
    }
  }
}
