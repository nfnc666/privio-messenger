import 'package:flutter/foundation.dart';

import '../core/status_controller.dart' show ProfileStatus;

/// Somebody else's profile, as the server was willing to describe it to *this*
/// account.
///
/// Every optional field here is optional for one of two quite different
/// reasons, and the screen has to keep them apart:
///
/// * **The owner did not set it.** No display name, no status.
/// * **The owner did not let this viewer see it.** `lastSeenAt` and `status`
///   come back null when the target's privacy setting does not include whoever
///   asked — see `server/src/services/presence.ts` and `status.ts`, where that
///   decision is made and where it stays.
///
/// Both arrive as null, and that is deliberate: the client is not told which of
/// the two it is, because being told "this is hidden from you" is itself
/// something the owner did not publish. So the screen shows nothing at all
/// rather than a greyed-out row that announces there is something to see.
///
/// There is no phone number on this object, and that is not an oversight. A
/// number linked for contact discovery is used to *find* people and is never
/// part of what a profile shows: `publicProfile` on the server does not select
/// the column, so there is nothing here to leave out by accident.
@immutable
class ContactProfile {
  const ContactProfile({
    required this.accountId,
    required this.username,
    this.displayName,
    this.avatarMediaId,
    this.lastSeenAt,
    this.status = ProfileStatus.none,
    this.isSelf = false,
    this.isContact = false,
    this.isBlocked = false,
  });

  /// Reads what `GET /v1/users/id/:accountId` returns.
  ///
  /// The id is taken from the answer rather than from whatever was asked for,
  /// so a profile can only ever be filed under the account the server named.
  factory ContactProfile.fromJson(Map<String, dynamic> json) {
    final name = (json['displayName'] as String?)?.trim();
    return ContactProfile(
      accountId: json['id'] as String,
      username: json['username'] as String,
      displayName: (name?.isEmpty ?? true) ? null : name,
      avatarMediaId: json['avatarMediaId'] as String?,
      lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? '')?.toLocal(),
      status: ProfileStatus.fromJson(json['status'] as Map<String, dynamic>?),
      // Defaulting the relationship to "no relationship" rather than throwing:
      // an older server does not send these, and the honest fallback is the
      // state that offers to add rather than one that claims a contact.
      isSelf: json['isSelf'] as bool? ?? false,
      isContact: json['isContact'] as bool? ?? false,
      isBlocked: json['isBlocked'] as bool? ?? false,
    );
  }

  final String accountId;
  final String username;

  /// What they chose to be called, or null if they never set one.
  final String? displayName;

  /// A pointer to their sealed picture. Opening it needs their profile key,
  /// which arrives inside messages and never from the server.
  final String? avatarMediaId;

  /// When the server last heard from them, **or null** — see the note above.
  final DateTime? lastSeenAt;

  /// The line they published, or [ProfileStatus.none] — see the note above.
  final ProfileStatus status;

  /// Whether this profile is the signed-in account's own.
  ///
  /// Decided by the server rather than compared on the client, so one place
  /// answers it. The screen uses it to withhold every action that only makes
  /// sense against somebody else: you do not add, block, report or call
  /// yourself.
  final bool isSelf;

  /// Whether the viewer has them in their address book.
  final bool isContact;

  /// Whether the viewer has blocked them. Never the other way round: the
  /// server does not tell anybody that they have been blocked.
  final bool isBlocked;

  /// What to call them on screen.
  String get label => displayName ?? username;

  ContactProfile copyWith({bool? isContact, bool? isBlocked}) => ContactProfile(
        accountId: accountId,
        username: username,
        displayName: displayName,
        avatarMediaId: avatarMediaId,
        lastSeenAt: lastSeenAt,
        status: status,
        isSelf: isSelf,
        isContact: isContact ?? this.isContact,
        isBlocked: isBlocked ?? this.isBlocked,
      );

  @override
  bool operator ==(Object other) =>
      other is ContactProfile &&
      other.accountId == accountId &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarMediaId == avatarMediaId &&
      other.lastSeenAt == lastSeenAt &&
      other.status == status &&
      other.isSelf == isSelf &&
      other.isContact == isContact &&
      other.isBlocked == isBlocked;

  @override
  int get hashCode => Object.hash(
        accountId,
        username,
        displayName,
        avatarMediaId,
        lastSeenAt,
        status,
        isSelf,
        isContact,
        isBlocked,
      );
}
