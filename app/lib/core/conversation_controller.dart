import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/message_store.dart';
import '../data/outbox.dart';
import '../media/attachment.dart';
import '../media/avatar.dart';
import '../media/metadata_scrubber.dart';
import '../crypto/privio_crypto.dart';
import 'message_search.dart';
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
  StreamSubscription<void>? _realtimeKeyRequests;

  /// Run when somebody is waiting for a key this device might hold. Set by the
  /// app so channels can answer too, since their keys live elsewhere.
  Future<void> Function()? onKeyRequest;
  Timer? _saveDebounce;
  bool _draining = false;

  List<Contact> _contacts = const [];
  String? _error;

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
  String? get error => _error;

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
      _keyChangeAlerts.add(change.accountId);
      await _services.crypto.raiseKeyChangeAlert(change.accountId);
    }
  }

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
    _error = null;
    notifyListeners();
  }

  /// This account's own id, told once at sign-in, so a reaction of mine can be
  /// told apart from somebody else's on the same message.
  String? accountId;

  bool get readReceiptsEnabled => _readReceipts;
  bool get typingIndicatorsEnabled => _typingIndicators;

  /// True while the other side of [conversationId] is typing.
  bool isTyping(String conversationId) =>
      _typingIndicators &&
      (_services.store.conversationWith(conversationId)?.isTypingAt(DateTime.now()) ?? false);

  List<ChatSummary> get chats => [
        for (final conversation in _services.store.conversations()) _summarise(conversation),
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
      pinned: conversation.pinned,
      previewKind: last?.kind ?? MessageKind.text,
      avatarSeed: conversation.id.hashCode.abs(),
    );
  }

  /// A file with no caption still needs a line in the list.
  static String _previewOf(Message? message) {
    if (message == null) return '';
    // A tombstone has no body, and an empty last line in the chat list would
    // read as a conversation with nothing in it.
    if (message.kind == MessageKind.deleted) return 'Message deleted';
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
  Future<void> send(String conversationId, String text, {Message? replyTo}) async {
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
      _error = null;
      _persist();
    } on Object catch (failure) {
      // Leaving it at `sending` would be a lie. Mark it and say why.
      _services.store.updateState(conversationId, clientId, DeliveryState.failed);
      _noteIdentityChange(failure);
      _error = switch (failure) {
        // The one send failure the user can do something about, so it says
        // what rather than repeating the server's wording.
        ApiException(code: 'license_required') => 'Activate your license to send messages.',
        // Refused on purpose: the key on the server is not the key that was
        // pinned. Sending anyway would seal it to whoever holds the new one.
        IdentityChangedException() =>
          'The safety number changed. Nothing was sent — check it before you do.',
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
      unawaited(_maintainGroupKeys());
    } on ApiException catch (failure) {
      _error = failure.message;
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
      _error = failure.message;
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
      _error = failure.message;
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
      _error = 'This device does not have the group key yet.';
      notifyListeners();
      return false;
    }
    try {
      await _services.messaging.renameGroup(groupId, name, key);
    } on ApiException catch (failure) {
      _error = failure.message;
      notifyListeners();
      return false;
    }
    _services.store.upsertGroup(
      GroupInfo(
        groupId: group.groupId,
        role: group.role,
        name: name,
        groupKey: group.groupKey,
        inviteCode: group.inviteCode,
        memberIds: group.memberIds,
      ),
    );
    _persist();
    notifyListeners();
    return true;
  }

  /// Deletes a group for everyone in it. Admins only, enforced by the server.
  Future<bool> deleteGroup(String groupId) async {
    try {
      await _services.api.deleteGroup(groupId);
    } on ApiException catch (failure) {
      _error = failure.message;
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
      // The placeholder was drawn before the file had a name on the server.
      // Now it has one: replace it with the message the recipient will see, so
      // the sender's own bubble shows the file rather than an empty box.
      _services.store.replace(
        conversationId,
        messageId,
        Message(
          id: messageId,
          body: caption,
          sentAt: placeholder.sentAt,
          isMine: true,
          kind: _kindFor(report.mediaType),
          state: DeliveryState.sent,
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
      _error = null;
      _persist();
      notifyListeners();
      return report.report;
    } on Object catch (failure) {
      _noteIdentityChange(failure);
      _error = switch (failure) {
        ApiException(:final message) => message,
        IdentityChangedException() =>
          'The safety number changed. Nothing was sent — check it before you do.',
        _ => 'Could not send file',
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
      _error = failure is ApiException ? failure.message : 'Could not open the file';
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
  Future<void> react(String conversationId, Message target, String emoji) async {
    final me = accountId;
    final clientId = target.clientId;
    if (me == null || clientId == null) return;

    final chosen = target.reactions[me] == emoji ? '' : emoji;
    _services.store.applyReaction(
      conversationId: conversationId,
      targetClientId: clientId,
      accountId: me,
      emoji: chosen,
    );
    _persist();
    notifyListeners();

    final payload = MessagePayload.reaction(reactionTo: clientId, reactionEmoji: chosen);
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
    _error = null;
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
      _error = 'Deleted here. The request to delete it there did not go out.';
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
    );
    if (changed) {
      _persist();
      notifyListeners();
    }
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
    notifyListeners();
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
        _error = switch (failure) {
          ApiException(:final message) => message,
          IdentityChangedException() =>
            'The safety number changed. Nothing was sent — check it before you do.',
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
  Duration? disappearAfter(String conversationId) =>
      _services.store.conversationWith(conversationId)?.disappearAfter;

  /// Sets the timer for a chat. It takes effect on messages sent from now on:
  /// the number rides inside each sealed payload, so the other side adopts it
  /// without the server being told anything.
  ///
  /// The other side learns of it from the next message, not from this call —
  /// there is no separate "timer changed" packet to send, and inventing one
  /// would tell the server that something about this conversation changed at
  /// this moment for no gain.
  void setDisappearAfter(String conversationId, Duration? timer) {
    if (_services.store.conversationWith(conversationId)?.disappearAfter == timer) return;
    _services.store.setDisappearAfter(conversationId, timer);
    _noteTimerChange(conversationId, timer, by: null);
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
        body: '$who $what.',
        sentAt: DateTime.now(),
        isMine: by == null,
        kind: MessageKind.notice,
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
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      await _fileResult(await _services.messaging.receive());
      // Draining is the one thing that happens regularly, so it is also where
      // someone waiting on a group key gets answered, where anything queued
      // gets another try, and where expired messages go.
      pruneExpired();
      unawaited(_maintainGroupKeys());
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
    _error = failures.length == 1
        ? 'A message could not be read'
        : '${failures.length} messages could not be read';
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
    final subject = count == 1 ? 'A message' : '$count messages';
    final from = who == null ? '' : ' from $who';
    _services.store.append(
      conversationId,
      Message(
        id: 'unreadable-${DateTime.now().microsecondsSinceEpoch}',
        body: '$subject$from could not be read. '
            'It was sealed to a key this device no longer has.',
        sentAt: DateTime.now(),
        isMine: false,
        kind: MessageKind.undelivered,
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
    final timer = _services.store.conversationWith(conversationId)?.disappearAfter;
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
        kind: payload.isVoice
            ? MessageKind.voice
            : payload.isMedia
                ? _kindFor(payload.mediaType!)
                : MessageKind.text,
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
      ),
    );
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
    final timer = _services.store.conversationWith(conversationId)?.disappearAfter;
    final receivedAt = incoming.receivedAt.toLocal();
    return Message(
      id: 'envelope-${incoming.envelopeId}',
      clientId: payload.clientId,
      body: payload.body,
      sentAt: receivedAt,
      isMine: false,
      senderName: senderName,
      senderAccountId: incoming.senderAccountId,
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
    );
  }

  /// Adopts the sender's disappearing-message setting.
  ///
  /// A timer only works if both sides keep it, and the sender is the one who
  /// chose it — so it travels with the message rather than being negotiated.
  /// [by] names who changed it, for the notice. Null means this account's own
  /// other device, which reads the same as changing it here.
  void _adoptTimer(String conversationId, MessagePayload payload, {String? by}) {
    final seconds = payload.expiresInSeconds;
    final current = _services.store.conversationWith(conversationId)?.disappearAfter;
    final incoming = seconds == null || seconds <= 0 ? null : Duration(seconds: seconds);
    if (incoming == current) return;
    _services.store.setDisappearAfter(conversationId, incoming);
    _noteTimerChange(conversationId, incoming, by: by);
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
    _adoptTimer(groupId, incoming.payload, by: senderName ?? 'Someone');
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
      _error = failure.message;
      notifyListeners();
    }
  }
}
