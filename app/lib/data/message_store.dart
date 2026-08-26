import '../models/models.dart';

/// A person this device knows about, by account id.
class KnownUser {
  const KnownUser({
    required this.accountId,
    required this.username,
    this.displayName,
    this.avatarMediaId,
    this.profileKey,
  });

  final String accountId;
  final String username;
  final String? displayName;

  /// Points at ciphertext on the server. Useless without [profileKey].
  final String? avatarMediaId;

  /// Base64. Arrives inside an end-to-end encrypted message from this person,
  /// which is why only someone they have written to can see their picture.
  final String? profileKey;

  String get label => displayName ?? username;

  bool get hasAvatar => avatarMediaId != null && profileKey != null;

  KnownUser merge({
    String? username,
    String? displayName,
    String? avatarMediaId,
    String? profileKey,
  }) =>
      KnownUser(
        accountId: accountId,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        // A pointer or key that was never sent must not erase one we already
        // have: partial updates arrive constantly, from different sources.
        avatarMediaId: avatarMediaId ?? this.avatarMediaId,
        profileKey: profileKey ?? this.profileKey,
      );
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
    if (existing == null) {
      return _conversations[user.accountId] = Conversation(user: user);
    }

    // Facts about a person arrive piecemeal — a username from the contact list,
    // a profile key from a message, an avatar pointer from a lookup. Merge them
    // rather than letting the newest partial answer overwrite the rest.
    final merged = existing.user.merge(
      username: user.username == 'unknown' ? null : user.username,
      displayName: user.displayName,
      avatarMediaId: user.avatarMediaId,
      profileKey: user.profileKey,
    );
    final replacement = Conversation(user: merged, messages: existing.messages)
      ..unreadCount = existing.unreadCount;
    return _conversations[user.accountId] = replacement;
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
