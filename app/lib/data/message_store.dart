import 'package:flutter/foundation.dart';
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

/// One person in a group, as the server lists them.
///
/// Not the same as [KnownUser]: this is membership — who is in and what they
/// are allowed to do — which is the server's to answer, because the server is
/// what enforces it.
@immutable
class GroupMember {
  const GroupMember({
    required this.accountId,
    required this.username,
    required this.role,
    this.displayName,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        accountId: json['id'] as String,
        username: json['username'] as String? ?? 'unknown',
        displayName: json['displayName'] as String?,
        role: json['role'] as String? ?? 'member',
      );

  final String accountId;
  final String username;
  final String? displayName;

  /// 'admin' or 'member'.
  final String role;

  bool get isAdmin => role == 'admin';

  String get label => displayName ?? username;
}

/// A group, as this device understands it.
class GroupInfo {
  const GroupInfo({
    required this.groupId,
    required this.role,
    this.name,
    this.groupKey,
    this.inviteCode,
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

  /// The code in the group's join link. Null on a group this device only heard
  /// about through a message.
  final String? inviteCode;

  final List<String> memberIds;

  bool get isAdmin => role == 'admin';

  GroupInfo merge({
    String? name,
    String? groupKey,
    List<String>? memberIds,
    String? role,
    String? inviteCode,
  }) =>
      GroupInfo(
        groupId: groupId,
        role: role ?? this.role,
        name: name ?? this.name,
        groupKey: groupKey ?? this.groupKey,
        inviteCode: inviteCode ?? this.inviteCode,
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

  /// How long a message in this chat lives before it disappears, or null when
  /// the timer is off.
  ///
  /// A per-chat setting, agreed end to end: the sender puts the number inside
  /// each sealed payload, the recipient's device adopts it, and both delete on
  /// their own clocks. The server is never asked.
  Duration? disappearAfter;

  /// Kept at the top of the chat list.
  ///
  /// A local preference, not a property of the conversation: nothing about it
  /// is sent, and the other side has no idea. It rides along in a backup
  /// because it lives in the archive, which is the only place it could be kept
  /// without telling a server which chats matter most to somebody.
  bool pinned = false;

  /// When the other side was last seen typing, or null.
  ///
  /// Deliberately not persisted: "was typing" is only interesting for a few
  /// seconds, and a typing indicator restored from disk would be a lie about
  /// the present.
  DateTime? typingUntil;

  bool isTypingAt(DateTime now) => typingUntil != null && typingUntil!.isAfter(now);

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

  /// Replaces a message in place, keeping its position in the conversation.
  void replace(String id, String messageId, Message message);

  void setDisappearAfter(String id, Duration? timer);

  /// Pins a conversation to the top of the list, or lets it go. Returns
  /// whether anything changed.
  bool setPinned(String id, {required bool pinned});

  /// Marks the other side as typing until [until].
  void setTyping(String id, DateTime? until);

  /// Sets the state of every message whose client id is listed. Returns how
  /// many changed, so a caller can skip a redraw that would change nothing.
  int markStateByClientIds(String id, Set<String> clientIds, DeliveryState state);

  /// The client ids of messages from the other side that are not yet marked
  /// read here — what a read receipt has to name.
  List<String> unreadClientIds(String id);

  /// Records [emoji] from [accountId] on the message with [targetClientId], or
  /// removes their reaction when [emoji] is empty. Returns whether anything
  /// changed.
  bool applyReaction({
    required String conversationId,
    required String targetClientId,
    required String accountId,
    required String emoji,
  });

  /// Takes a message back.
  ///
  /// With [tombstone] the message is replaced by a marker in the same place,
  /// which is the honest thing to show: the other person watched a line
  /// disappear, and a chat that silently closes over the gap invites them to
  /// misremember what was there. Without it the message goes entirely — that
  /// is the "delete for me" case, where nobody else has anything to reconcile.
  ///
  /// Returns whether anything was there to delete.
  bool deleteMessage({
    required String conversationId,
    required String clientId,
    required bool tombstone,
  });

  /// Drops every message whose timer has run out.
  ///
  /// Returns the messages that went, rather than a count: the caller has to be
  /// able to forget what was decrypted from them, and a number cannot say which
  /// files those were.
  List<Message> pruneExpired(DateTime now);

  /// Forgets one conversation entirely — used when the other side is blocked,
  /// where a chat that can never grow again would only be clutter.
  void removeConversation(String id);

  /// Replaces the contents with what was read back from the archive.
  void restore(List<Conversation> conversations);
  void clear();
}

class InMemoryMessageStore implements MessageStore {
  final Map<String, Conversation> _conversations = {};

  @override
  List<Conversation> conversations() {
    // A group with nothing said in it still belongs in the list — someone who
    // joined by a link has to be able to find it before anyone speaks. An empty
    // direct conversation is just a contact, and belongs under Contacts.
    final all = _conversations.values
        .where((c) => c.messages.isNotEmpty || c.isGroup)
        .toList();
    // Pinned first, then most recent, which is the order the chat list shows.
    all.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
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
      ..unreadCount = existing.unreadCount
      ..disappearAfter = existing.disappearAfter
      ..typingUntil = existing.typingUntil;
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
      ..unreadCount = existing.unreadCount
      ..disappearAfter = existing.disappearAfter
      ..typingUntil = existing.typingUntil;
    return _conversations[group.groupId] = replacement;
  }

  @override
  void append(String id, Message message) {
    final conversation = _conversations[id];
    if (conversation == null) return;

    // The same message can arrive twice — a sender who retried before the
    // server had recorded the first attempt, or a second device syncing. The
    // sender's own id is what makes them recognisable as one message.
    final clientId = message.clientId;
    if (clientId != null &&
        conversation.messages.any((existing) => existing.clientId == clientId)) {
      return;
    }

    conversation.messages.add(message);
    // A notice is not something anyone sent, so it is not something anyone has
    // to read: a chat badge for "the timer changed" would be a badge for a
    // message that is not there.
    if (!message.isMine && !message.isNotice) conversation.unreadCount += 1;
  }

  @override
  void replace(String id, String messageId, Message message) {
    final conversation = _conversations[id];
    if (conversation == null) return;
    final index = conversation.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    conversation.messages[index] = message;
  }

  @override
  void setDisappearAfter(String id, Duration? timer) =>
      _conversations[id]?.disappearAfter = timer;

  @override
  void setTyping(String id, DateTime? until) => _conversations[id]?.typingUntil = until;

  @override
  int markStateByClientIds(String id, Set<String> clientIds, DeliveryState state) {
    final conversation = _conversations[id];
    if (conversation == null || clientIds.isEmpty) return 0;

    var changed = 0;
    for (var i = 0; i < conversation.messages.length; i++) {
      final message = conversation.messages[i];
      if (!message.isMine || message.clientId == null) continue;
      if (!clientIds.contains(message.clientId)) continue;
      // Receipts can arrive out of order — a read receipt then a delivered one
      // from a second device. Never walk the state backwards.
      if (message.state.index >= state.index) continue;
      conversation.messages[i] = message.copyWith(state: state);
      changed++;
    }
    return changed;
  }

  @override
  bool setPinned(String id, {required bool pinned}) {
    final conversation = _conversations[id];
    if (conversation == null || conversation.pinned == pinned) return false;
    conversation.pinned = pinned;
    return true;
  }

  @override
  bool deleteMessage({
    required String conversationId,
    required String clientId,
    required bool tombstone,
  }) {
    final conversation = _conversations[conversationId];
    if (conversation == null) return false;
    final index = conversation.messages.indexWhere((m) => m.clientId == clientId);
    if (index == -1) return false;

    final message = conversation.messages[index];
    if (message.kind == MessageKind.deleted) return false;
    if (!tombstone) {
      conversation.messages.removeAt(index);
      return true;
    }
    // Everything the message carried goes: the body, the file it pointed at,
    // the reactions, the quote. What is left is that there was one.
    conversation.messages[index] = Message(
      id: message.id,
      body: '',
      sentAt: message.sentAt,
      isMine: message.isMine,
      kind: MessageKind.deleted,
      state: message.state,
      senderName: message.senderName,
      clientId: message.clientId,
    );
    return true;
  }

  @override
  bool applyReaction({
    required String conversationId,
    required String targetClientId,
    required String accountId,
    required String emoji,
  }) {
    final conversation = _conversations[conversationId];
    if (conversation == null) return false;
    final index =
        conversation.messages.indexWhere((m) => m.clientId == targetClientId);
    // A reaction to a message this device does not have — deleted, expired, or
    // never received — is dropped. There is nothing to attach it to, and
    // inventing a placeholder would be inventing a message.
    if (index == -1) return false;

    final message = conversation.messages[index];
    final reactions = Map<String, String>.from(message.reactions);
    if (emoji.isEmpty) {
      if (reactions.remove(accountId) == null) return false;
    } else {
      if (reactions[accountId] == emoji) return false;
      reactions[accountId] = emoji;
    }
    conversation.messages[index] = message.copyWith(reactions: reactions);
    return true;
  }

  @override
  List<String> unreadClientIds(String id) => [
        for (final message in _conversations[id]?.messages ?? const <Message>[])
          if (!message.isMine && message.clientId != null) message.clientId!,
      ];

  @override
  List<Message> pruneExpired(DateTime now) {
    final removed = <Message>[];
    for (final conversation in _conversations.values) {
      conversation.messages.removeWhere((message) {
        if (!message.hasExpiredAt(now)) return false;
        removed.add(message);
        return true;
      });
    }
    return removed;
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

  @override
  void removeConversation(String id) => _conversations.remove(id);

  /// Used by sign-out and by the wipe code: nothing readable is left behind.
  @override
  void clear() => _conversations.clear();
}
