import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/message_store.dart';
import '../services/messaging_service.dart';
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

  /// How often the queue is drained. The server also pushes over a WebSocket;
  /// wiring that up replaces this poll and is the next step for realtime.
  static const Duration pollInterval = Duration(seconds: 3);

  Timer? _poller;
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
      id: conversation.user.accountId,
      title: conversation.user.label,
      preview: last?.body ?? '',
      timestamp: last == null ? '' : _formatTimestamp(last.sentAt),
      unreadCount: conversation.unreadCount,
      previewKind: last?.kind ?? MessageKind.text,
      avatarSeed: conversation.user.accountId.hashCode.abs(),
    );
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

  /// Starts draining the queue. Safe to call more than once.
  void start() {
    _poller ??= Timer.periodic(pollInterval, (_) => drain());
    unawaited(drain());
  }

  void stop() {
    _poller?.cancel();
    _poller = null;
  }

  @override
  void dispose() {
    stop();
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> refreshContacts() async {
    try {
      final response = await _services.api.contacts();
      _contacts = [
        for (final raw in response['contacts'] as List<dynamic>)
          _toContact(raw as Map<String, dynamic>),
      ];
      // Knowing a contact is enough to show their name against an incoming
      // message, before any conversation exists.
      for (final contact in _contacts) {
        _services.store.upsertUser(
          KnownUser(
            accountId: contact.id,
            username: contact.username,
            displayName: contact.displayName,
          ),
        );
      }
      _error = null;
    } on ApiException catch (failure) {
      _error = failure.message;
    }
    notifyListeners();
  }

  static Contact _toContact(Map<String, dynamic> json) => Contact(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: (json['alias'] ?? json['displayName'] ?? json['username']) as String,
        avatarSeed: (json['id'] as String).hashCode.abs(),
      );

  Future<bool> addContact(String username) async {
    try {
      final added = await _services.api.addContact(username);
      _services.store.upsertUser(
        KnownUser(
          accountId: added['id'] as String,
          username: added['username'] as String,
          displayName: added['displayName'] as String?,
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
        ),
      );
      notifyListeners();
      return conversation.user.accountId;
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
  Future<void> send(String accountId, String text) async {
    final conversation = _services.store.conversationWith(accountId);
    if (conversation == null || text.trim().isEmpty) return;

    final messageId = DateTime.now().microsecondsSinceEpoch.toString();
    _services.store.append(
      accountId,
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
      await _services.messaging.sendToUser(conversation.user.username, text.trim());
      _services.store.updateState(accountId, messageId, DeliveryState.sent);
      _error = null;
      _persist();
    } on Object catch (failure) {
      // Leaving it at `sending` would be a lie. Mark it and say why.
      _error = failure is ApiException ? failure.message : 'Could not send message';
    }
    notifyListeners();
  }

  /// Fetches, decrypts and files whatever is queued for this device.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final result = await _services.messaging.receive();
      if (result.messages.isEmpty && result.failures.isEmpty) return;

      for (final incoming in result.messages) {
        await _fileIncoming(incoming);
      }
      if (result.messages.isNotEmpty) _persist();
      if (result.failures.isNotEmpty) {
        _error = '${result.failures.length} message(s) could not be decrypted';
      }
      notifyListeners();
    } on ApiException catch (failure) {
      _error = failure.message;
      notifyListeners();
    } finally {
      _draining = false;
    }
  }

  Future<void> _fileIncoming(IncomingMessage incoming) async {
    // First contact from someone not in the address book: the envelope carries
    // only the account id, so the name has to be resolved before the message
    // can be shown against anything but a UUID.
    if (_services.store.conversationWith(incoming.senderAccountId) == null) {
      await _resolveSender(incoming.senderAccountId);
    }
    _services.store.append(
      incoming.senderAccountId,
      Message(
        id: 'envelope-${incoming.envelopeId}',
        body: incoming.body,
        sentAt: incoming.receivedAt.toLocal(),
        isMine: false,
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
        ),
      );
    } on ApiException {
      _services.store.upsertUser(
        KnownUser(accountId: accountId, username: accountId.substring(0, 8)),
      );
    }
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
