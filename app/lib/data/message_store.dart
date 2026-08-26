import '../models/models.dart';

/// A person this device knows about, by account id.
class KnownUser {
  const KnownUser({required this.accountId, required this.username, this.displayName});

  final String accountId;
  final String username;
  final String? displayName;

  String get label => displayName ?? username;
}

/// One conversation and everything this device holds of it.
class Conversation {
  Conversation({required this.user, List<Message>? messages})
      : messages = messages ?? <Message>[];

  final KnownUser user;
  final List<Message> messages;

  int unreadCount = 0;

  Message? get lastMessage => messages.isEmpty ? null : messages.last;
}

/// The decrypted conversations held on this device.
///
/// Everything in here is plaintext, which is exactly why it must end up in an
/// encrypted database: this is the in-memory implementation, and persistence
/// (SQLCipher) is the next milestone. Keeping it behind an interface means the
/// UI will not notice when that lands.
abstract interface class MessageStore {
  List<Conversation> conversations();
  Conversation? conversationWith(String accountId);
  Conversation upsertUser(KnownUser user);
  void append(String accountId, Message message);
  void markRead(String accountId);
  void updateState(String accountId, String messageId, DeliveryState state);

  /// Replaces the contents with what was read back from the archive.
  void restore(List<Conversation> conversations);
  void clear();
}

class InMemoryMessageStore implements MessageStore {
  final Map<String, Conversation> _conversations = {};

  @override
  List<Conversation> conversations() {
    final all = _conversations.values.where((c) => c.messages.isNotEmpty).toList();
    // Most recent first, which is the order the chat list shows.
    all.sort((a, b) {
      final left = a.lastMessage?.sentAt ?? DateTime(0);
      final right = b.lastMessage?.sentAt ?? DateTime(0);
      return right.compareTo(left);
    });
    return all;
  }

  @override
  Conversation? conversationWith(String accountId) => _conversations[accountId];

  @override
  Conversation upsertUser(KnownUser user) {
    final existing = _conversations[user.accountId];
    if (existing != null) {
      // A username can be learned later than the account id, so refresh it.
      if (existing.user.username != user.username ||
          existing.user.displayName != user.displayName) {
        final replacement = Conversation(user: user, messages: existing.messages)
          ..unreadCount = existing.unreadCount;
        _conversations[user.accountId] = replacement;
        return replacement;
      }
      return existing;
    }
    return _conversations[user.accountId] = Conversation(user: user);
  }

  @override
  void append(String accountId, Message message) {
    final conversation = _conversations[accountId];
    if (conversation == null) return;
    conversation.messages.add(message);
    if (!message.isMine) conversation.unreadCount += 1;
  }

  @override
  void markRead(String accountId) => _conversations[accountId]?.unreadCount = 0;

  @override
  void updateState(String accountId, String messageId, DeliveryState state) {
    final conversation = _conversations[accountId];
    if (conversation == null) return;
    final index = conversation.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    conversation.messages[index] = conversation.messages[index].copyWith(state: state);
  }

  @override
  void restore(List<Conversation> conversations) {
    _conversations
      ..clear()
      ..addEntries(
        conversations.map((conversation) => MapEntry(conversation.user.accountId, conversation)),
      );
  }

  /// Used by sign-out and by the wipe code: nothing readable is left behind.
  @override
  void clear() => _conversations.clear();
}
