import 'package:flutter/foundation.dart';

/// What a member is allowed to do in a channel.
@immutable
class ChannelPermissions {
  const ChannelPermissions({
    this.canPost = false,
    this.canEditChannel = false,
    this.canDeletePosts = false,
    this.canManageMembers = false,
    this.canDeleteChannel = false,
  });

  factory ChannelPermissions.fromJson(Map<String, dynamic>? json) => json == null
      ? const ChannelPermissions()
      : ChannelPermissions(
          canPost: json['canPost'] as bool? ?? false,
          canEditChannel: json['canEditChannel'] as bool? ?? false,
          canDeletePosts: json['canDeletePosts'] as bool? ?? false,
          canManageMembers: json['canManageMembers'] as bool? ?? false,
          canDeleteChannel: json['canDeleteChannel'] as bool? ?? false,
        );

  final bool canPost;
  final bool canEditChannel;
  final bool canDeletePosts;
  final bool canManageMembers;
  final bool canDeleteChannel;

  Map<String, dynamic> toJson() => {
        'canPost': canPost,
        'canEditChannel': canEditChannel,
        'canDeletePosts': canDeletePosts,
        'canManageMembers': canManageMembers,
        'canDeleteChannel': canDeleteChannel,
      };
}

enum ChannelVisibility { public, private }

@immutable
class ChannelInfo {
  const ChannelInfo({
    required this.id,
    required this.visibility,
    required this.title,
    this.handle,
    this.description,
    this.category,
    this.memberCount = 0,
    this.role,
    this.permissions = const ChannelPermissions(),
    this.inviteCode,
    this.restrictSaving = false,
    this.hasKey = false,
  });

  final String id;
  final ChannelVisibility visibility;

  /// Plaintext for a public channel; decrypted from sealed metadata for a
  /// private one, or a placeholder until the key arrives.
  final String title;

  final String? handle;
  final String? description;
  final String? category;
  final int memberCount;

  /// Null when this account is not a member.
  final String? role;
  final ChannelPermissions permissions;

  /// Only returned to someone who may invite.
  final String? inviteCode;

  final bool restrictSaving;

  /// Whether this device holds the key that opens the channel's posts.
  final bool hasKey;

  /// "1 member", not "1 members".
  String get memberLabel => '$memberCount member${memberCount == 1 ? '' : 's'}';

  bool get isMember => role != null;
  bool get isPublic => visibility == ChannelVisibility.public;

  ChannelInfo copyWith({
    String? title,
    bool? hasKey,
    String? role,
    ChannelPermissions? permissions,
    int? memberCount,
  }) =>
      ChannelInfo(
        id: id,
        visibility: visibility,
        title: title ?? this.title,
        handle: handle,
        description: description,
        category: category,
        memberCount: memberCount ?? this.memberCount,
        role: role ?? this.role,
        permissions: permissions ?? this.permissions,
        inviteCode: inviteCode,
        restrictSaving: restrictSaving,
        hasKey: hasKey ?? this.hasKey,
      );
}

/// One post in a channel, after it has been opened.
@immutable
class ChannelPost {
  const ChannelPost({
    required this.id,
    required this.body,
    required this.createdAt,
    this.authorUsername,
    this.pinned = false,
    this.opened = true,
  });

  final int id;

  /// The decrypted text, or an empty string when [opened] is false.
  final String body;

  final DateTime createdAt;
  final String? authorUsername;
  final bool pinned;

  /// False when this device has no key for the channel, or the post would not
  /// decrypt. Shown as a locked placeholder rather than hidden, so the reader
  /// knows something is there.
  final bool opened;
}

/// Someone in a channel, with what they may do in it.
@immutable
class ChannelMember {
  const ChannelMember({
    required this.id,
    required this.username,
    this.displayName,
    this.role = 'subscriber',
    this.permissions = const ChannelPermissions(),
  });

  factory ChannelMember.fromJson(Map<String, dynamic> json) => ChannelMember(
        id: json['id'] as String,
        username: json['username'] as String? ?? '',
        displayName: json['displayName'] as String?,
        role: json['role'] as String? ?? 'subscriber',
        permissions: ChannelPermissions.fromJson(
          json['permissions'] as Map<String, dynamic>?,
        ),
      );

  final String id;
  final String username;
  final String? displayName;
  final String role;
  final ChannelPermissions permissions;

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin' || isOwner;

  String get label => displayName?.isNotEmpty == true ? displayName! : username;

  ChannelMember copyWith({String? role, ChannelPermissions? permissions}) => ChannelMember(
        id: id,
        username: username,
        displayName: displayName,
        role: role ?? this.role,
        permissions: permissions ?? this.permissions,
      );
}

/// What a Privio join link points at.
enum InviteKind { channel, group }

/// An invite link taken apart.
///
/// It holds only the code, because that is all the link holds: the key that
/// opens the channel's posts is delivered separately, device to device.
@immutable
class ChannelInvite {
  const ChannelInvite({required this.code, required this.kind});

  final String code;
  final InviteKind kind;
}
