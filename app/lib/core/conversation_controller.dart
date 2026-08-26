import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/message_store.dart';
import '../media/attachment.dart';
import '../media/avatar.dart';
import '../media/metadata_scrubber.dart';
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

  Timer? _poller;
  RealtimeConnection? _realtime;
  StreamSubscription<List<dynamic>>? _realtimeEnvelopes;
  Timer? _saveDebounce;
  bool _draining = false;

  List<Contact> _contacts = const [];
  String? _error;

  List<Contact> get contacts => _contacts;

  /// The last failure worth showing, or null. Cleared when the next call works.
  String? get error => _error;

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
      preview: _previewOf(last),
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
    final conversations = await _services.archive.load();
    if (conversations.isEmpty) return;
    _services.store.restore(conversations);
    notifyListeners();
  }

  /// Writes the history back, coalescing bursts: a fast exchange should not
  /// re-seal and rewrite the whole archive once per keystroke.
  void _persist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_services.archive.save(_services.store.conversations()));
    });
  }

  /// Flushes any pending write. Called when the app goes to the background.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    await _services.archive.save(_services.store.conversations());
  }

  /// Whether the realtime socket is currently up.
  ValueListenable<bool>? get connected => _realtime?.connected;

  /// Opens the realtime socket and starts the fallback poll. Safe to call more
  /// than once.
  void start({String? token}) {
    _poller ??= Timer.periodic(fallbackPollInterval, (_) => drain());
    if (token != null) _openRealtime(token);
    unawaited(drain());
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

    final messageId = DateTime.now().microsecondsSinceEpoch.toString();
    _services.store.append(
      conversationId,
      Message(
        id: messageId,
        body: text.trim(),
        sentAt: DateTime.now(),
        isMine: true,
        state: DeliveryState.sending,
      ),
    );
    notifyListeners();

    try {
      if (conversation.isGroup) {
        await _services.messaging.sendToGroup(
          conversationId,
          text.trim(),
          groupKey: conversation.group!.groupKey,
        );
      } else {
        await _services.messaging.sendToUser(conversation.user!.username, text.trim());
      }
      _services.store.updateState(conversationId, messageId, DeliveryState.sent);
      _error = null;
      _persist();
    } on Object catch (failure) {
      // Leaving it at `sending` would be a lie. Mark it and say why.
      _error = failure is ApiException ? failure.message : 'Could not send message';
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
    // Group attachments need the same per-device fan-out as group text, which
    // is not wired yet; refusing is better than a message that never arrives.
    if (conversation == null || conversation.isGroup) return null;

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
      final report = await _services.messaging.sendAttachment(
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

  /// Fetches, decrypts and files whatever is queued for this device.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      await _fileResult(await _services.messaging.receive());
      // Draining is the one thing that happens regularly, so it is also where
      // someone waiting on a group key gets answered.
      unawaited(_deliverGroupKeys());
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

    for (final incoming in result.messages) {
      await _fileIncoming(incoming);
    }
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
    _services.store.append(
      incoming.senderAccountId,
      Message(
        id: 'envelope-${incoming.envelopeId}',
        body: payload.body,
        sentAt: incoming.receivedAt.toLocal(),
        isMine: false,
        kind: payload.isMedia ? _kindFor(payload.mediaType!) : MessageKind.text,
        attachment: payload.isMedia
            ? Attachment(
                mediaId: payload.mediaId!,
                mediaKey: payload.mediaKey!,
                mediaType: payload.mediaType!,
                byteSize: payload.byteSize!,
                fileName: payload.fileName,
              )
            : null,
      ),
    );
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
    _services.store.append(
      groupId,
      Message(
        id: 'envelope-${incoming.envelopeId}',
        body: incoming.payload.body,
        sentAt: incoming.receivedAt.toLocal(),
        isMine: false,
        senderName: senderName ?? 'Someone',
      ),
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

  void markRead(String accountId) {
    _services.store.markRead(accountId);
    _persist();
    notifyListeners();
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
