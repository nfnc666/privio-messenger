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

/// A group, as this device understands it.
class GroupInfo {
  const GroupInfo({
    required this.groupId,
    required this.role,
    this.name,
    this.groupKey,
    this.memberIds = const [],
  });

  final String groupId;

  /// 'admin' or 'member'.
  final String role;

  /// Decrypted from the group's sealed metadata. Null until the key arrives.
  final String? name;

  /// Base64. Seals the group's name, and reaches members inside end-to-end
  /// encrypted messages — the server stores the sealed name and no key for it.
  final String? groupKey;

  final List<String> memberIds;

  bool get isAdmin => role == 'admin';

  GroupInfo merge({String? name, String? groupKey, List<String>? memberIds, String? role}) =>
      GroupInfo(
        groupId: groupId,
        role: role ?? this.role,
        name: name ?? this.name,
        groupKey: groupKey ?? this.groupKey,
        memberIds: memberIds ?? this.memberIds,
      );
}

/// One conversation and everything this device holds of it.
///
/// Either a direct chat with a person or a group; the screens treat both the
/// same, which is why they share a type.
class Conversation {
  Conversation.direct(KnownUser this.user, {List<Message>? messages})
      : group = null,
        messages = messages ?? <Message>[];

  Conversation.group(GroupInfo this.group, {List<Message>? messages})
      : user = null,
        messages = messages ?? <Message>[];

  final KnownUser? user;
  final GroupInfo? group;
  final List<Message> messages;

  int unreadCount = 0;

  bool get isGroup => group != null;

  /// Addressed by account id for a person, group id for a group.
  String get id => group?.groupId ?? user!.accountId;

  String get title => group != null ? (group!.name ?? 'Group') : user!.label;

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
  Conversation? conversationWith(String id);
  Conversation upsertUser(KnownUser user);
  Conversation upsertGroup(GroupInfo group);
  void append(String id, Message message);
  void markRead(String id);
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
  Conversation? conversationWith(String id) => _conversations[id];

  @override
  Conversation upsertUser(KnownUser user) {
    final existing = _conversations[user.accountId];
    if (existing?.user == null) {
      return _conversations[user.accountId] = Conversation.direct(user);
    }

    // Facts about a person arrive piecemeal — a username from the contact list,
    // a profile key from a message, an avatar pointer from a lookup. Merge them
    // rather than letting the newest partial answer overwrite the rest.
    final merged = existing!.user!.merge(
      username: user.username == 'unknown' ? null : user.username,
      displayName: user.displayName,
      avatarMediaId: user.avatarMediaId,
      profileKey: user.profileKey,
    );
    final replacement = Conversation.direct(merged, messages: existing.messages)
      ..unreadCount = existing.unreadCount;
    return _conversations[user.accountId] = replacement;
  }

  @override
  Conversation upsertGroup(GroupInfo group) {
    final existing = _conversations[group.groupId];
    if (existing?.group == null) {
      return _conversations[group.groupId] = Conversation.group(group);
    }

    // Group facts arrive piecemeal too: the id and role from the listing, the
    // name only once the key has been shared.
    final merged = existing!.group!.merge(
      name: group.name,
      groupKey: group.groupKey,
      memberIds: group.memberIds.isEmpty ? null : group.memberIds,
      role: group.role,
    );
    final replacement = Conversation.group(merged, messages: existing.messages)
      ..unreadCount = existing.unreadCount;
    return _conversations[group.groupId] = replacement;
  }

  @override
  void append(String id, Message message) {
    final conversation = _conversations[id];
    if (conversation == null) return;
    conversation.messages.add(message);
    if (!message.isMine) conversation.unreadCount += 1;
  }

  @override
  void markRead(String id) => _conversations[id]?.unreadCount = 0;

  @override
  void updateState(String id, String messageId, DeliveryState state) {
    final conversation = _conversations[id];
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
        conversations.map((conversation) => MapEntry(conversation.id, conversation)),
      );
  }

  /// Used by sign-out and by the wipe code: nothing readable is left behind.
  @override
  void clear() => _conversations.clear();
}
