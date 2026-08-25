import '../models/models.dart';

/// The content shown in the mockups, so every screen can be opened and reviewed
/// against `design/mockups/privio-screens-v1.jpg` before the API is wired in.
///
/// `ChatRepository` swaps this for live data; nothing else in the UI changes.
abstract final class DemoData {
  static const List<ChatSummary> chats = [
    ChatSummary(
      id: 'alice',
      title: 'Alice',
      preview: 'Hey! How are you?',
      timestamp: '11:32',
      unreadCount: 2,
      presence: Presence.online,
      avatarSeed: 1,
    ),
    ChatSummary(
      id: 'project-x',
      title: 'Project X',
      preview: 'Bob: Document.pdf',
      timestamp: '10:45',
      unreadCount: 3,
      isGroup: true,
      previewKind: MessageKind.file,
      avatarSeed: 2,
    ),
    ChatSummary(
      id: 'charlie',
      title: 'Charlie',
      preview: 'Voice message',
      timestamp: '09:12',
      previewKind: MessageKind.voice,
      presence: Presence.online,
      avatarSeed: 3,
    ),
    ChatSummary(
      id: 'family',
      title: 'Family',
      preview: 'Mom: Dinner today?',
      timestamp: 'Yesterday',
      isGroup: true,
      avatarSeed: 4,
    ),
    ChatSummary(
      id: 'david',
      title: 'David',
      preview: 'Photo',
      timestamp: 'Yesterday',
      previewKind: MessageKind.photo,
      avatarSeed: 5,
    ),
  ];

  static List<Message> conversation(String chatId) {
    final today = DateTime.now();
    DateTime at(int hour, int minute) =>
        DateTime(today.year, today.month, today.day, hour, minute);

    return [
      Message(id: '1', body: 'Hey!', sentAt: at(11, 30), isMine: false),
      Message(id: '2', body: 'How are you?', sentAt: at(11, 30), isMine: false),
      Message(
        id: '3',
        body: "I'm good, thanks!",
        sentAt: at(11, 31),
        isMine: true,
        state: DeliveryState.read,
      ),
      Message(
        id: '4',
        body: 'What about you?',
        sentAt: at(11, 31),
        isMine: true,
        state: DeliveryState.delivered,
      ),
      Message(
        id: '5',
        body: 'Voice message',
        sentAt: at(11, 31),
        isMine: true,
        kind: MessageKind.voice,
        voiceDuration: const Duration(seconds: 8),
        state: DeliveryState.sent,
      ),
    ];
  }

  static const List<Contact> contacts = [
    Contact(id: 'alice', username: 'alice', displayName: 'Alice', presence: Presence.online, avatarSeed: 1),
    Contact(id: 'bob', username: 'bob', displayName: 'Bob', presence: Presence.recently, avatarSeed: 2),
    Contact(id: 'charlie', username: 'charlie', displayName: 'Charlie', presence: Presence.online, avatarSeed: 3),
    Contact(id: 'david', username: 'david', displayName: 'David', presence: Presence.recently, avatarSeed: 5),
    Contact(id: 'eve', username: 'eve', displayName: 'Eve', presence: Presence.online, avatarSeed: 6),
    Contact(id: 'frank', username: 'frank', displayName: 'Frank', presence: Presence.recently, avatarSeed: 7),
  ];

  static const List<CallEntry> calls = [
    CallEntry(id: '1', contactName: 'Alice', direction: CallDirection.outgoing, timestamp: '11:32', avatarSeed: 1),
    CallEntry(id: '2', contactName: 'Charlie', direction: CallDirection.incoming, timestamp: '10:21', avatarSeed: 3),
    CallEntry(id: '3', contactName: 'David', direction: CallDirection.outgoing, timestamp: 'Yesterday', avatarSeed: 5),
    CallEntry(id: '4', contactName: 'Project X', direction: CallDirection.incoming, timestamp: 'Yesterday', avatarSeed: 2),
    CallEntry(id: '5', contactName: 'Alice', direction: CallDirection.missed, timestamp: 'Yesterday', avatarSeed: 1),
  ];

  static const List<LinkedDevice> devices = [
    LinkedDevice(
      id: 'this',
      name: 'iPhone 15 Pro',
      platform: 'This device',
      lastActive: 'Active now',
      isCurrent: true,
    ),
    LinkedDevice(id: 'mac', name: 'MacBook Pro', platform: 'macOS', lastActive: 'Last active: 2h ago'),
    LinkedDevice(id: 'ipad', name: 'iPad Pro', platform: 'iPadOS', lastActive: 'Last active: 1d ago'),
    LinkedDevice(id: 'pc', name: 'Windows PC', platform: 'Windows', lastActive: 'Last active: 3d ago'),
  ];
}
